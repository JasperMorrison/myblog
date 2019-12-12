---
layout: post
title: dex文件格式分析例子
categories: Android逆向工程
tags: Reverse dex-format
author: Jasper
---

* content
{:toc}

本文记录一个分析dex文件格式的例子，供参考。



## 源码

```java
  1 public class Demo
  2 {
  3     public static void myLog(String tag, String str)
  4     {
  5         System.out.printf(tag + ": " + str + "\n");
  6     }
  7 
  8     public static void main(String[] argc)
  9     {
 10         myLog("myLog","Hello World!");
 11     }
 12 }
```

## 生成dex文件

```
➜  apk-demo ls
Demo.java
➜  apk-demo javac Demo.java 
➜  apk-demo ls
Demo.class  Demo.java
➜  apk-demo dx --dex --output=classes.dex Demo.class
➜  apk-demo ls
classes.dex  Demo.class  Demo.java
```

## 完整的classes.dex

```
hexdump -C classes.dex
00000000  64 65 78 0a 30 33 35 00  a7 83 a6 ef 32 77 c2 ea  |dex.035.....2w..|
00000010  3a 2c 23 63 31 b4 16 b3  6e ba 6e 64 f7 4e dd 31  |:,#c1...n.nd.N.1|
00000020  30 04 00 00 70 00 00 00  78 56 34 12 00 00 00 00  |0...p...xV4.....|
00000030  00 00 00 00 90 03 00 00  19 00 00 00 70 00 00 00  |............p...|
00000040  09 00 00 00 d4 00 00 00  06 00 00 00 f8 00 00 00  |................|
00000050  01 00 00 00 40 01 00 00  08 00 00 00 48 01 00 00  |....@.......H...|
00000060  01 00 00 00 88 01 00 00  88 02 00 00 a8 01 00 00  |................|
00000070  5a 02 00 00 5d 02 00 00  61 02 00 00 69 02 00 00  |Z...]...a...i...|
00000080  74 02 00 00 82 02 00 00  85 02 00 00 8d 02 00 00  |t...............|
00000090  91 02 00 00 96 02 00 00  ad 02 00 00 c1 02 00 00  |................|
000000a0  d5 02 00 00 f0 02 00 00  04 03 00 00 07 03 00 00  |................|
000000b0  0b 03 00 00 10 03 00 00  25 03 00 00 3a 03 00 00  |........%...:...|
000000c0  42 03 00 00 48 03 00 00  4f 03 00 00 54 03 00 00  |B...H...O...T...|
000000d0  5c 03 00 00 06 00 00 00  09 00 00 00 0a 00 00 00  |\...............|
000000e0  0b 00 00 00 0c 00 00 00  0d 00 00 00 0e 00 00 00  |................|
000000f0  11 00 00 00 12 00 00 00  08 00 00 00 01 00 00 00  |................|
00000100  3c 02 00 00 05 00 00 00  03 00 00 00 00 00 00 00  |<...............|
00000110  07 00 00 00 04 00 00 00  44 02 00 00 0e 00 00 00  |........D.......|
00000120  06 00 00 00 00 00 00 00  10 00 00 00 06 00 00 00  |................|
00000130  4c 02 00 00 0f 00 00 00  06 00 00 00 54 02 00 00  |L...........T...|
00000140  05 00 01 00 16 00 00 00  00 00 03 00 02 00 00 00  |................|
00000150  00 00 05 00 14 00 00 00  00 00 04 00 15 00 00 00  |................|
00000160  01 00 00 00 17 00 00 00  02 00 03 00 02 00 00 00  |................|
00000170  04 00 03 00 02 00 00 00  04 00 02 00 13 00 00 00  |................|
00000180  04 00 01 00 18 00 00 00  00 00 00 00 01 00 00 00  |................|
00000190  02 00 00 00 00 00 00 00  03 00 00 00 00 00 00 00  |................|
000001a0  7c 03 00 00 00 00 00 00  01 00 01 00 01 00 00 00  ||...............|
000001b0  66 03 00 00 04 00 00 00  70 10 04 00 00 00 0e 00  |f.......p.......|
000001c0  03 00 01 00 02 00 00 00  6b 03 00 00 08 00 00 00  |........k.......|
000001d0  1a 00 15 00 1a 01 04 00  71 20 02 00 10 00 0e 00  |........q ......|
000001e0  05 00 02 00 03 00 00 00  72 03 00 00 26 00 00 00  |........r...&...|
000001f0  62 00 00 00 22 01 04 00  70 10 05 00 01 00 6e 20  |b..."...p.....n |
00000200  06 00 31 00 0c 01 1a 02  01 00 6e 20 06 00 21 00  |..1.......n ..!.|
00000210  0c 01 6e 20 06 00 41 00  0c 01 1a 02 00 00 6e 20  |..n ..A.......n |
00000220  06 00 21 00 0c 01 6e 10  07 00 01 00 0c 01 12 02  |..!...n.........|
00000230  23 22 07 00 6e 30 03 00  10 02 0e 00 02 00 00 00  |#"..n0..........|
00000240  03 00 07 00 01 00 00 00  03 00 00 00 02 00 00 00  |................|
00000250  03 00 03 00 01 00 00 00  08 00 01 0a 00 02 3a 20  |..............: |
00000260  00 06 3c 69 6e 69 74 3e  00 09 44 65 6d 6f 2e 6a  |..<init>..Demo.j|
00000270  61 76 61 00 0c 48 65 6c  6c 6f 20 57 6f 72 6c 64  |ava..Hello World|
00000280  21 00 01 4c 00 06 4c 44  65 6d 6f 3b 00 02 4c 4c  |!..L..LDemo;..LL|
00000290  00 03 4c 4c 4c 00 15 4c  6a 61 76 61 2f 69 6f 2f  |..LLL..Ljava/io/|
000002a0  50 72 69 6e 74 53 74 72  65 61 6d 3b 00 12 4c 6a  |PrintStream;..Lj|
000002b0  61 76 61 2f 6c 61 6e 67  2f 4f 62 6a 65 63 74 3b  |ava/lang/Object;|
000002c0  00 12 4c 6a 61 76 61 2f  6c 61 6e 67 2f 53 74 72  |..Ljava/lang/Str|
000002d0  69 6e 67 3b 00 19 4c 6a  61 76 61 2f 6c 61 6e 67  |ing;..Ljava/lang|
000002e0  2f 53 74 72 69 6e 67 42  75 69 6c 64 65 72 3b 00  |/StringBuilder;.|
000002f0  12 4c 6a 61 76 61 2f 6c  61 6e 67 2f 53 79 73 74  |.Ljava/lang/Syst|
00000300  65 6d 3b 00 01 56 00 02  56 4c 00 03 56 4c 4c 00  |em;..V..VL..VLL.|
00000310  13 5b 4c 6a 61 76 61 2f  6c 61 6e 67 2f 4f 62 6a  |.[Ljava/lang/Obj|
00000320  65 63 74 3b 00 13 5b 4c  6a 61 76 61 2f 6c 61 6e  |ect;..[Ljava/lan|
00000330  67 2f 53 74 72 69 6e 67  3b 00 06 61 70 70 65 6e  |g/String;..appen|
00000340  64 00 04 6d 61 69 6e 00  05 6d 79 4c 6f 67 00 03  |d..main..myLog..|
00000350  6f 75 74 00 06 70 72 69  6e 74 66 00 08 74 6f 53  |out..printf..toS|
00000360  74 72 69 6e 67 00 01 00  07 0e 00 0a 01 00 07 0e  |tring...........|
00000370  78 00 05 02 00 00 07 0e  01 25 0f 00 00 00 03 00  |x........%......|
00000380  00 81 80 04 a8 03 01 09  c0 03 01 09 e0 03 00 00  |................|
00000390  0d 00 00 00 00 00 00 00  01 00 00 00 00 00 00 00  |................|
000003a0  01 00 00 00 19 00 00 00  70 00 00 00 02 00 00 00  |........p.......|
000003b0  09 00 00 00 d4 00 00 00  03 00 00 00 06 00 00 00  |................|
000003c0  f8 00 00 00 04 00 00 00  01 00 00 00 40 01 00 00  |............@...|
000003d0  05 00 00 00 08 00 00 00  48 01 00 00 06 00 00 00  |........H.......|
000003e0  01 00 00 00 88 01 00 00  01 20 00 00 03 00 00 00  |......... ......|
000003f0  a8 01 00 00 01 10 00 00  04 00 00 00 3c 02 00 00  |............<...|
00000400  02 20 00 00 19 00 00 00  5a 02 00 00 03 20 00 00  |. ......Z.... ..|
00000410  03 00 00 00 66 03 00 00  00 20 00 00 01 00 00 00  |....f.... ......|
00000420  7c 03 00 00 00 10 00 00  01 00 00 00 90 03 00 00  ||...............|
00000430
```

## 文件内容大体划分

![dex-header](/images/Reverse/dex-header.png)
![dex-body1](/images/Reverse/dex-body1.png)
![dex-body2](/images/Reverse/dex-body2.png)

## 类

### 类的定义

```c++
 343 /*
 344  * Direct-mapped "class_def_item".
 345  */
 346 struct DexClassDef {
 347     u4  classIdx;           /* index into typeIds for this class */
 348     u4  accessFlags;
 349     u4  superclassIdx;      /* index into typeIds for superclass */
 350     u4  interfacesOff;      /* file offset to DexTypeList */
 351     u4  sourceFileIdx;      /* index into stringIds for source file name */
 352     u4  annotationsOff;     /* file offset to annotations_directory_item */
 353     u4  classDataOff;       /* file offset to class_data_item */
 354     u4  staticValuesOff;    /* file offset to DexEncodedArray */
 355 };
```

``` c++
 309 /*
 310  * Direct-mapped "type_id_item".
 311  */
 312 struct DexTypeId {
 313     u4  descriptorIdx;      /* index into stringIds list for type descriptor */
 314 };
```

表：类

| classIdx      | 0x00 | typeIds = 0x06  | stringIds = 0x285  |  string_data_item = 06 4c 44  65 6d 6f 3b 00 | LDemo; |
| accessFlags   | 0x01 | public  |   |   |
| superclassIdx | 0x02 | typeIds = 0x0a  | stringIds = 0x02ad  | string_data_item = 12 4c 6a 61 76 61 2f 6c 61 6e 67  2f 4f 62 6a 65 63 74 3b 00 | Ljava/lang/Object; |
| interfacesOff | 0x00 | 没有接口  |   |   |
| sourceFileIdx | 0x03 | stringIds = 0x269 | string_data_item = 09 44 65 6d 6f 2e 6a 61 76 61 00 | Demo.java |
| annotationsOff | 0x00 | 这个类没有注释  |   |   |
| classDataOff | 0x37c | class_data_item的偏移量  |   |   |
| staticValuesOff | 0x00 | 这个类没有静态段 | |

### class_data_item 解析

表：class_data_item定义


| Name | Format | Description |
| --- | --- | --- |
| static_fields_size | uleb128 | the number of static fields defined in this item |
| instance_fields_size | uleb128 | the number of instance fields defined in this item |
| direct_methods_size | uleb128 | the number of direct methods defined in this item |
| virtual_methods_size | uleb128 | the number of virtual methods defined in this item |
| static_fields | encoded_field[static_fields_size] | the defined static fields, represented as a sequence of    encoded elements. The fields must be sorted by    `field_idx` in increasing order.   |
| instance_fields | encoded_field[instance_fields_size] | the defined instance fields, represented as a sequence of    encoded elements. The fields must be sorted by    `field_idx` in increasing order.   |
| direct_methods | encoded_method[direct_methods_size] | the defined direct (any of `static`, `private`,    or constructor) methods, represented as a sequence of    encoded elements. The methods must be sorted by    `method_idx` in increasing order.   |
| virtual_methods | encoded_method[virtual_methods_size] | the defined virtual (none of `static`, `private`,    or constructor) methods, represented as a sequence of    encoded elements. This list should _not_ include inherited    methods unless overridden by the class that this item represents. The    methods must be sorted by `method_idx` in increasing order.    The `method_idx` of a virtual method must _not_ be the same    as any direct method.    |

表：class_data_item  
从0x37c开始。

```
0000037c  00 00 03 00  |x........%......|
00000380  00 81 80 04 a8 03 01 09  c0 03 01 09 e0 03 00 00  |................|
```

| Name | Format | value | description |
| --- | --- | --- | --- |
| static_fields_size | uleb128 | 00 |
| instance_fields_size | uleb128 | 00 |
| direct_methods_size | uleb128 | 03 | 
| virtual_methods_size | uleb128 | 00 |
| static_fields | encoded_field[static_fields_size] | 无 |
| instance_fields | encoded_field[instance_fields_size] | 无 |
| direct_methods | encoded_method[direct_methods_size] | 00 81 80 04 a8 03 01 09  c0 03 01 09 e0 03 |
| virtual_methods | encoded_method[virtual_methods_size] | 无 |

### encoded_method解析

表：encoded_method定义

| Name | Format | Description |
| --- | --- | --- |
| method_idx_diff | uleb128 | index into the `method_ids` list for the identity of this    method (includes the name and descriptor), represented as a difference    from the index of previous element in the list. The index of the    first element in a list is represented directly.   |
| access_flags | uleb128 | access flags for the method (`public`, `final`,    etc.). See "`access_flags` Definitions" for details.   |
| code_off | uleb128 | offset from the start of the file to the code structure for this    method, or `0` if this method is either `abstract`    or `native`. The offset should be to a location in the    `data` section. The format of the data is specified by    "`code_item`" below.    |

表：direct_methods

direct_methods | value 
--- | ---
direct_method[0]|00 81 80 04 a8 03
direct_method[1]|01 09 c0 03
direct_method[2]|01 09 e0 03

表：direct_method[0]

method_idx_diff | access_flags | code_off
---|---|---
00|81 80 04|a8 03
0|0x1001|0x1a8
\<init\>|ACC_CONSTRUCTOR\|ACC_PUBLIC|code_item的偏移地址

表：direct_method[1]

method_idx_diff | access_flags | code_off
---|---|---
01|09|c0 03
1|0x09|0x1c0
main|ACC_STATIC\|ACC_PUBLIC|code_item的偏移地址

表：direct_method[2]

method_idx_diff | access_flags | code_off
---|---|---
01|09|e0 03
1|0x09|0x1e0
main|ACC_STATIC\|ACC_PUBLIC|code_item的偏移地址

注意：这里的main为什么会显示有两个？所有的static方法，到dex中都会是main。`public static void main(String[] argc)`始终放在\<init\>函数后面，所以它会被当做入口函数。多少个static函数就会产生对应多的包含`01 09`的encoded_method。

下面解析code_item，具体的定义结构在[官网](http://source.android.com/devices/tech/dalvik/dex-format.html#file-layout)中有说明。  
以下是尼古拉斯.赵四的翻译：  
(1) registers_size：本段代码使用到的寄存器数目。  
(2) ins_size：method传入参数的数目 。  
(3) outs_size： 本段代码调用其它method 时需要的参数个数 。  
(4) tries_size： try_item 结构的个数 。  
(5) debug_off：偏移地址 ，指向本段代码的 debug 信息存放位置 ，是一个 debug_info_item 结构。  
(6) insns_size：指令列表的大小 ，以 16-bit 为单位 。 insns 是 instructions 的缩写 。  
(7) padding：值为 0 ，用于对齐字节 。  
(8) tries 和 handlers：用于处理 java 中的 exception , 常见的语法有 try catch 。  

### code_item解析

direct_method[1]的code_item。

```
000001c0  03 00 01 00 02 00 00 00  6b 03 00 00 08 00 00 00  |........k.......|
000001d0  1a 00 15 00 1a 01 04 00  71 20 02 00 10 00 0e 00  |........q ......|
```

| Name | Format | value |
| --- | --- | --- |
| registers_size | ushort | 0x03 |
| ins_size | ushort | 0x01 |
| outs_size | ushort | 0x02 |
| tries_size | ushort | 0x00 |
| debug_info_off | uint | 0x36b |
| insns_size | uint | 0x08 |
| insns | ushort[insns_size] | 1a 00 15 00 1a 01 04 00  71 20 02 00 10 00 0e 00   |
| padding | ushort _(optional)_ = 0 | tries_size == 0  或者 insns_size 不是奇数(odd)，所以这项为空 |
| tries | try_item[tries_size] _(optional)_ | 空  |
| handlers | encoded_catch_handler_list _(optional)_ | 空 |

direct_method[2]的code_item

```
000001e0  05 00 02 00 03 00 00 00  72 03 00 00 26 00 00 00  |........r...&...|
000001f0  62 00 00 00 22 01 04 00  70 10 05 00 01 00 6e 20  |b..."...p.....n |
00000200  06 00 31 00 0c 01 1a 02  01 00 6e 20 06 00 21 00  |..1.......n ..!.|
00000210  0c 01 6e 20 06 00 41 00  0c 01 1a 02 00 00 6e 20  |..n ..A.......n |
00000220  06 00 21 00 0c 01 6e 10  07 00 01 00 0c 01 12 02  |..!...n.........|
00000230  23 22 07 00 6e 30 03 00  10 02 0e 00 02 00 00 00  |#"..n0..........|
```

| Name | Format | value |
| --- | --- | --- |
| registers_size | ushort | 0x05 |
| ins_size | ushort | 0x02 |
| outs_size | ushort | 0x03 |
| tries_size | ushort | 0x00 |
| debug_info_off | uint | 0x372 |
| insns_size | uint | 0x26 |
| insns | ushort[insns_size] | 0x1f0开始的38个双字节 |
| padding | ushort _(optional)_ = 0 | tries_size == 0  或者 insns_size 不是奇数(odd)，所以这项为空 |
| tries | try_item[tries_size] _(optional)_ | 空  |
| handlers | encoded_catch_handler_list _(optional)_ | 空 |

为了简单起见，只解析direct_method[1]的code_item。  
指令内容：`1a 00 15 00 1a 01 04 00  71 20 02 00 10 00 0e 00`  

步骤

- 查看[Dalvik instructions中的 Summary of bytecode set](http://source.android.com/devices/tech/dalvik/dalvik-bytecode.html#instructions)，确定指令格式，占几位，使用的寄存器个数等等，分离出一个完整的指令；注意，每一个16bit编码单元都是小端序，所以op有第一个字节指定，数据由后续字节指定；
- 根据寄存器内容获得确定的值或者常量；
- 写出可供阅读的指令语法Syntax。  

分析过程

1. 查表  
由于第一个字节是1a，所以查到以下表项：  
| 1a 21c | const-string vAA, string@BBBB | `A:` destination register (8 bits) `B:` string index | Move a reference to the string specified by the given index into the specified register. |  
1a 21c：指令占两个16bit，一个寄存器和一个常量池索引。  
完整指令：`1a 00 15 00` 
2. 确定指令内容  
1a： const-string vAA, string@BBBB  
00： v0  
15 00: 常量池中的索引是0x0015，第21个字符串，stringId = `48 03 00 00` = `05 6d 79 4c 6f 67 00` = 'myLog'  
string@： 字符串常量池  
3. 确定语句  
const-string v0, 'myLog'  
所以：`1a 00 15 00` = `const-string v0, 'myLog'`

同理：  
`1a 01 04 00` = `const-string v1, 'Hello World!'`

__`71 20 02 00 10 00`这一条复杂些，记录一下。__

从71查表得71 35c，从id 35c查表得：

| A\|G\|_op_ BBBB F\|E\|D\|C | 35c | _[`A=5`] `op`_ {vC, vD, vE, vF, vG}, type@BBBB _[`A=4`] `op`_ {vC, vD, vE, vF},_`kind`_@BBBB _[`A=3`] `op`_ {vC, vD, vE}, _`kind`_@BBBB _[`A=2`] `op`_ {vC, vD}, _`kind`_@BBBB _[`A=1`] `op`_ {vC}, _`kind`_@BBBB _[`A=0`] `op`_ {}, _`kind`_@BBBB _The unusual choice in lettering here reflects a desire to make the count and the reference index have the same label as in format 3rc._ |

`[A=2] op {vC, vD}, kind@BBBB`

由0x7120，转换成小端序0x2071得：  
`A = 2`  
`G = 0`  
`op = 71`，查表得`invoke-static {vC, vD, vE, vF, vG}, meth@BBBB`  
由0x0200，转换成小端序0x0002得：  
`BBBB = 0002`  
由0x1000，转换成小端序0x0010得：  
`vC = 0`  
`vD = 1`

所以： `71 20 02 00 10 00` = `invoke-static {v0,v1}, meth@0002`   
又：`meth@0002 = 00 00 04 00 15 00 00 00`  
`00 00`:classid ==> 'LDemo';  
`04 00`:protoid ==> `10 00 00 00 06 00 00 00 4c 02 00 00` ==> `VLL V 02 00 00` ==> `VLL V 2 x 0x02c1` ==> `VLL V Ljava/lang/String; Ljava/lang/String;`  
`15 00 00 00`:stringid ==> 'myLog'

得到完整的函数：`LDemo;->myLog(Ljava/lang/String;Ljava/lang/String;)V`

所以： `71 20 02 00 10 00` = `invoke-static {v0,v1}, LDemo;->myLog(Ljava/lang/String;Ljava/lang/String;)V`

第三条指令`0e 00`：  
根据0e查表得到 `0e 10x	return-void	 	Return from a void method.`  
根据10x查表得到`ØØ|op	10x	op`，可知，`0e 00`的`00`表示`ØØ`，表示没有使用。  
所以`0e 00` = `return-void`

最后整理main函数：

```
.method public static main()V
	const-string v0, "myLog"
	const-string v1, "Hello World!"
	invoke-static {v0,v1}, LDemo;->myLog(Ljava/lang/String;Ljava/lang/String;)V
	return-void
.end method
```

## 附上baksmali.jar程序对classes.dex的分析

```c
                           |
                           |-----------------------------
                           |header_item section
                           |-----------------------------
                           |
                           |[0] header_item
000000: 6465 780a 3033 3500|  magic: dex\n035\u0000
000008: a783 a6ef          |  checksum
00000c: 3277 c2ea 3a2c 2363|  signature
000014: 31b4 16b3 6eba 6e64|
00001c: f74e dd31          |
000020: 3004 0000          |  file_size: 1072
000024: 7000 0000          |  header_size: 112
000028: 7856 3412          |  endian_tag: 0x12345678 (Little Endian)
00002c: 0000 0000          |  link_size: 0
000030: 0000 0000          |  link_offset: 0x0
000034: 9003 0000          |  map_off: 0x390
000038: 1900 0000          |  string_ids_size: 25
00003c: 7000 0000          |  string_ids_off: 0x70
000040: 0900 0000          |  type_ids_size: 9
000044: d400 0000          |  type_ids_off: 0xd4
000048: 0600 0000          |  proto_ids_size: 6
00004c: f800 0000          |  proto_ids_off: 0xf8
000050: 0100 0000          |  field_ids_size: 1
000054: 4001 0000          |  field_ids_off: 0x140
000058: 0800 0000          |  method_ids_size: 8
00005c: 4801 0000          |  method_ids_off: 0x148
000060: 0100 0000          |  class_defs_size: 1
000064: 8801 0000          |  class_defs_off: 0x188
000068: 8802 0000          |  data_size: 648
00006c: a801 0000          |  data_off: 0x1a8
                           |
                           |-----------------------------
                           |string_id_item section
                           |-----------------------------
                           |
                           |[0] string_id_item
000070: 5a02 0000          |  string_data_item[0x25a]: "\n"
                           |[1] string_id_item
000074: 5d02 0000          |  string_data_item[0x25d]: ": "
                           |[2] string_id_item
000078: 6102 0000          |  string_data_item[0x261]: "<init>"
                           |[3] string_id_item
00007c: 6902 0000          |  string_data_item[0x269]: "Demo.java"
                           |[4] string_id_item
000080: 7402 0000          |  string_data_item[0x274]: "Hello World!"
                           |[5] string_id_item
000084: 8202 0000          |  string_data_item[0x282]: "L"
                           |[6] string_id_item
000088: 8502 0000          |  string_data_item[0x285]: "LDemo;"
                           |[7] string_id_item
00008c: 8d02 0000          |  string_data_item[0x28d]: "LL"
                           |[8] string_id_item
000090: 9102 0000          |  string_data_item[0x291]: "LLL"
                           |[9] string_id_item
000094: 9602 0000          |  string_data_item[0x296]: "Ljava/io/PrintStream;"
                           |[10] string_id_item
000098: ad02 0000          |  string_data_item[0x2ad]: "Ljava/lang/Object;"
                           |[11] string_id_item
00009c: c102 0000          |  string_data_item[0x2c1]: "Ljava/lang/String;"
                           |[12] string_id_item
0000a0: d502 0000          |  string_data_item[0x2d5]: "Ljava/lang/StringBuilder;"
                           |[13] string_id_item
0000a4: f002 0000          |  string_data_item[0x2f0]: "Ljava/lang/System;"
                           |[14] string_id_item
0000a8: 0403 0000          |  string_data_item[0x304]: "V"
                           |[15] string_id_item
0000ac: 0703 0000          |  string_data_item[0x307]: "VL"
                           |[16] string_id_item
0000b0: 0b03 0000          |  string_data_item[0x30b]: "VLL"
                           |[17] string_id_item
0000b4: 1003 0000          |  string_data_item[0x310]: "[Ljava/lang/Object;"
                           |[18] string_id_item
0000b8: 2503 0000          |  string_data_item[0x325]: "[Ljava/lang/String;"
                           |[19] string_id_item
0000bc: 3a03 0000          |  string_data_item[0x33a]: "append"
                           |[20] string_id_item
0000c0: 4203 0000          |  string_data_item[0x342]: "main"
                           |[21] string_id_item
0000c4: 4803 0000          |  string_data_item[0x348]: "myLog"
                           |[22] string_id_item
0000c8: 4f03 0000          |  string_data_item[0x34f]: "out"
                           |[23] string_id_item
0000cc: 5403 0000          |  string_data_item[0x354]: "printf"
                           |[24] string_id_item
0000d0: 5c03 0000          |  string_data_item[0x35c]: "toString"
                           |
                           |-----------------------------
                           |type_id_item section
                           |-----------------------------
                           |
                           |[0] type_id_item
0000d4: 0600 0000          |  string_id_item[6]: LDemo;
                           |[1] type_id_item
0000d8: 0900 0000          |  string_id_item[9]: Ljava/io/PrintStream;
                           |[2] type_id_item
0000dc: 0a00 0000          |  string_id_item[10]: Ljava/lang/Object;
                           |[3] type_id_item
0000e0: 0b00 0000          |  string_id_item[11]: Ljava/lang/String;
                           |[4] type_id_item
0000e4: 0c00 0000          |  string_id_item[12]: Ljava/lang/StringBuilder;
                           |[5] type_id_item
0000e8: 0d00 0000          |  string_id_item[13]: Ljava/lang/System;
                           |[6] type_id_item
0000ec: 0e00 0000          |  string_id_item[14]: V
                           |[7] type_id_item
0000f0: 1100 0000          |  string_id_item[17]: [Ljava/lang/Object;
                           |[8] type_id_item
0000f4: 1200 0000          |  string_id_item[18]: [Ljava/lang/String;
                           |
                           |-----------------------------
                           |proto_id_item section
                           |-----------------------------
                           |
                           |[0] proto_id_item
0000f8: 0800 0000          |  shorty_idx = string_id_item[8]: LLL
0000fc: 0100 0000          |  return_type_idx = type_id_item[1]: Ljava/io/PrintStream;
000100: 3c02 0000          |  parameters_off = type_list_item[0x23c]: Ljava/lang/String;[Ljava/lang/Object;
                           |[1] proto_id_item
000104: 0500 0000          |  shorty_idx = string_id_item[5]: L
000108: 0300 0000          |  return_type_idx = type_id_item[3]: Ljava/lang/String;
00010c: 0000 0000          |  parameters_off = type_list_item[NO_OFFSET]
                           |[2] proto_id_item
000110: 0700 0000          |  shorty_idx = string_id_item[7]: LL
000114: 0400 0000          |  return_type_idx = type_id_item[4]: Ljava/lang/StringBuilder;
000118: 4402 0000          |  parameters_off = type_list_item[0x244]: Ljava/lang/String;
                           |[3] proto_id_item
00011c: 0e00 0000          |  shorty_idx = string_id_item[14]: V
000120: 0600 0000          |  return_type_idx = type_id_item[6]: V
000124: 0000 0000          |  parameters_off = type_list_item[NO_OFFSET]
                           |[4] proto_id_item
000128: 1000 0000          |  shorty_idx = string_id_item[16]: VLL
00012c: 0600 0000          |  return_type_idx = type_id_item[6]: V
000130: 4c02 0000          |  parameters_off = type_list_item[0x24c]: Ljava/lang/String;Ljava/lang/String;
                           |[5] proto_id_item
000134: 0f00 0000          |  shorty_idx = string_id_item[15]: VL
000138: 0600 0000          |  return_type_idx = type_id_item[6]: V
00013c: 5402 0000          |  parameters_off = type_list_item[0x254]: [Ljava/lang/String;
                           |
                           |-----------------------------
                           |field_id_item section
                           |-----------------------------
                           |
                           |[0] field_id_item
000140: 0500               |  class_idx = type_id_item[5]: Ljava/lang/System;
000142: 0100               |  return_type_idx = type_id_item[1]: Ljava/io/PrintStream;
000144: 1600 0000          |  name_idx = string_id_item[22]: out
                           |
                           |-----------------------------
                           |method_id_item section
                           |-----------------------------
                           |
                           |[0] method_id_item
000148: 0000               |  class_idx = type_id_item[0]: LDemo;
00014a: 0300               |  proto_idx = proto_id_item[3]: ()V
00014c: 0200 0000          |  name_idx = string_id_item[2]: <init>
                           |[1] method_id_item
000150: 0000               |  class_idx = type_id_item[0]: LDemo;
000152: 0500               |  proto_idx = proto_id_item[5]: ([Ljava/lang/String;)V
000154: 1400 0000          |  name_idx = string_id_item[20]: main
                           |[2] method_id_item
000158: 0000               |  class_idx = type_id_item[0]: LDemo;
00015a: 0400               |  proto_idx = proto_id_item[4]: (Ljava/lang/String;Ljava/lang/String;)V
00015c: 1500 0000          |  name_idx = string_id_item[21]: myLog
                           |[3] method_id_item
000160: 0100               |  class_idx = type_id_item[1]: Ljava/io/PrintStream;
000162: 0000               |  proto_idx = proto_id_item[0]: (Ljava/lang/String;[Ljava/lang/Object;)Ljava/io/PrintStream;
000164: 1700 0000          |  name_idx = string_id_item[23]: printf
                           |[4] method_id_item
000168: 0200               |  class_idx = type_id_item[2]: Ljava/lang/Object;
00016a: 0300               |  proto_idx = proto_id_item[3]: ()V
00016c: 0200 0000          |  name_idx = string_id_item[2]: <init>
                           |[5] method_id_item
000170: 0400               |  class_idx = type_id_item[4]: Ljava/lang/StringBuilder;
000172: 0300               |  proto_idx = proto_id_item[3]: ()V
000174: 0200 0000          |  name_idx = string_id_item[2]: <init>
                           |[6] method_id_item
000178: 0400               |  class_idx = type_id_item[4]: Ljava/lang/StringBuilder;
00017a: 0200               |  proto_idx = proto_id_item[2]: (Ljava/lang/String;)Ljava/lang/StringBuilder;
00017c: 1300 0000          |  name_idx = string_id_item[19]: append
                           |[7] method_id_item
000180: 0400               |  class_idx = type_id_item[4]: Ljava/lang/StringBuilder;
000182: 0100               |  proto_idx = proto_id_item[1]: ()Ljava/lang/String;
000184: 1800 0000          |  name_idx = string_id_item[24]: toString
                           |
                           |-----------------------------
                           |class_def_item section
                           |-----------------------------
                           |
                           |[0] class_def_item
000188: 0000 0000          |  class_idx = type_id_item[0]: LDemo;
00018c: 0100 0000          |  access_flags = 0x1: public
000190: 0200 0000          |  superclass_idx = type_id_item[2]: Ljava/lang/Object;
000194: 0000 0000          |  interfaces_off = type_list_item[NO_OFFSET]
000198: 0300 0000          |  source_file_idx = string_id_item[3]: Demo.java
00019c: 0000 0000          |  annotations_off = annotations_directory_item[NO_OFFSET]
0001a0: 7c03 0000          |  class_data_off = class_data_item[0x37c]
0001a4: 0000 0000          |  static_values_off = encoded_array_item[NO_OFFSET]
                           |
                           |-----------------------------
                           |code_item section
                           |-----------------------------
                           |
                           |[0] code_item: LDemo;-><init>()V
0001a8: 0100               |  registers_size = 1
0001aa: 0100               |  ins_size = 1
0001ac: 0100               |  outs_size = 1
0001ae: 0000               |  tries_size = 0
0001b0: 6603 0000          |  debug_info_off = 0x366
0001b4: 0400 0000          |  insns_size = 0x4
                           |  instructions:
0001b8: 7010 0400 0000     |    invoke-direct {v0}, Ljava/lang/Object;-><init>()V
0001be: 0e00               |    return-void
                           |[1] code_item: LDemo;->main([Ljava/lang/String;)V
0001c0: 0300               |  registers_size = 3
0001c2: 0100               |  ins_size = 1
0001c4: 0200               |  outs_size = 2
0001c6: 0000               |  tries_size = 0
0001c8: 6b03 0000          |  debug_info_off = 0x36b
0001cc: 0800 0000          |  insns_size = 0x8
                           |  instructions:
0001d0: 1a00 1500          |    const-string v0, "myLog"
0001d4: 1a01 0400          |    const-string v1, "Hello World!"
0001d8: 7120 0200 1000     |    invoke-static {v0, v1}, LDemo;->myLog(Ljava/lang/String;Ljava/lang/String;)V
0001de: 0e00               |    return-void
                           |[2] code_item: LDemo;->myLog(Ljava/lang/String;Ljava/lang/String;)V
0001e0: 0500               |  registers_size = 5
0001e2: 0200               |  ins_size = 2
0001e4: 0300               |  outs_size = 3
0001e6: 0000               |  tries_size = 0
0001e8: 7203 0000          |  debug_info_off = 0x372
0001ec: 2600 0000          |  insns_size = 0x26
                           |  instructions:
0001f0: 6200 0000          |    sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
0001f4: 2201 0400          |    new-instance v1, Ljava/lang/StringBuilder;
0001f8: 7010 0500 0100     |    invoke-direct {v1}, Ljava/lang/StringBuilder;-><init>()V
0001fe: 6e20 0600 3100     |    invoke-virtual {v1, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
000204: 0c01               |    move-result-object v1
000206: 1a02 0100          |    const-string v2, ": "
00020a: 6e20 0600 2100     |    invoke-virtual {v1, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
000210: 0c01               |    move-result-object v1
000212: 6e20 0600 4100     |    invoke-virtual {v1, v4}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
000218: 0c01               |    move-result-object v1
00021a: 1a02 0000          |    const-string v2, "\n"
00021e: 6e20 0600 2100     |    invoke-virtual {v1, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
000224: 0c01               |    move-result-object v1
000226: 6e10 0700 0100     |    invoke-virtual {v1}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
00022c: 0c01               |    move-result-object v1
00022e: 1202               |    const/4 v2, 0
000230: 2322 0700          |    new-array v2, v2, [Ljava/lang/Object;
000234: 6e30 0300 1002     |    invoke-virtual {v0, v1, v2}, Ljava/io/PrintStream;->printf(Ljava/lang/String;[Ljava/lang/Object;)Ljava/io/Print
                           |Stream;
00023a: 0e00               |    return-void
                           |
                           |-----------------------------
                           |type_list section
                           |-----------------------------
                           |
                           |[0] type_list
00023c: 0200 0000          |  size: 2
000240: 0300               |  type_id_item[3]: Ljava/lang/String;
000242: 0700               |  type_id_item[7]: [Ljava/lang/Object;
                           |[1] type_list
000244: 0100 0000          |  size: 1
000248: 0300               |  type_id_item[3]: Ljava/lang/String;
00024a: 0000               |
                           |[2] type_list
00024c: 0200 0000          |  size: 2
000250: 0300               |  type_id_item[3]: Ljava/lang/String;
000252: 0300               |  type_id_item[3]: Ljava/lang/String;
                           |[3] type_list
000254: 0100 0000          |  size: 1
000258: 0800               |  type_id_item[8]: [Ljava/lang/String;
                           |
                           |-----------------------------
                           |string_data_item section
                           |-----------------------------
                           |
                           |[0] string_data_item
00025a: 01                 |  utf16_size = 1
00025b: 0a00               |  data = "\n"
                           |[1] string_data_item
00025d: 02                 |  utf16_size = 2
00025e: 3a20 00            |  data = ": "
```

## 参考文献

[hex To str在线工具](http://tool.lu/hexstr/)  
[html To markdown](http://tool.lu/markdown/)  
[Android dex format official site](http://source.android.com/devices/tech/dalvik/dex-format.html)

