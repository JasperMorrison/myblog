---
layout: post
title: 快速构建工具ninja
categories: tools
tags: ninja android
author: Jasper
---

* content
{:toc}

本文记录了快速构建工具ninja的认识和学习。



## 准备

从[Ninja - github](https://github.com/ninja-build/ninja)clone源码编译或者自行[下载二进制文件](https://github.com/ninja-build/ninja/releases)

## 使用说明

```
➜  ninja git:(release) ./ninja -h
usage: ninja [options] [targets...]

if targets are unspecified, builds the 'default' target (see manual).

options:
  --version  print ninja version ("1.7.2")

  -C DIR   change to DIR before doing anything else 相当于在DIR下执行ninja
  -f FILE  specify input build file [default=build.ninja]

  -j N     run N jobs in parallel [default=10, derived from CPUs available] 并行
  -k N     keep going until N jobs fail [default=1] 默认一旦有错就停止
  -l N     do not start new jobs if the load average is greater than N ？？？
  -n       dry run (don't run commands but act like they succeeded) 相关定make的 -n 只打印不执行
  -v       show all command lines while building 输出执行的命令

  -d MODE  enable debugging (use -d list to list modes) 测试模式
  -t TOOL  run a subtool (use -t list to list subtools) 有哪些subtools，用 -t list查看？ 后续的flags是传递到subtools的
    terminates toplevel options; further flags are passed to the tool 
  -w FLAG  adjust warnings (use -w list to list warnings) 对警告行为进行调整，类似gcc的 -Wall 相关的东西
```

subtools:

```
ninja subtools:
    browse  browse dependency graph in a web browser 在浏览器中显示依赖关系
     clean  clean built files 清空编译
  commands  list all commands required to rebuild given targets 列出重新构建给定target的所有命令
      deps  show dependencies stored in the deps log 显示存储在deps log中的依赖
     graph  output graphviz dot file for targets 输出graphviz dot file，对于每一个target
     query  show inputs/outputs for a path ？？？
   targets  list targets by their rule or depth in the DAG ？？？
    compdb  dump JSON compilation database to stdout 这个数据库有什么用？
 recompact  recompacts ninja-internal data structures 优化内部数据结构，有哪些数据结构，什么作用？
```

带着诸多疑问继续往下走。。。

## 测试

编译完成后，会在当前目录生成build.ninja文件，用于编译ninja_test，于是就这么做。  
`./ninja ninja_test`  
得到./ninja_test，它的作用是用于测试ninja的，如果执行输出passed表明测试通过。

## 阅读ninja手册

参考[Ninja - chromium核心构建工具](http://www.cnblogs.com/x_wukong/p/4846179.html)

### phony

它不是一个命令，更像是一个声明，可以让ninja通过命令行一次性执行多个目标的编译，类似makefile的.PHONY。

比如下面的例子：

```
cflags = -Wall

rule rule1 
     command = gcc $cflags -c $in -o $out
 
build mmm: phony foodir/foo fdd

build foodir/foo: rule1 foodir/foo.c
build fdd: rule1 fdd.c
build fgg: rule1 fgg.c
```

单单执行ninja，后处理foodir/foo fdd fgg，因为ninja会处理每一个build，但是all被指定为phony，所以它不会被处理。  
也可以执行ninja mmm，保证phony后面的目标都会被处理，而忽略了fgg。

### default

用于标注默认的build，如果没有default，那么ninja会处理所有的build，除了带有phony的。  
比如在上面的例子中加入default。

```
cflags = -Wall

rule rule1 
     command = gcc $cflags -c $in -o $out
 
build mmm: phony foodir/foo fdd

build foodir/foo: rule1 foodir/foo.c
build fdd: rule1 fdd.c
build fgg: rule1 fgg.c

default fdd
```

单单执行ninja，只会处理build fdd，如果没有default，就是完全原始的默认情况了。

## 参考文献

[Ninja - chromium核心构建工具](http://www.cnblogs.com/x_wukong/p/4846179.html)  
[Ninja - github](https://github.com/ninja-build/ninja)  
[Ninja - 手册](https://ninja-build.org/manual.html)  
[Ninja - Android7.0 编译原理](http://blog.csdn.net/chaoy1116/article/details/53063082)  
