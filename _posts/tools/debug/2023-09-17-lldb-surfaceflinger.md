---
layout: post
title: 使用lldb远程调试SurfaceFlinger
categories: tools
tags: lldb android SurfaceFlinger
author: Jasper
---

* content
{:toc}

发现，具有十几年研发经验的Android大佬，也有很多都没能折腾出来怎么使用lldb远程调试SurfaceFlinger，看来这个东西经验很重要，特此记录，让有缘人少走弯路。



# 1. 任务

在服务器上使用lldb远程调试设备端Surfaceflinger。

# 2. 环境

1. 编译Android的Linux服务器；
2. 一台测试用的Android手机或者Android虚拟机；
3. Linux服务器与Android手机处于同一个网段；

# 3. 准备

1. Android 13 整套源码；
2. 编译通过SurfaceFlinger；
3. source build/<...setup>.sh
4. lunch <...>

# 4. 获取lldb配置命令

运行：lldbclient.py -n surfaceflinger

会提示没有adb设备，需要将Linux服务器上的adb识别到Android手机：  
1. 手机执行：adb root; adb tcpip 6666
2. 服务器执行：adb connect \<device-ip\>:6666

lldbclient.py执行完成后，执行一系列lldb配置，比如 source-map、target create等等，我们被这些 __lldb配置命令__ 记下来。  
集中，target create与 file 命令等同。

然后输入quit退出界面。

# 5. lldb.sh和lldb-server

在Android代码库中搜索: find . -name lldb.sh，选择一个与设备匹配的lldb.sh文件。  
在Android代码库中搜索: find . -name lldb-server，选择一个与设备匹配的lldb-server文件。

Linux服务器执行： adb push \<path to lldb-server\> /data/local/tmp/
手机执行：/data/local/tmp/lldb-server p --server --listen *:7777
Linux服务器执行：   
1. lldb.sh 进入 lldb命令行
2. platform select remote-android # 如果不对，可以通过platform list 来查看具体的平台名称
3. 把刚才记录下来的 __lldb配置命令__ 抄一遍
4. platform connect connect://\<device ip\>:7777
5. attach \<the pid of surfaceflinger\>

到此完毕，一般已经成功进入surfaceflinger调试状态。

# 6. 调试

在 lldb 调试命令行中

1. 先输入 c，保证surfaceflinger不会hung
2. 设备断点： b \<c++ 命令空间\>:\<function\>， 或者 b \<cpp file\>:\<行号\>
3. （操作手机，触发断点）
4. 获得调用栈：bt

其它调试命令参考lldb文档，与gdb类似。

