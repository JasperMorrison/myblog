---
layout: post
title: Android与Kernel调度交互知识框架
categories: Android
tags: Android Kernel Sched EAS CFS EEVDF cpuset cpufreq walt pelt
author: Jasper
---

* content
{:toc}

在Android原生体系中，是如何考虑调度问题的，Framework层是如何与Kernel交互的，以及如何实现调度策略。Android在调度方面的设计原理，性能与功耗的平衡，以及相关的评估验证指标又是什么呢？（先立个flag，期待1个月完成相关调研）



 
