---
layout: post
title: Android AppExitInfoTracker
categories: Android
tags: Android Process
author: Jasper
---

* content
{:toc}

Android是如何感知进程死亡，又是如何处理的呢？基于AppExitInfoTracker，本文将梳理进程的各种原因死亡流程，包括：自杀、被杀、Native Crash、Java Crash。




# 死亡信息管理

通过  `dumpsys activity exit-info` 可以打印出进程的死亡记录，每一条记录都是一个AppExitInfoTracker，记录了进程的死亡原因、死亡时间等诸多内容。

exit info 以被存放在ProcessMap中： `private final ProcessMap<AppExitInfoContainer> mData;`

**exit-info数据结构**

![](/images/Android/framework/AppExitInfoTracker.png)

由于SpareArray实际上是一个Map，所以，该数据结构显得有点复杂，层层嵌套，最终统计了某个进程（以 process name 和 uid 进行区分）的不同 pid 的死亡记录。

**数据更新逻辑**

KillHandler 接受多种消息：

```java
    static final int MSG_LMKD_PROC_KILLED = 4101;
    static final int MSG_CHILD_PROC_DIED = 4102;
    static final int MSG_PROC_DIED = 4103;
    static final int MSG_APP_KILL = 4104;
    static final int MSG_APP_RECOVERABLE_CRASH = 4106;
```

在上述消息中，创建 ApplicationExitInfo，或者更新该对象。如果是更新对象，为了避免 pid 重用问题，同一个 pid 的死亡记录大于 300 秒后不再更新。

# 死亡 tracker 流程

![](/images/Android/framework/AppExitInfoTracker-tracker-route.png)

1. java crash, 走 ART exception -- AMS 
2. native crash，走 crash_dump，可以感知多种终止信号，比如 SIGABRT SIGSEGV SIGBUS SIGILL等
3. 自杀或者被杀，走 父进程 zygote， 通过 socket 通知上层，利用 waitpid() 感知 SIGKILL
4. lmkd查杀，走 lmkd socket
5. AMS 查杀，比如 AMS.killBackgroundProcesses()、多任务查杀、高负载查杀 等等

# 现有缺陷及处理方案

SIGKILL无法明确是自杀还是被杀，本人通过 killed_process tracepoint 获取，解析signal的发送task的uid和pid，并将其转递回AppExitInfoTracker。

# 总结

AppExitInfoTracker 复杂在数据的管理，多重嵌套。  
进程的死亡Tracker，关键点在于SIGKILL的感知，是zygote进程通过waitpid来感知是被SIGKILL所杀。

# 参考

[AppExitInfoTracker.java](https://cs.android.com/android/platform/superproject/+/android14-qpr3-release:frameworks/base/services/core/java/com/android/server/am/AppExitInfoTracker.java)

[RuntimeInit.java](https://cs.android.com/android/platform/superproject/main/+/main:frameworks/base/core/java/com/android/internal/os/RuntimeInit.java)
