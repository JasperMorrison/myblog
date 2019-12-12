---
layout: post
title: linux/Android中ELF文件格式简要学习指南
categories: Android逆向工程
tags: ELF linux Android
author: Jasper
---

* content
{:toc}



本文记录对ELF文件的分析，借此直观了解ELF文件。

## 源码

```
➜  elf-demo cat elf-demo.c 
#include<stdio.h>

int
main(void){
	printf("elf-demo\n");
}
```

## 得到ELF文件

- 得到linux ELF文件

```
➜  elf-demo gcc -o elf-demo elf-demo.c 
➜  elf-demo file elf-demo
elf-demo: ELF 64-bit LSB  executable, x86-64, version 1 (SYSV), dynamically linked (uses shared libs), for GNU/Linux 2.6.24, BuildID[sha1]=c74c2483765a3ff0eb84e01af94b66d644a4c224, not stripped
➜  elf-demo ./elf-demo 
elf-demo
```

- 得到arm ELF文件

```
➜  elf-demo cat Android.mk
LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := elf-arm 
LOCAL_SRC_FILES := elf-demo.c
include $(BUILD_EXECUTABLE)

➜  elf-demo ~/android-tool/android-ndk-r10e/ndk-build NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=./Android.mk
[armeabi] Compile thumb  : elf-arm <= elf-demo.c
[armeabi] Executable     : elf-arm
[armeabi] Install        : elf-arm => libs/armeabi/elf-arm

➜  elf-demo ls
Android.mk  elf-demo  elf-demo.c  libs  obj
➜  elf-demo file obj/local/armeabi/elf-arm 
obj/local/armeabi/elf-arm: ELF 32-bit LSB  executable, ARM, EABI5 version 1 (SYSV), dynamically linked (uses shared libs), not stripped
```

## ELF文件布局

![](https://upload.wikimedia.org/wikipedia/commons/thumb/7/77/Elf-layout--en.svg/260px-Elf-layout--en.svg.png)  
An ELF file has two views: the program header shows the segments used at run-time, whereas the section header lists the set of sections of the binary.

各个布局详细定义见[EFL wiki](https://en.wikipedia.org/wiki/Executable_and_Linkable_Format#File_layout)

## 参考学习方法

- 详细阅读[《北京大学实验室出的标准版-ELF文件格式》](http://download.csdn.net/detail/jiangwei0910410003/9204051)
- 认真分析非虫对AndroidELF给出的概况图

![](http://img.blog.csdn.net/20151022180146951?watermark/2/text/aHR0cDovL2Jsb2cuY3Nkbi5uZXQv/font/5a6L5L2T/fontsize/400/fill/I0JBQkFCMA==/dissolve/70/gravity/Center)

- 尝试分析自己编译的ELF文件
- 明白Android .oat文件格式与加载原理

## 参考文献

[ELF wiki](https://en.wikipedia.org/wiki/Executable_and_Linkable_Format)  
[SO文件格式](http://blog.csdn.net/jiangwei0910410003/article/details/49336613/)  



