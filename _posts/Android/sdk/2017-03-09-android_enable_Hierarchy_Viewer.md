---
layout: post
title: "Android 在真机上开启Hierarchy Viewer 监控UI"
categories: Android
tags: Android Hierarchy_Viewer
author: Jasper
---

* content
{:toc}

本文记录如何在真机上打开Hierarchy Viewer，让Android SDK monitor能监控实时UI的布局，对UI开发，APP分析和测试给予很大的方便。



### Disable secure

在boot.img -> rootfs -> default.prop中，将 ro.secure 和 ro.adb.secure 属性设置为 0，顺便默认打开adb debug，ro.debuggable=1.

1. 做一个差分包update.zip
2. 或者重刷boot.img

### Run monitor

下载Android SDK，tools->monitor。

Open Perspective -> Hierarchy View 

然后打开app，在界面选择指定的Activiry，即可查看UI.


