---
layout: post
title: 百问Kernel(4)：Kernel 内存最后的倔强 oom_killer
categories: Kernel 
tags: Linux oom_killer
author: Jasper
---

* content
{:toc}

Kernel 的 oom_kill 主要解决内核内存紧张的问题，当系统内存不足时，内核会触发 oom_kill 机制，选择性杀掉进程，并利用 reaper 快速清理匿名页。



# 背景

平时看到的 `Out of Memory: Killed process ...` 或者 `Memory cgroup out of memory: Killed process ...` 便是oom killer打的log，来自：  
```c
static void __oom_kill_process(struct task_struct *victim, const char *message)
{
    pr_err("%s: Killed process %d (%s) total-vm:%lukB, anon-rss:%lukB, file-rss:%lukB, shmem-rss:%lukB, UID:%u pgtables:%lukB oom_score_adj:%hd\n",
}
```

# oom 的判定

```
H A D	memcontrol.c	1713 ret = task_is_dying() || out_of_memory(&oc); in mem_cgroup_out_of_memory()
H A D	page_alloc.c	4541 if (out_of_memory(&oc) || in __alloc_pages_may_oom()
H A D	vmscan.c	    4545 out_of_memory(&oc); in lru_gen_age_node()
```

## mem_cgroup_out_of_memory

当cgroup内存不足时，会调用该函数，判断是否需要触发 oom_kill。  

[mm/memcontrol.c](http://www.aospxref.com/kernel-android14-6.1-lts/xref/mm/memcontrol.c)  

`mem_cgroup_oom/memory_max_write --> mem_cgroup_out_of_memory`

更多mem_cgroup逻辑，需要深入mem crgoup分析。

## alloc_pages_may_oom

```c
static inline struct page *
__alloc_pages_may_oom(gfp_t gfp_mask, unsigned int order,
	const struct alloc_context *ac, unsigned long *did_some_progress)
{
    // 尝试分配页面
	page = get_page_from_freelist((gfp_mask | __GFP_HARDWALL) &
				      ~__GFP_DIRECT_RECLAIM, order,
				      ALLOC_WMARK_HIGH|ALLOC_CPUSET, ac);
	if (page)
		goto out;

	/* Coredumps can quickly deplete all memory reserves */
    // core dump 可能会迅速消耗掉所有剩余内存
	if (current->flags & PF_DUMPCORE)
		goto out;
	/* The OOM killer will not help higher order allocs */
    // 申请页面过大，不考虑通过OOM提供更多的内存
	if (order > PAGE_ALLOC_COSTLY_ORDER)
		goto out;

    // 尝试回收的机会用尽了，跳过OOM killer
	if (gfp_mask & (__GFP_RETRY_MAYFAIL | __GFP_THISNODE))
		goto out;
	/* The OOM killer does not needlessly kill tasks for lowmem */
    // 低内存zone不需要oom干预
	if (ac->highest_zoneidx < ZONE_NORMAL)
		goto out;
    // 设备休眠，跳过
	if (pm_suspended_storage())
		goto out;
	
    // 尝试OOM
	if (out_of_memory(&oc) ||
	    WARN_ON_ONCE_GFP(gfp_mask & __GFP_NOFAIL, gfp_mask)) {
		*did_some_progress = 1;

		/*
		 * Help non-failing allocations by giving them access to memory
		 * reserves
		 */
		if (gfp_mask & __GFP_NOFAIL)
            // oom成功了，尝试分配页面
			page = __alloc_pages_cpuset_fallback(gfp_mask, order,
					ALLOC_NO_WATERMARKS, ac);
	}
out:
	mutex_unlock(&oom_lock);
	return page;
}
```

总结起来该函数的逻辑：  
1. 分配成功了，跳过oom
2. core dump、order过大、没有机会了、低内存zone、设备休眠都跳过oom
3. 尝试oom
4. 如果成功oom，再次尝试分配内存页

## lru_gen_age_node

通过`lruvec_is_reclaimable`判断是否有可能回收的内存，如果没有，尝试oom killer来解决。

```c
static void lru_gen_age_node(struct pglist_data *pgdat, struct scan_control *sc)
{
	memcg = mem_cgroup_iter(NULL, NULL, NULL);
	do {
		struct lruvec *lruvec = mem_cgroup_lruvec(memcg, pgdat);

		if (lruvec_is_reclaimable(lruvec, sc, min_ttl)) {
			mem_cgroup_iter_break(NULL, memcg);
            // 有可以回收的lruvec，直接返回，否则，可能会触发oom
			return;
		}

		cond_resched();
	} while ((memcg = mem_cgroup_iter(NULL, memcg, NULL)));

	/*
	 * The main goal is to OOM kill if every generation from all memcgs is
	 * younger than min_ttl. However, another possibility is all memcgs are
	 * either too small or below min.
	 */
     // 如果所有memcgs都小于min_ttl，尝试通过oom killer解决问题
	if (mutex_trylock(&oom_lock)) {
		struct oom_control oc = {
			.gfp_mask = sc->gfp_mask,
		};

		out_of_memory(&oc);

		mutex_unlock(&oom_lock);
	}
}
```

# oom 机制

```c
bool out_of_memory(struct oom_control *oc)
{
    // 当前进程本来就要进行内存清理，那就通过reaper加快这个过程
	if (task_will_free_mem(current)) {
		mark_oom_victim(current);
		queue_oom_reaper(current);
		return true;
	}

    // 是否要发生 panic
	check_panic_on_oom(oc);

    // 查杀正在分配页面的进程， sysctl_oom_kill_allocating_task
	if (!is_memcg_oom(oc) && sysctl_oom_kill_allocating_task &&
	    current->mm && !oom_unkillable_task(current) &&
	    oom_cpuset_eligible(current, oc) &&
	    current->signal->oom_score_adj != OOM_SCORE_ADJ_MIN) {
		get_task_struct(current);
		oc->chosen = current;
		oom_kill_process(oc, "Out of memory (oom_kill_allocating_task)");
		return true;
	}

    // 找到一个bad process 
	select_bad_process(oc);

	/* Found nothing?!?! */
    // 找不到，打印些信息
	if (!oc->chosen) {
		dump_header(oc, NULL);
		pr_warn("Out of memory and no killable processes...\n");
		/*
		 * If we got here due to an actual allocation at the
		 * system level, we cannot survive this and will enter
		 * an endless loop in the allocator. Bail out now.
		 */
		if (!is_sysrq_oom(oc) && !is_memcg_oom(oc))
			panic("System is deadlocked on memory\n");
	}

    // do it now
	if (oc->chosen && oc->chosen != (void *)-1UL)
		oom_kill_process(oc, !is_memcg_oom(oc) ? "Out of memory" :
				 "Memory cgroup out of memory");
	return !!oc->chosen;
}
```

1. 当前进程本来就要进行内存清理，那就通过reaper加快这个过程
2. 是否要发生 panic
3. 查杀正在分配页面的进程， sysctl_oom_kill_allocating_task
4. 找到一个 bad process，如果找不到，打印些信息
5. 杀掉找到的 bad process

# bad process

```c
long oom_badness(struct task_struct *p, unsigned long totalpages)
{
	adj = (long)p->signal->oom_score_adj;
    // 忽略OOM_SCORE_ADJ_MIN，即 -1000
	if (adj == OOM_SCORE_ADJ_MIN ||
			test_bit(MMF_OOM_SKIP, &p->mm->flags) ||
			in_vfork(p)) {
		task_unlock(p);
		return LONG_MIN;
	}

	// 内存占用 == rss + pagetable + swap space
	points = get_mm_rss(p->mm) + get_mm_counter(p->mm, MM_SWAPENTS) +
		mm_pgtables_bytes(p->mm) / PAGE_SIZE;

	/* Normalize to oom_score_adj units */
	adj *= totalpages / 1000;
	points += adj;

	return points;
}
```

通过 内存占用量 及 adj 来计算一个的得分，得分越大越容易被kill。

totalpages ：设备总的page个数，一般是4KB  
adj : oom_score_adj，即 -1000 ~ 1000  
points = rss + pagetable + swap space  

惩罚机制：  
1. 先对adj进行调整，使得adj与内存正相关
2. 如何调整？假设将设备内存分成1000份，一个单位的adj代表进程占用了1份，经过adj计算之后得到的这个偏移量，就是对内存的惩罚
3. 对内存占用量point进行惩罚，最终得到一个bad的得分

可以简单的理解为：**adj越大，对内存的惩罚越大**，内存越大，越bad，越容易被kill

# 参考

[http://www.aospxref.com/kernel-android14-6.1-lts/xref/mm/oom_kill.c](http://www.aospxref.com/kernel-android14-6.1-lts/xref/mm/oom_kill.c)  
