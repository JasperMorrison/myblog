---
layout: post
title: 利用docker编译Android源码
categories: Android
tags: docker android building
author: Jasper
---

* content
{:toc}

本文描述了如何在一个docker上搭建Android编译环境。



## Docker

Docker是一个计算机操作系统的容器，利用主机内核，搭建独立的文件系统，让用户程序运行在一个与宿主机文件系统无关的独立环境中。
Docker支持很多优雅的特性，方便项目的程序开发、调试和运行。在大数据云计算等领域具有不可比拟的优势，就连jvm就望而生畏。
Docker技术来源于Linux LXC技术，可以说是LXC技术的包装、升级和商品化。现在，也支持Windows Docker。

Docker有很多用途：

- 编译Android，你不用因为主机环境的变化或者系统的升级而烦恼。
- 学习分布式开发，一台计算机就能模拟分布式。
- 搭建代理服务器，每一个业务逻辑都是分开的，比如搭建一个内部小型网站。
- 模拟主机作业，先在docker上处理，防止破坏主机环境。

学习Docker时，有问题和需求，第一时间访问Docker官网，善于从英文文档中检索信息。  
初学者可能对images和container管理、Dockerfile的CMD和ENTRYPOINT、网络配置、跨系统版本搭建Docker等感到困惑。  
简单的提示一下：  
images：静态存在的镜像，可以理解是一个静态的文件系统镜像，运行它就能得到一个container。  
container：一个容器，可以理解是动态的文件系统镜像，我们可以运行它，在其上面作业，停止并删除它。  
CMD：`docker run最后一项`就是CMD，在Dockerfile中定义CMD会被命令行中的CMD覆盖。  
ENTRYPOINT：docker run后，docker容器的入口点，每次container运行时都会被执行，而且会覆盖命令行的CMD。  
网络配置：Docker默认建立一个bridge，给定一个桥地址，没开辟一个container，自动分配一个在桥ip段的ip。  
自定义网络配置：Docker的网络其实是linux的`ip`命令创建的虚拟网络，具体查找关键字`linux ip命令`，`maclan`，`vlan`，`veth`，`bridge`等。  
跨系统版本搭建Docker：比如在ubuntu16.04上搭建一个ubuntu14.04的dokcer，可能会产生内核不兼容的情况，比如，如果我们在docker执行service命令将失败，因为ubuntu16.04内核中使用systemd而不是service管理守护进程。

以上内容，几乎都能从Docker官网得到答案。

## Android　Building Docker

这里采用Dockerfile的方式建立docker镜像。

例子：在ubuntu16.04中搭建Android6.0的编译环境。

```
  1 FROM ubuntu:xenial
  2 
  3 MAINTAINER jaren jlin@archos.com
  4 
  5 ADD sources.list /etc/apt/sources.list #这里更新一个源，会快很多。
  6 RUN apt-get update
  7 # 在ubuntu中安装openjdk7需要单独添加仓库。
  8 RUN apt-get install -y software-properties-common
  9 RUN add-apt-repository ppa:openjdk-r/ppa
 10 RUN apt-get update
 11 RUN apt-get install -y openjdk-7-jdk
 12 # 安装Android编译的依赖包，查看Android官网可以得到。
 13 RUN apt-get install -y git-core gnupg flex bison gperf build-essential \
 14   zip curl zlib1g-dev gcc-multilib g++-multilib libc6-dev-i386 \
 15   lib32ncurses5-dev x11proto-core-dev libx11-dev lib32z-dev ccache \
 16   libgl1-mesa-dev libxml2-utils xsltproc unzip
 17 # ubuntu16.04中，默认不包含Python2.7
 18 RUN apt-get install -y python2.7
 19 
 20 RUN ln -sf /usr/bin/python2.7 /usr/bin/python
 21 # ubuntu16.04中默认不包含bc（一种编程语言）
 22 RUN apt-get install -y bc
 23 ENV USER=root
```

例子：在ubuntu16.04中创建ubuntu14.04的docker并编译Android6.0。  
这个跟上一个例子是类似的，只是我们可以简单安装openjdk7。并且库依赖也是完整的，省去了很多麻烦。

```
  1 FROM ubuntu:14.04
  2 MAINTAINER Jaren <jaren@archos.com>
  3 
  4 # Set to 32bit
  5 #RUN dpkg --add-architecture i386
  6 
  7 ADD sources.list /etc/apt/sources.list
  8 
  9 ADD setup.sh /setup/setup.sh
 10 RUN bash -x /setup/setup.sh
 11 
 12 ENV USER=root

```
setup.sh

```
  3 apt-get update || true
  4 
  5 apt-get install -y openjdk-7-jdk
  6 
  7 apt-get -y install git-core gnupg flex bison gperf build-essential \
  8   zip curl zlib1g-dev gcc-multilib g++-multilib libc6-dev-i386 \
  9   lib32ncurses5-dev x11proto-core-dev libx11-dev lib32z-dev ccache \
 10   libgl1-mesa-dev libxml2-utils xsltproc unzip python-networkx
```

例子：搭建ubuntu14.04的docker编译Android7.
此文创建之时，官网说明，建议采用ubuntu14.04编译，所以，参考官网能实现编译需求。

## 参考文献

[Docker](https://dockercon.smarteventscloud.com/portal/newreg.ww)  
[Android Building](https://source.android.com/source/requirements.html)

