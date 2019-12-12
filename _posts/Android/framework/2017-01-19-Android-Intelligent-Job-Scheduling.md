---
layout: post
title:  "Android智能任务调度"
categories: "Android-Framework"
tags:  android framework job-scheduling 翻译
author: Jasper
---

* content
{:toc}

本文翻译Android官网对智能任务调度的Guide。



## 概述

```
Modern apps can perform many of their tasks asynchronously, outside the direct flow of user interaction. Some examples of these asynchronous tasks are:
Updating network resources.
Downloading information.
Updating background tasks.
Scheduling system service calls.
```

现代的app能够异步处理多任务，在用户交互界面的后台进行。一些多任务的例子：

- 更新网络资源
- 下载
- 更新后台任务
- 调度系统服务调用

智能调度可以改进app性能，优化系统服务（从`system health`翻译而来），比如优化电池消耗。对应的api请参考[JobScheduler](https://developer.android.com/reference/android/app/job/JobScheduler.html)

这里提供了多个API集供开发者在调度后台任务，主要的API是JobScheduler API。JobScheduler给开发者提供了稳健的多任务调度的可能，甚至还可以使用它来调度系统任务。它还提供高拓展性的功能，比如，开发者既可以使用一个小任务来清除缓存，也可以创建一个大任务来从云服务上同步数据库。

其它可用的APIs可以帮助开发者进行多任务开发：

- AlarmManager
- Firebase JobDispatcher
- Additional Facilities(SyncAdapter, Services)

## Android Framework JobScheduler

JobScheduler从Android5.0(API level 21)被加入，正处于积极的开发阶段，Android7.0 就增加了触发任务的功能，
这个功能的实现是基于对ContentProvider的修改。

JobScheduler在platform层实现，这样使得跨越所有app收集多任务信息成为可能，这些收集来的信息用于调度本app的任务或者其它app的任务。
以这种方式处理批处理作业能让设备进入并保持较长的休眠状态，以节省电量。

我们通过注册任务来使用JobScheduler，并指定任务对网络和时间的要求。然后系统就能在合适的时间时优雅地处理任务的执行，同时会对任务进行一定的延迟处理，
以适应Doze And App Standby的要求。JobScheduler提供了很多方法来定义任务执行条件。

从Android5.0之后，强烈建议使用JobScheduler执行后台任务。

## AlarmManager

AlarmManager是一个调度任务的可选API，它适合于一个app需要在明确的时间发送notification或者弹出一个alarm的情况。只允许在特定的时刻调用AlarmManagerAPI，不允许请求其它由JobScheduler指定的执行条件，比如检测设备休眠和充电状态。

## Firebase JobDispatcher

Android5.0 之前（lower than），Firebase JobDispatcher是JobScheduler的开源兼容版，支持使用Google Play services实现任务调度，也支持其它实现方式。介于此，我们建议在Android5.0之后，统一使用JobScheduler代替Firebase JobDispatcher来实现需要的任务调度功能。

## Additional Facilities

这里提供可选的API，这些可选的API在某种特定的情形下，能给多任务调度更突出的表现。

### SyncAdapter

只能用于与云服务器同步数据的情况，而且它的使用也更加复杂，因为设计authenticatorand content provider 的使用。如果可以，请使用JobScheduler, Firebase JobDispatcher, or GCM Network Manager。

从Android7.0开始，SyncAdapter被部分整合到JobScheduler中了，除非需要使用SyncAdapter的附加功能，否则，你不需要使用SyncAdapterAPI。

### Services

使用Services也能实现多任务功能，Services允许你创建一个后台服务。但是，我们建议你使用前台服务去实现多任务功能，比如说播放音乐，它需要时刻处于用户的控制下。（如果不在控制之下，音乐在后台一直响无法关闭，估计用户会摔手机。-_-'）。尽量避免使用StartServices的方式开启服务，这种服务会常驻后台，长时间占用用户资源即使这个服务并没有执行一些有用的任务，除非逼不得已不要使用。后续的Android，将会不支持使用StartServices的方式启动服务。

## Additional Points

不管你使用什么方式实现多任务调度，请牢记：

- Captive Internet Portals, VPNs, and proxies can pose Internet-connectivity detection problems. A library or API may think the Internet is available, but your service may not be accessible. Fail gracefully and reschedule as few of your tasks as possible.  
Captive Internet Portals, VPNs, and proxies会提示网络连接的检测问题，比如WiFi无法上网会有提示。库或者API会认为连接状态是可用的，只是无法上网，但是app的服务却对网络不可达，认为是无网络连接状态的。
- Depending on the conditions you assign for running a task, such as network availability, after the task is triggered, a change may occur so that those conditions are no longer met. In such a case, your operation may fail unexpectedly and repeatedly. For this reason, you should code your background task logic to notice when tasks are failing persistently, and perform exponential back-off to avoid inadvertently over-using resources.  
基于你给任务设定的触发条件，比如网络可用，当任务被触发后，触发条件会发生变化，比如网络会中断。这样，任务的功能将不能预期重复执行。所以，你应该增强任务逻辑，当检测当触发条件不再可用的时候发出提醒，并做出指数退避（exponential backoff）处理，避免不必要的资源浪费。
- Remember to use exponential backoff when rescheduling any work, especially when using AlarmManager. If your app uses JobScheduler, Firebase JobDispatcher, or sync adapters, exponential backoff is automatically used.  
当使用进行多任务调度的时候，记得使用指数退避（exponential backoff），特别是AlarmManager。当然，JobScheduler, Firebase JobDispatcher, or sync adapters中，指数退避是自动进行的。

**简单的非随机数的指数退避算法**

代码来自网络，把任务间歇使用指数变化范围内的随机数，就是合格指数退避算法。

```
private void retryIn(long interval) {
  boolean success = attemptTransfer();

  if (!success) {
    retryIn(interval*2 < MAX_RETRY_INTERVAL ?
            interval*2 : MAX_RETRY_INTERVAL);
  }
}
```

## 参考文献

- [Intelligent Job-Scheduling](https://developer.android.com/topic/performance/scheduling.html)
- [指数退避算法](http://hugnew.com/?p=814)
