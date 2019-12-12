---
layout: post
title: "从Android源码中编译Apk"
categories: Android
tags: Android Source Compile Apk
author: Jasper
---

* content
{:toc}

本文记录如何从Android源码中单独编译一个可单独安装的Apk。文章来自对问题的解决：  
1. 不执行dex2oat处理
2. 如何把.so文件编译进Apk中？



## Android.mk

第一个问题解决办法： LOCAL_DEX_PREOPT := false  
本人手上的代码，默认是false

第二个问题解决办法： TARGET_BUILD_APPS := true  
默认是false  
开启后会遇到很多问题，多半是某些预编译好的库没有添加，在prebuilt下面。也或者是make 目标依赖不完整。

详细情况每个Android版本源码有差异，需根据实际情况解决，这里不做记录。

Android7 开始采用ninja，有时间了解相关内容才能入手解决问题。

## 参考文献

[makefile = := ?= +=](http://www.cnblogs.com/wanqieddy/archive/2011/09/21/2184257.html)  
