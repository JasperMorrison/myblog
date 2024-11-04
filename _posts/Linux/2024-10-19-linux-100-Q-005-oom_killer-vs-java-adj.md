---
layout: post
title: 百问Kernel(5)：oom_killer 与 oom_adj 的关系
categories: Kernel 
tags: Linux oom_killer oom_adj oom_score_adj
author: Jasper
---

* content
{:toc}

你是否思考过，我们在java 看到的OomAdj是什么？其实来源于 kernel中的oom_killer，oom_adj 全称为 `Out of Memory Adjustment`。所以，adj就是Adjustment的缩写。那么，用户空间的adj与内核空间的adj又是什么关系呢？



# 介绍

`·Out of Memory Adjustment`表述的正式oom_killer中对进程占用内存统计量的一个调整值，或者说是惩罚，被惩罚后有的内存占用量就是kill的优先级，这些个名词都指向同一个意思“优先级”。

从前面oom_killer的介绍中，知道adj只使用了oom_score_adj，而没有使用oom_adj，因为oom_score_adj替代了oom_adj.

# adj 的设置

[proc](http://www.aospxref.com/kernel-android14-6.1-lts/xref/fs/proc/base.c) 中给了adj的读写操作：

```c
static const struct file_operations proc_oom_adj_operations = {
	.read		= oom_adj_read,
	.write		= oom_adj_write,
	.llseek		= generic_file_llseek,
};

static const struct file_operations proc_oom_score_adj_operations = {
	.read		= oom_score_adj_read,
	.write		= oom_score_adj_write,
	.llseek		= default_llseek,
};
```

`static int __set_oom_adj(struct file *file, int oom_adj, bool legacy)`

legacy = true : oom_adj，做一个简单的乘法转换为 oom_score_adj
legacy = false : oom_score_adj

> 另外，fork一个进程时，会继承父进程的adj值。

# lmkd 设置 adj

[applyOomAdjLSP](http://www.aospxref.com/android-14.0.0_r2/xref/frameworks/base/services/core/java/com/android/server/am/OomAdjuster.java#applyOomAdjLSP)

流程：

```
OomAdjuster --> applyOomAdjLSP --> ProcessList::setOomAdj --> 
lmkd --> cmd_procprio --> 写节点/proc/[pid]/oom_score_adj
```

```c
snprintf(path, sizeof(path), "/proc/%d/oom_score_adj", params.pid);
snprintf(val, sizeof(val), "%d", params.oomadj);
if (!writefilestring(path, val, false)) {
```

cmd_procprio 还有很多其它的逻辑，参考着看吧。

# 总结

内核空间的adj，用户空间的adj，两者是同一个意思。不同的是，oom_adj是过时的产物，且oom_score_adj通过用户空间来设置。

1. 当一个进程对oom_killer保活，设置 adj 为-1000
2. lmkd/OomAdjuster的adj设置会对内核oom_killer产生影响

