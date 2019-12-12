---
layout: post
title: Makefile-C工程实践
categories: Make
tags: Make Makefile C 工程实践
author: Jasper
---

* content
{:toc}

本文是关于Linux平台标配构建工具Make，其使用的默认配置文件Makefile。根据个人的项目经验，介绍Makefile在工程实践中的应用技巧。比如，如何在Makefile中执行shell命令、打包发布、动态库与静态库混编、模块化编程等。本文假设读者拥有一定的Makefile基础知识，至少懂Makefile基本规则。





## 工程样例

本工程样例保存在github，[Makefile-C Project Example](https://github.com/JasperMorrison/Makefile-C-Example).


```
$ tree
.
├── config.mk
├── dream_first
│   ├── include
│   │   └── api.h
│   ├── Makefile
│   └── src.c
├── include
├── libbuild
│   ├── include
│   │   └── api.h
│   ├── Makefile
│   └── src.c
├── librun
│   ├── include
│   │   └── api.h
│   ├── Makefile
│   └── src.c
├── libstatic
│   ├── include
│   │   └── api.h
│   ├── Makefile
│   └── src.c
├── main.c
└── Makefile

9 directories, 16 files
```

config.mk : 配置文件，比如配置gcc、宏控制等等  
dream\_first : 工程的源码文件  
include : 工程的依赖头文件  
libbuild : 编译时使用的库  
librun : 运行时使用的库，api与libbuild相同，但是函数实体不同  
libstatic : 静态库  
main.c : 工程main函数所在

### Make输出

```
$ make
make[1]: Entering directory '/mnt/ext/test/makefile/dream_first'
mkdir obj -p
x86_64-linux-gnu-gcc -I./include -c src.c  -o obj/src.o 
make[1]: Leaving directory '/mnt/ext/test/makefile/dream_first'
make[1]: Entering directory '/mnt/ext/test/makefile/libstatic'
mkdir obj -p
mkdir out -p
x86_64-linux-gnu-gcc -I./include -c src.c  -o obj/src.o 
x86_64-linux-gnu-ar -rcs -o out/libstatic.a obj/src.o
make[1]: Leaving directory '/mnt/ext/test/makefile/libstatic'
make[1]: Entering directory '/mnt/ext/test/makefile/libbuild'
mkdir obj -p
mkdir out -p
x86_64-linux-gnu-gcc -fPIC -I./include -c src.c  -o obj/src.o 
x86_64-linux-gnu-ld -shared obj/src.o  -o out/libdream.so 
make[1]: Leaving directory '/mnt/ext/test/makefile/libbuild'
make[1]: Entering directory '/mnt/ext/test/makefile/librun'
mkdir obj -p
mkdir out -p
x86_64-linux-gnu-gcc -fPIC -I./include -c src.c  -o obj/src.o 
x86_64-linux-gnu-ld -shared obj/src.o  -o out/libdream.so 
make[1]: Leaving directory '/mnt/ext/test/makefile/librun'
mkdir obj -p
mkdir out -p
x86_64-linux-gnu-gcc -I./include -DDEBUG -c main.c  -o obj/main.o 
x86_64-linux-gnu-gcc -o out/build_dream obj/main.o dream_first/obj/src.o -I./include -DDEBUG -L./libbuild/out -ldream -L./libstatic/out -lstatic -Wl,-rpath=./librun/out
```

### 运行输出

```
$ ./out/build_dream 
DEBUG:begin
I am the librun
I am libstatic.a
I have a dream,see: 
        I am dreaming......
DEBUG:end
```

## 模块化构建

C中，模块化构建思想是将模块相关的内容放到独立的文件夹中管理。在本工程中，创建了dream_first作为独立的模块。这个独立的模块既可以独立编译通过，产出主工程需要的.o文件，也可以在外部执行make编译。有的工程也习惯在工程根目录中使用make参数指定模块的方式独立编译模块。比如Android源码中，可以使用make services独立编译services.jar。又或者，make module=dream_first这样的方式。

```
$ cd dream\_first
$ make
mkdir obj -p
cc -I./include -c src.c  -o obj/src.o
```

在主Makefile中，将上面的.o添加进来一起编译。

```
$(BIN_DIR)/$(TARGET): $(OBJ_DIR)/$(OBJS)
    $(CC) -o $@ $(OBJ_DIR)/$(OBJS) $(shell for it in $(src_sub);do echo $$it/obj/*.o; done) $(CFLAGS) $(LDFLAGS)
```

关键是插入的一个shell语句：

`$(shell for it in $(src_sub);do echo $$it/obj/*.o; done)`

## 保持工程简洁

参阅《代码简洁之道》，对于保持工程的简洁就会抱有强烈的欲望，好像患上洁癖似的。工程简洁要求每一个参与工程开发的同学，都要尽可能熟读工程源码，特别一些公共的模块。不要在多个模块里面定义相同功能的函数体，或者程序块。主动将常用的代码放到公共模块中。保持每一个模块的函数命名的统一和独特性，比如都以`模块名+功能`中央的方式命名函数。保持工程的简洁，将对阅读、分析、调试、重构带来极大的好处。

同时，保持统一风格的代码注解，并保证所有关键代码、陌生代码、复杂代码都有相应的注解。

保持写测试用例的习惯，国内不知道有没有测试驱动开发的做法，只知道我身边寥寥无几。常常幻想，感觉那就是一个美梦。

## Makefile与源码变量传递

如果我们希望一些宏定义是动态配置的，并与make保持关联，可以在Makefile或者config.mk中给gcc添加debug参数。CFLAGS += -DDEBUG，表示定义了一个名为DEBUG的宏.通过这样的方式，可以编译DEBUG版本，控制工程功能，动态集成模块等等。

## 模块间传递变量

如果将主工程也当做一个模块看到的话，那么将主工程中的变量传递到子模块就是可以叫模块间传递变量。

假设在主Makefile中定义了一个变量CONFIG_FILE，同时，希望将这个变量传到到每一个子模块，怎么做？

可以通过向make添加变量的方式传递：

`make -C dream_first CONFIG_FILE=$(CONFIG_FILE)`

dream_first中的Makefile就能读到这个CONFIG_FILE变量的值。

## 模块依赖

对于C源码本身的依赖：  
其实C工程并没有模块的说法，所有自认为的模块在C工程中都被视为唯一一个模块的文件夹，内部源码没有模块之分。要实现模块间依赖，只需要模块包含另一个模块的头文件即可。但是为了避免头文件重复包含，所以，可以在.h文件通过宏的方式进行控制。这一块，并没有在本示例工程中实现。

但是，这并不是本节的重点，本文讲的是make。如果希望一次make就将所有模块都编译完成，并让主工程正确依赖模块编译通过。可以这么做：

将所有模块定义到一个变量中，`subs := dream_first libstatic libbuild librun`.

然后添加一个依赖规则：

```
all : subs
subs:
    @for sub in $(subs); do \
        make -C $$sub CONFIG_FILE=$(CONFIG_FILE); \
    done
```

当在工程根目录执行make时，会自动编译所有子模块。

注意，subs不能是一个文件或者文件夹，下面的文件依赖会提到这方面的内容。


## 文件依赖

文件依赖，就是在makefile规则中将一个文件/文件夹的名称当做依赖或者目标。

比如：

```
mydir
mydir:
    mkdir $@ -p
```

那么，如果mydir存在当前目录，则不会执行该语句，否则会执行该语句。

也可以同时依赖多个文件：


```
dirs := $(OBJ_DIR) $(BIN_DIR)
$(dirs):
    mkdir $@ -p
```

如果dirs这个变量中的文件夹任一一个没有创建，则会自动创建对应的文件夹。

不要将makefile中的变量与文件依赖的目标使用相同的名称，否则会给导致混淆，容易犯错。

比如上面的mydir已经被当做文件夹了。再这么写：

```
mydir := a b c 

.PHONY: all 
all: mydir $(dir)

$(mydir):
    mkdir $@ -p

mydir:
    mkdir $@ -p
```

结果，会创建这些文件夹: mydir a b c

## 动态库

见 libbuild ，它就是一个生成一个动态库的方法。

它的关键点在于，生成.o文件时，添加参数 -fPIC；生成.so文件时，添加参数 -shared。

引用动态库：`LDFLAGS += -L./libbuild/out -ldream`

## 静态库

见libstatic，它的关键点在于：将所有的.o使用 `$(AR) -rcs` 命令打包成一个.a文件，无需再经过ld。

引用静态库在引用动态库的基础上，多加 -static。  
`LDFLAGS += -L./libstatic/out -lstatic`

## 运行时依赖优先级

参考：https://www.cnblogs.com/homejim/p/8004883.html

第一优先级：-Wl,-rpath=《my_thirdparty_lib_path》  
第二优先级：export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:《your_lib_path》  
第三优先级：/etc/ld.so.cache中缓存了动态库路径，可以通过修改配置文件/etc/ld.so.conf中指定的动态库搜索路径，然后执行ldconfig命令来改变。  
第四优先级：系统库路径，比如/lib,/usr/lib

这个非常有用的，可以用一个动态库进行编译，而实际运行时使用另一个动态库。

比如项目要求一个加密后的.so用于运行时，但是这个加密后的.so无法通过编译，于是我们制造一个拥有相同API的非加密库，供第三方进行编译。

见libbuild和librun，它们的API完全相同，但是API内部的实现逻辑却可以完全不同。工程使用libbuild进行编译，但是运行的时候却输出了librun中的代码。

libbuild代码应当输出：I am the libbuild  
实际输出了librun中的log： I am the librun

## 发版本

版本发布的诀窍是在makefile中执行shell脚本，调用zip命令进行文件压缩。并使用shell脚本产生版本号等辅助信息。

## 倡导的做法

尽量保证子模块可以独立编译通过，产生库或者中间文件。  
为了方便子模块的编译，并保持工程简洁，不在子模块中使用.mk文件等其它文件替代Makefile。  

