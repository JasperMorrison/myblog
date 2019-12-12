---
layout: post
title: Dalvik-bytecode
categories: Android逆向工程
tags: Reverse Android Dalvik bytecode 翻译
author: Jasper
---

* content
{:toc}

本文记录对官网[Dalvik-bytecode](http://source.android.com/devices/tech/dalvik/dalvik-bytecode.html)的详细阅读，进行适当翻译和说明。



## 通用设计

- 机器模型和调用约定：
  - 机器模型是基于寄存器的，每一帧指令都在创建后拥有固定的size。每一个指令都包含一定的寄存器和参数。
  - 当需要表示值时，单个寄存器代表32bits值，相邻的两个寄存器代表64bits值，寄存器对没有字节对齐的要求。
  - 当需要表示引用时，寄存器被认为足够可以表示一个引用。
  - (Object) null == (int) 0。
  - 方法的N个参数被放在方法的调用帧（invocation frame）的最后N个寄存器中。
- 每条指令的都已16bit的位宽存储。在某些指令中，某些bit是被忽略的，被忽略的bit必须置0.
- 指令并不限定于特定的数据类型，比如，移动32bits寄存器的值并不需要知晓其是int还是float类型。
- 对于strings，types，fileds和methods的引用，分别采用不同的枚举和引用常量池。
- Bitwise literal data is represented in-line in the instruction stream.
不懂什么意思，可能是：按位表示的字面值直接表现出来。
- 实践表明，指令一般使用8-16个寄存器，所以，很多指令限制只寻址钱16个寄存器，如果有必要，可以增加到256个寄存器。另外，move系列指令可以拓展到可寻址v0 – v65535，即最大65536个寄存器。
- 有几个伪指令（pseudo-instructions）允许持有可变长度的参数，比如fill-array-data，在正常的指令流中，是不允许出现伪指令的。另外，指令采用4字节对齐形式存储，dex生成工具会对不对其的指令填充nop以使其适应4字节对齐。大多数工具会将伪指令放在方法的末尾，否则，将需要更多的指令协助于伪指令实现相同的功能。
- 当安装在一个运行中的系统时，指令的格式是运行被改变的，以获得更高的指令效率。
- 语法与助记符：
  - 参数的排列方式：目标 - 源，就是目标寄存器在源寄存器的前面。
  - 某些操作码带有二义性消除名称后缀（disambiguating name suffix），用来识别类型：
    - 32-bit操作码没有标志；
    - 64-bit操作码带有-wide后缀；
    - 特定类型的操作码，带有特定的后缀，比如，-boolean -byte -char -short -int -long -float -double -object -string -class -void.
  - 某些操作码带有二义性消除后缀（disambiguating suffix），用来区别完全相同但拥有不同的布局（layout）和选项的操作码。使用“/”分割多个后缀。
  - 特定说明：指令的长度就是指令所包含的字节的个数。
  - 比如，"move-wide/from16 vAA, vBBBB"：
    - "move" is the base opcode, indicating the base operation (move a register's value).
    - "wide" is the name suffix, indicating that it operates on wide (64 bit) data.
    - "from16" is the opcode suffix, indicating a variant that has a 16-bit register reference as a source. 16位寄存器作为源。
    - "vAA" is the destination register (implied by the operation; again, the rule is that destination arguments always come first), which must be in the range v0 – v255.
    - "vBBBB" is the source register, which must be in the range v0 – v65535. 注意这两个寄存器的范围
- 请参考[instruction formats document](http://source.android.com/devices/tech/dalvik/instruction-formats.html)，以获得Summary of bytecode set中对Op&Format的参考解释。
- 请参考[.dex file format document](http://source.android.com/devices/tech/dalvik/dex-format.html)，以获得对dex文件格式的解释。

## Summary of bytecode set

这个表是根据[instruction formats document](http://source.android.com/devices/tech/dalvik/instruction-formats.html)的定义的规范给出的。每一个Dalvik指令都能从这个[instruction formats document](http://source.android.com/devices/tech/dalvik/instruction-formats.html)中找到对应的ID。一个ID只是指明了一种格式，同一种格式可以定制多个指令。  
比如：ID = 12x，可以是指令`move vA, vB`，也可以是指令`move-wide vA, vB`。

## 参考文献

[dalvik-bytecode Android web site](http://source.android.com/devices/tech/dalvik/dalvik-bytecode.html)
