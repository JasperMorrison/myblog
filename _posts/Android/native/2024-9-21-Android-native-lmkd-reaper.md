---
layout: post
title: lmkd reaper 查杀方式
categories: Android
tags: Android lmkd kill pidfd process_mrealease
author: Jasper
---

* content
{:toc}

本文介绍lmkd的查杀方式，如果快速清理内存，与传统的像 pid 发送 signal -9 相比，如何保证查杀行为的稳定性。



# Reaper

Reaper负责向pidfd发送signal，并主动清理进程匿名页。

## init

1. 创建一个线程池

```c++
snprintf(name, sizeof(name), "lmkd_reaper%d", thread_cnt_);
```

所以，我们可以从 killed_process 的 traceprint 中看到lmkd_reaper是 signal 的发送方。

1. 初始化一个queue_来保存 target_proc

```c++
Reaper::target_proc Reaper::dequeue_request() {
    struct target_proc target;
    std::unique_lock<std::mutex> lock(mutex_);

    while (queue_.empty()) {
        cond_.wait(lock);
    }
    target = queue_.back();
    queue_.pop_back();

    return target;
}
```

通过dequeue_request() 来找到需要查杀的目标进程。

## 线程函数 reaper_main

```c++
    for (;;) {
        target = reaper->dequeue_request();

        if (pidfd_send_signal(target.pidfd, SIGKILL, NULL, 0)) {
            goto done;
        }

        if (process_mrelease(target.pidfd, 0)) {
            goto done;
        }
    }
```

等待 queue_ 有查杀任务请求，发送SIGKILL到pidfd，并清理进程匿名页。

# process_mrelease

```c++
#ifndef __NR_process_mrelease
#define __NR_process_mrelease 448
#endif

static int process_mrelease(int pidfd, unsigned int flags) {
    return syscall(__NR_process_mrelease, pidfd, flags);
}
```

由于没有对于的库函数支持，只能通过syscall的方式调用 __NR_process_mrelease。

__NR_process_mrelease 定义在 [oom kill](http://www.aospxref.com/kernel-android14-6.1-lts/xref/mm/oom_kill.c#1200)

```c++
SYSCALL_DEFINE2(process_mrelease, int, pidfd, unsigned int, flags)
{
	if (!test_bit(MMF_OOM_SKIP, &mm->flags) && !__oom_reap_task_mm(mm))
}
```

关键函数是 __oom_reap_task_mm，它主要调用了kernel oom kill 中的 reaper 功能来进行内存清理。

## oom_kill reaper

```c++
static bool __oom_reap_task_mm(struct mm_struct *mm)
{
	struct vm_area_struct *vma;

	for_each_vma(vmi, vma) {
		// 清理匿名页
		if (vma_is_anonymous(vma) || !(vma->vm_flags & VM_SHARED)) {
			unmap_page_range(&tlb, vma, range.start, range.end, NULL);
		}
	}

	return ret;
}
```

它遍历了进程的vma，并逐个调用unmap_page_range来清理匿名页。

# 总结

实际上，借鉴 oom kill， lmkd 通过 pidfd 替代了 signal -9 的方式来清理内存，并主动调用 kernel oom kill reaper 来清理进程匿名页。

pidfd可以获得稳定的查杀行为，即避免了pid重用问题，也是为了保证 process_mrelease 能够正确执行， 同时，reaper直接清理vma， 达到快速释放内存的目的。
 
# 参考

[kernel oom_kill](http://www.aospxref.com/kernel-android14-6.1-lts/xref/mm/oom_kill.c)
