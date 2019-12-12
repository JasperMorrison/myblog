---
layout: post
title: Dalvik可执行指令格式
categories: Android逆向工程
tags: Reverse Android Dalvik instruction 翻译
author: Jasper
---

* content
{:toc}

本文记录了[Dalvik Executable instruction formats](http://source.android.com/devices/tech/dalvik/instruction-formats.html)详细阅读笔记，做大体翻译。



## Introduction

本文列出Dalvik指令格式，用于描述Dalvik可执行格式和Dalvik字节码。
应当结合[bytecode reference document](http://source.android.com/devices/tech/dalvik/dalvik-bytecode.html)一起使用。

## 按位描述（Bitwise descriptions）

Formats表中，第一列指明了格式的位布局。布局包含了__一个或者多个"words"__，"word"翻译为"字"，每一个"words"代表一个16-bit编码单元。
每一个word中的字符代表4个二进制位，从高位往低位读取，使用"|"分割以辅助阅读。从'A'开始的大写字母，用于表示格式中的段，
这个段由后面的语法列进行定义。"op"项用于表示格式中的eight-bit操作码。一个被削减过的0，
就是说0中间被砍了一刀的这样一个符号，用于表示指定位置中所有为0的位。

一般来说，一个编码单元使用有序的先低后高的字母序列表示。但是也有例外，主要是用于区别具有相同格式的编码指令。

例如，"B|A|op CCCC"： 
"B|A|op" 属于第一个"word"，"CCCC"属于第二个"word"，__每一个word是一个16-bit code units（16-bit编码单元）__。
第一个word包含低8位的操作码和一对高4位的value；第二个word代表了单个16位的值。也就是说，对于第一个word，低8位操作码是op，一对高4位的值分别是B和A，共16位。
这样，两个16位组合起来就是32位，所以，这条Dalvik指令等于32位二进制。

## Format IDs（格式的IDs）

Formats表中，第二列指明了某种格式的ID，ID可以用于其它文件的参考，也可以在编码中识别格式的类型，一个id对应一种编码格式的意思。

大多数的id包含三个字符，两个十进制数和一个字母。第一个十进制数表示16-bit code units在表格中的个数，第二个十进制数用于表示当前格式包含的最大寄存器个数（某些指令可以动态调整寄存器的个数）。
特别的，标识符"r"正代表编码寄存器的个数范围。最后那个字母半自动地（semi-mnemonically）表示了格式中任何其它附加的类型。
比如"21t"表示，指令是2个word（两个16-bit编码单元），使用一个寄存器，包含brach target（转移目标）。

| Mnemonic 助记符| Bit Sizes | Meaning |
| --- | --- | --- |
| b | 8 | immediate signed **b**yte 8位立即数 |
| c | 16, 32 | **c**onstant pool index 常量池索引|
| f | 16 | inter**f**ace constants (only used in statically linked formats) 接口常量（只使用于静态链接格式）|
| h | 16 | immediate signed **h**at (high-order bits of a 32- or 64-bit value; low-order bits are all `0`) 立即有符号数，高位有效|
| i | 32 | immediate signed **i**nt, or 32-bit float 立即有符号整数或者32位浮点数|
| l | 64 | immediate signed **l**ong, or 64-bit double 立即有符号长整数或者64位双精度浮点数|
| m | 16 | **m**ethod constants (only used in statically linked formats) 方法常量|
| n | 4 | immediate signed **n**ibble 立即有符号半字节数|
| s | 16 | immediate signed **s**hort 立即有符号短整型|
| t | 8, 16, 32 | branch **t**arget 转移目标（跳转）|
| x | 0 | no additional data 没有附加的信息|

## Syntax 语法

下表中第三列使用人类可识别的语法表示前面指定的格式，op在前面，然后跟随参数，所有内容以逗号分隔。

所有在第一列中指定的参数都将以原型出现，不加修改。比如：BB还是BB。

表示寄存器时使用"vX"，而不是"rX"，因为v表示虚拟寄存器的意思，从而不会与Dalvik实体寄存器的"r"冲突。由此，我们可以简洁地同时描述虚拟寄存器和实体寄存器。

"#+X"表示高位非零。

"+X"表示相对地址。

形如 "kind@X"表示常量池中内容X。kind可以是"string" (string pool index), "type" (type pool index), "field" (field pool index), and "meth" (method pool index)。

类似于常量池的表示方式，vtable offsets (indicated as "vtaboff") and field offsets (indicated as "fieldoff")表示两种预链接偏移量。

当格式中的某个符号无法明确表示一个值的时候，采用类似"[X=N]" 的变体形式，比如"[A=2]"，以表示A在等于2的情况下指令的语法。

## The formats表

请查阅[官网 The formats](http://source.android.com/devices/tech/dalvik/instruction-formats.html#formats).

例子

| AA\|_op_ BBBB | 20bc | _`op`_ AA, kind@BBBB | _suggested format for statically determined verification errors; A is the type of error and B is an index into a type-appropriate table (e.g. method references for a no-such-method error)_ |

- 格式：AA\|_op_ BBBB，AA是8bit的数，从ID可见它是一个8bit的立即数，op是操作码，BBBB是16bit的数，从ID可见它用于字符串常量池索引。  
- ID：20bc，2个word，0个寄存器，b表示8位立即数，c表示常量池索引。  
- 语法：_`op`_ AA, kind@BBBB，应当写成这样的供人类阅读的语法。  
- 描述：建议这样的格式用于错误处理，AA作为错误码，BBBB用于索引常量池中的错误类型信息（比如说，常量池中存放：没有这个函数，那么BBBB就是这个字符串的偏移量）。

问：BBBB是字符串对于文件的偏移地址还是对于常量池的偏移量？
答：是对于常量池的偏移量，否则kind就不需要分类了，实践证明的确是常量池的偏移量。


