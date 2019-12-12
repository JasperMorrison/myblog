---
layout: post
title: Android Uri Permissions
categories: Android
tags: Android Framework Uri Permissions
author: Jasper
---

* content
{:toc}

# 概述

Android N 开始，建议使用FileProvider进行应用间文件共享， uri permissions是临时授予的。第三方应用一旦结束接受uri permissions的所有Activity，应用将丢失对应的uri  permissions，执行query操作将出现权限问题。




# 权限传递原理

假设有应用A 、B、C，A提供一个FileProvider，B尝试去获得A共享出来的文件。此时B调用A，并在onResult中获得uri 及 uri permissions。可以参考官网的共享策略。如果此时B结束当前的Activity，B将失去uri permissions。如果此时B在持有权限时继续启动C，C将获得uri permissions，可以读取A提供的FileProvider。

# 源码分析

## 权限的授予

打开AMS调试开关：com.android.server.am.ActivityManagerDebugConfig#DEBUG_ALL = true

com.android.server.am.ActivityStarter#startActivityUnchecked ->  
com.android.server.am.ActivityManagerService#grantUriPermissionFromIntentLocked ->  
    com.android.server.am.ActivityManagerService#checkGrantUriPermissionFromIntentLocked（先check，后授权）  
        com.android.server.am.ActivityManagerService#checkGrantUriPermissionLocked  
            com.android.server.am.ActivityManagerService#checkHoldingPermissionsLocked(必须是读写同时授权，否则返回false)(这个函数用户检查当前的权限授权情况，如果读写权限已经授权，不需要往下执行了，否则continue)  

可以通过adb  shell dumpsys activity permissions 查看权限授予情况

## 权限清空

分析finishActivity对uri permissions的处理逻辑

08-21 15:32:33.546  775  1543 V ActivityManager: Clearing app during remove for activity ActivityRecord{c5c15c5 u0 com.android.bluetooth/.opp.BluetoothOppLauncherActivity t10 f}
08-21 15:32:33.547  775  1543 V ActivityManager: Removing 1002 permission to 0 @ content://com.example.fileprovider/name/storage/emulated/0/DCIM/Camera/IMG_20170821_081132.jpg

调用过程：  
com.android.server.am.ActivityStack#destroyActivityLocked  
com.android.server.am.ActivityStack#removeActivityFromHistoryLocked  
com.android.server.am.ActivityRecord#removeUriPermissionsLocked    
com.android.server.am.ActivityManagerService#removeUriPermissionIfNeededLocked  

# 针对实时权限的解决方案

在接受uri permissions的Activity结束前，进行query操作，保存文件路径。然后再考虑结束Activity。（推荐）  
或者将intent的data和flag传递下去。