---
layout: post
title:  "Android resources.arsc 分析例子"
categories: Android逆向工程
tags: android reverse resources.arsc
author: Jasper
---

* content
{:toc}

本文尝试分析一个简单的resources.arsc文件格式，共参考学习。



## 准备

使用Android Studio新建一个Android项目，不做任何修改，直接编译成apk，然后unzip这个apk，得到resources.arsc文件。  
取得参考头文件`frameworks/base/include/androidfw/ResourceTypes.h(Android 7.0)`

比如解压到apk目录下：

```
➜  apk unzip app-debug.apk
➜  apk ls
AndroidManifest.xml  classes.dex  res             res.txt
app-debug.apk        META-INF     resources.arsc
```

## 头部信息

```c++
 213 enum {
 214     RES_NULL_TYPE               = 0x0000,
 215     RES_STRING_POOL_TYPE        = 0x0001,
 216     RES_TABLE_TYPE              = 0x0002,
 217     RES_XML_TYPE                = 0x0003,
 218 
 219     // Chunk types in RES_XML_TYPE
 220     RES_XML_FIRST_CHUNK_TYPE    = 0x0100,
 221     RES_XML_START_NAMESPACE_TYPE= 0x0100,
 222     RES_XML_END_NAMESPACE_TYPE  = 0x0101,
 223     RES_XML_START_ELEMENT_TYPE  = 0x0102,
 224     RES_XML_END_ELEMENT_TYPE    = 0x0103,
 225     RES_XML_CDATA_TYPE          = 0x0104,
 226     RES_XML_LAST_CHUNK_TYPE     = 0x017f,
 227     // This contains a uint32_t array mapping strings in the string
 228     // pool back to resource identifiers.  It is optional.
 229     RES_XML_RESOURCE_MAP_TYPE   = 0x0180,
 230 
 231     // Chunk types in RES_TABLE_TYPE
 232     RES_TABLE_PACKAGE_TYPE      = 0x0200,
 233     RES_TABLE_TYPE_TYPE         = 0x0201,
 234     RES_TABLE_TYPE_SPEC_TYPE    = 0x0202,
 235     RES_TABLE_LIBRARY_TYPE      = 0x0203
 236 };
```

```c++
 191 /**
 192  * Header that appears at the front of every data chunk in a resource.
 193  */
 194 struct ResChunk_header //chunk头
 195 {
 196     // Type identifier for this chunk.  The meaning of this value depends
 197     // on the containing chunk.
 198     uint16_t type;
 199 
 200     // Size of the chunk header (in bytes).  Adding this value to
 201     // the address of the chunk allows you to find its associated data
 202     // (if any).
 203     uint16_t headerSize;
 204 
 205     // Total size of this chunk (in bytes).  This is the chunkSize plus
 206     // the size of any data associated with the chunk.  Adding this value
 207     // to the chunk allows you to completely skip its contents (including
 208     // any child chunks).  If this value is the same as chunkSize, there is
 209     // no data associated with the chunk.
 210     uint32_t size;
 211 };
```

```c++
 832 /**
 833  * Header for a resource table.  Its data contains a series of
 834  * additional chunks:
 835  *   * A ResStringPool_header containing all table values.  This string pool
 836  *     contains all of the string values in the entire resource table (not
 837  *     the names of entries or type identifiers however).
 838  *   * One or more ResTable_package chunks.
 839  *
 840  * Specific entries within a resource table can be uniquely identified
 841  * with a single integer as defined by the ResTable_ref structure.
 842  */
 843 struct ResTable_header  //文件头，64+32=96bits
 844 {
 845     struct ResChunk_header header; //一个chunk记录文件头的头部信息
 846 
 847     // The number of ResTable_package structures.
 848     uint32_t packageCount; //这个文件有几个package
 849 };
```

文件头：`02 00 0c 00 dc 22 03 00  01 00 00 00`

- 0x0002 -> RES_TABLE_TYPE - 表明这是一个table的头部
- 0x000c -> 这个头部占12个bit
- 0x0322dc -> 这个table的占 205532 Bytes，包含关联的chunk（不在这个resources.arsc文件中），如果 size = 这个文件的chunk的实际大小，则说明这个文件没有关联的chunk。
- 0x01 -> 只有一个package

```
➜  apk du -h -b resources.arsc
205532	resources.arsc
```
文件大小=所有chunk总大小，说明了这个resources.arsc就是单个chunk，没有关联的chunk。

## 常量池头部信息

``` c++
 419 /**
 420  * Definition for a pool of strings.  The data of this chunk is an
 421  * array of uint32_t providing indices into the pool, relative to
 422  * stringsStart.  At stringsStart are all of the UTF-16 strings
 423  * concatenated together; each starts with a uint16_t of the string's
 424  * length and each ends with a 0x0000 terminator.  If a string is >
 425  * 32767 characters, the high bit of the length is set meaning to take
 426  * those 15 bits as a high word and it will be followed by another
 427  * uint16_t containing the low word.
 428  *
 429  * If styleCount is not zero, then immediately following the array of
 430  * uint32_t indices into the string table is another array of indices
 431  * into a style table starting at stylesStart.  Each entry in the
 432  * style table is an array of ResStringPool_span structures.
 433  */
/*
字符串常量池的定义。这个chunk是一个指向一个pool的uint32_t的索引数组，这个pool从stringStart开始。从stringStart开始，
如果是UTF-16（到底是UTF-8还是UTF-16，是由这个结构体的flag指定的，但是不管是UTF-8还是UTF-16，都是用两个字节表示字符串长度，两个0x00表示字符串结束），字符串的开始一个uint16_t指定了字符串的长度，并以一个0x0000结束这个字符串。如果一个字符串的长度大于32767(0x7fff)，那么，最高位用于表示下一个字节依然用于表示字符串的长度。变成两个uint16_t表示这个字符串的长度，第一个uint16_t低15位表示高位，第二个uint16_t表示字符串长度的低16位。

如果styleCount不等于0，类似字符串常量池，上面说到的strings的后面紧接着一个索引数组，从stylesStart开始是对应个数的ResStringPool_span structures。
*/
 434 struct ResStringPool_header
 435 {
 436     struct ResChunk_header header;
 437 
 438     // Number of strings in this pool (number of uint32_t indices that follow
 439     // in the data).
 440     uint32_t stringCount;
 441 
 442     // Number of style span arrays in the pool (number of uint32_t indices
 443     // follow the string indices).
 444     uint32_t styleCount;
 445 
 446     // Flags.
 447     enum {
 448         // If set, the string index is sorted by the string values (based
 449         // on strcmp16()).
 450         SORTED_FLAG = 1<<0,
 451 
 452         // String pool is encoded in UTF-8
 453         UTF8_FLAG = 1<<8
 454     };
 455     uint32_t flags;
 456 
 457     // Index from header of the string data.
 458     uint32_t stringsStart;
 459 
 460     // Index from header of the style data.
 461     uint32_t stylesStart;
 462 };
```

常量池头部信息： 

```
01 00 1c 00  |....."..........| // 1c 个byte
00000010  64 d9 00 00 64 06 00 00  00 00 00 00 00 01 00 00  |d...d...........|
00000020  ac 19 00 00 00 00 00 00  00 00 00 00 24 00 00 00  |............$...|
00000030  54 00 00 00 83 00 00 00  b0 00 00 00 e2 00 00 00  |T...............|
```

- 64 d9 00 00 -> 整个常量池占 0xd964 个byte
- 64 06 00 00 -> string个数 - 0x0664
- 00 00 00 00 -> style个数 
- 00 01 00 00 -> flag -> 0x0100 -> 1<\<8 -\> UTF-8格式
- ac 19 00 00 -> string起始位置（相对于string data，而不是整个文件） -> 0x19ac + 文件头的大小0c = 0x19b8（这个才是相对于文件头的偏移量）
- 00 00 00 00 -> style起始位置

stringIds：
`00 00 00 00 24 00 00 00 等等`

string data：  
从上面计算的string起始位置对于文件头的偏移量得到0x19b8，截获部分数据分析。

```
21 21 72 65 73 2f 6c 61  |........!!res/la|
000019c0  79 6f 75 74 2f 61 62 63  5f 73 63 72 65 65 6e 5f  |yout/abc_screen_|
000019d0  74 6f 6f 6c 62 61 72 2e  78 6d 6c 00
```

'!!res/layout/abc_screen_toolbar.xml\0'共0x24个byte，这里的'\0'表示结束符。

所以stringIds是对string data区的index，每一个uint32_t代表了string的起始位置（相对于string data区）

计算最后一个string在resources.arsc的偏移地址：  
最后一个string的起始位置是`af bf 00 00`， 0xbfaf + 0x19b8 = 0xd967

```
0000d960  69 64 69 72 75 76 00 06  06 54 61 79 79 6f 72 00  |idiruv...Tayyor.|
0000d970  00 02 20 01 6c 49 02 00  7f 00 00 00 63 00 6f 00  |.. .lI......c.o.|
```

从第一个00 00到下一个00 00，`06  06 54 61 79 79 6f 72 00 00` = 'Tayyor'，前面两个字节都表示字符串的长度，最后两个00是结束符。  
如果字符串的长度大于0x7fff，则，前两个uint16_t表示字符串的长度，第一位为1，剩余31位表示长度，具体在前面的注释中已经说明。

## RES_TABLE_PACKAGE

```c++
 851 /**
 852  * A collection of resource data types within a package.  Followed by
 853  * one or more ResTable_type and ResTable_typeSpec structures containing the
 854  * entry values for each resource type.
 855  */
//这里的解释很重要，后续的ResTable_type and ResTable_typeSpec结构体包含的entry values指向了具体的resource type。
 856 struct ResTable_package
 857 {
 858     struct ResChunk_header header;
 859 
 860     // If this is a base package, its ID.  Package IDs start
 861     // at 1 (corresponding to the value of the package bits in a
 862     // resource identifier).  0 means this is not a base package.
 863     uint32_t id;
 864 
 865     // Actual name of this package, \0-terminated.
 866     uint16_t name[128];
 867 
 868     // Offset to a ResStringPool_header defining the resource
 869     // type symbol table.  If zero, this package is inheriting from
 870     // another base package (overriding specific values in it).
 871     uint32_t typeStrings;
 872 
 873     // Last index into typeStrings that is for public use by others.
 874     uint32_t lastPublicType;
 875 
 876     // Offset to a ResStringPool_header defining the resource
 877     // key symbol table.  If zero, this package is inheriting from
 878     // another base package (overriding specific values in it).
 879     uint32_t keyStrings;
 880 
 881     // Last index into keyStrings that is for public use by others.
 882     uint32_t lastPublicKey;
 883 
 884     uint32_t typeIdOffset;
 885 };
```

紧接着常量池的末尾，得到下面信息：

```
0000d970  00 02 20 01 6c 49 02 00  7f 00 00 00 63 00 6f 00  |.. .lI......c.o.|
0000d980  6d 00 2e 00 61 00 72 00  63 00 68 00 6f 00 73 00  |m...a.r.c.h.o.s.|
0000d990  2e 00 6d 00 79 00 61 00  70 00 70 00 6c 00 69 00  |..m.y.a.p.p.l.i.|
0000d9a0  63 00 61 00 74 00 69 00  6f 00 6e 00 00 00 00 00  |c.a.t.i.o.n.....|
0000d9b0  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
0000da70  00 00 00 00 00 00 00 00  00 00 00 00 20 01 00 00  |............ ...|
0000da80  0c 00 00 00 d0 01 00 00  dd 03 00 00 00 00 00 00  |................|
0000da90  01 00 1c 00 b0 00 00 00  0c 00 00 00 00 00 00 00  |................|
0000daa0  00 01 00 00 4c 00 00 00  00 00 00 00 00 00 00 00  |....L...........|
0000dab0  07 00 00 00 12 00 00 00  1b 00 00 00 24 00 00 00  |............$...|
```

- 00 02 -> RES_TABLE_PACKAGE_TYPE = 0x0200
- 20 01 -> package header的大小 - 0x120
- 6c 49 02 00 -> package chunk 的大小 - 0x2496c
- 7f 00 00 00 -> 开始bit是0，所以不是base package，而是用户package
- 63 00 ～ 00 00 -> uint16_t name[128] -> 这个package的名称 'com.archos.myapplication'
- 0xd970 + 128 x 2 = 0xd970 + 0x100 = 0xda70 -> 在此取得 20 01 00 00 -> 0x120（相对于package header的） -> typeStrings -> 0xd970 + 0x120 = 0xda90(相对于整个文件的偏移量)
- 0c 00 00 00 -> lastPublicType （指向typeStrings的最后一个，第0x0c个typeString就是lastPublieType）
- d0 01 00 00 -> keyStrings （计算方式同typeStrings，得到偏移地址 0xdb40）
- dd 03 00 00 -> lastPublicKey （指向最后一个typeString，第0x3dd个keyString就是lastPublicKey）
- 00 00 00 00 -> typeIdOffset （同上）

说明：  
typeString 就是attr，drawable，layout等，keyString就是 app_name，hello_world，action_settings等，要想知道对应的内容代表什么，根据偏移地址分析。

### typeString

前面已经计算过typeStrings对文件的偏移地址是0xda90  
typeStrings信息：  

```
0000da90  01 00 1c 00 b0 00 00 00  0c 00 00 00 00 00 00 00  |................|
0000daa0  00 01 00 00 4c 00 00 00  00 00 00 00 00 00 00 00  |....L...........|
0000dab0  07 00 00 00 12 00 00 00  1b 00 00 00 24 00 00 00  |............$...|
0000dac0  2b 00 00 00 34 00 00 00  3c 00 00 00 44 00 00 00  |+...4...<...D...|
0000dad0  4b 00 00 00 53 00 00 00  58 00 00 00 04 04 61 74  |K...S...X.....at|
0000dae0  74 72 00 08 08 64 72 61  77 61 62 6c 65 00 06 06  |tr...drawable...|
0000daf0  6d 69 70 6d 61 70 00 06  06 6c 61 79 6f 75 74 00  |mipmap...layout.|
0000db00  04 04 61 6e 69 6d 00 06  06 73 74 72 69 6e 67 00  |..anim...string.|
0000db10  05 05 64 69 6d 65 6e 00  05 05 73 74 79 6c 65 00  |..dimen...style.|
0000db20  04 04 62 6f 6f 6c 00 05  05 63 6f 6c 6f 72 00 02  |..bool...color..|
0000db30  02 69 64 00 07 07 69 6e  74 65 67 65 72 00 00 00  |.id...integer...|
0000db40  01 00 1c 00 a0 86 00 00  dd 03 00 00 00 00 00 00  |................|
```

- 01 00 -> STRING_POOL -> 常量池 -> 参考ResStringPool_header结构体
- 1c 00 -> typeString header 的大小 1c 个 bytes
- b0 -> 整个chunk的大小 b0 个 bytes，包括头部
- 0c 00 00 00 -> stringCount
- 00 00 00 00 -> styleCount
- 00 01 00 00 -> 1<\<8 -\> -> UTF-8
- 4c 00 00 00 -> 相对于这个chunk开头的起始位置是 string，得到stringId后从这里开始找string
- 00 00 00 00 -> styleStart

计算typeString的stringIds的偏移地址，跟前面计算string的偏移地址是一样的：  
0xda90 + 0x1c = 0xdaac

计算typeString的偏移地址：  
0xdaac + 0x0c x 4 = 0xdadc

计算typeString的末尾地址，也就是下一段信息keyString的起始地址：  
0xda90 + 0xb0 = 0xdb40

表：typeString例子

strinId | typeString | explain
--|-- |--
00 00 00 00 | 04 04 61 74 74 72 00 | attr
00 00 00 07 | 08 08 64 72 61  77 61 62 6c 65 00 | drawable

上表中给出了两个资源类型字符串attr和drawable。

### keyString

前面分析到keyString的偏移地址是0xdb40。获得keyString的信息：  

```
0000db40  01 00 1c 00 a0 86 00 00  dd 03 00 00 00 00 00 00  |................|
0000db50  00 01 00 00 90 0f 00 00  00 00 00 00 00 00 00 00  |................|
0000db60  13 00 00 00 1c 00 00 00  2b 00 00 00 33 00 00 00  |........+...3...|
```

- 01 00 -> 0x0001 -> STRING_POOL
- 1c 00 -> headerSize 0x1c
- a0 86 00 00 -> 这个chunk的总大小
- dd 03 00 00 -> stringCount
- 00 00 00 00 -> styleCount
- 00 01 00 00 -> UTF-8
- 90 0f 00 00 -> stringStart 0x0f90 -> stringStart相对于文件头的偏移量 = 0xdb40 + 0xf90 = 0xead0

0xead0处的信息：  

```
0000ead0  10 10 64 72 61 77 65 72  41 72 72 6f 77 53 74 79  |..drawerArrowSty|
0000eae0  6c 65 00 06 06 68 65 69  67 68 74 00 0c 0c 69 73  |le...height...is|
0000eaf0  4c 69 67 68 74 54 68 65  6d 65 00 05 05 74 69 74  |LightTheme...tit|
```

表： keyString例子

stringId | keyString | explain
--|-- |
00 00 00 00|10 10 64 72 61 77 65 72  41 72 72 6f 77 53 74 79 00 |drawerArrowStyle
00 00 00 13|06 06 68 65 69  67 68 74 00 |height

上表中给出了两个资源名称的字符串信息，比如第二个height，是用于定义UI的高度。类似这些就是keyString。

计算下一个chunk的偏移地址：  
0xdb40 + 0x86a0 = 0x161e0

## RES_TABLE_TYPE_SPEC

```c++
1286 /**
1287  * A specification of the resources defined by a particular type.
1288  *
1289  * There should be one of these chunks for each resource type.
1290  *
1291  * This structure is followed by an array of integers providing the set of
1292  * configuration change flags (ResTable_config::CONFIG_*) that have multiple
1293  * resources for that configuration.  In addition, the high bit is set if that
1294  * resource has been made public.
1295  */
1296 struct ResTable_typeSpec
1297 {
1298     struct ResChunk_header header;
1299 
1300     // The type identifier this chunk is holding.  Type IDs start
1301     // at 1 (corresponding to the value of the type bits in a
1302     // resource identifier).  0 is invalid.
1303     uint8_t id;
1304     
1305     // Must be 0.
1306     uint8_t res0;
1307     // Must be 0.
1308     uint16_t res1;
1309     
1310     // Number of uint32_t entry configuration masks that follow.
1311     uint32_t entryCount;
1312 
1313     enum {
1314         // Additional flag indicating an entry is public.
1315         SPEC_PUBLIC = 0x40000000
1316     };
1317 };
```

前面得到了这段信息的地址，取出来，发现 flag = 0x0202，正好是TABLE_TYPE_SPEC。

```
000161e0  02 02 10 00 94 03 00 00  01 00 00 00 e1 00 00 00  |................|
000161f0  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
00016570  00 00 00 00 01 02 4c 00  c4 1e 00 00 01 00 00 00  |......L.........|
```

- 02 02 -> spec 类型
- 10 00 -> header size
- 94 03 00 00 -> chunkSize
- 01 -> id 
- e1 00 00 00 -> entryCount ，表示此chunk包含有多少个entry

这里的id是type id，从1开始，不同的id代表不同的类型。每一种类型都有一个spec块指定了这种类型的规范信息。
每一个entry都是一个uint32_t，代表这这类资源的规范。  
由此可知，整个chunkSize占0x394个byte，尝试验证一下上一句话的意思：  
header size + entryCount x entrySize = 0x10 + 0xe1 x 4 = 0x394， 正好是这个chunk的大小，证毕。

但是这些entry都是uint32_t的0x00，我还不知道这个规范具体起到了什么作用，参考文献指出，当系统信息发生变化时（如屏幕密度），规范中指定了屏幕密度的资源将会被重新加载。

另外，上面得到的typeString的个数是0x0c个，按理说也应当有0x0c个spec块，然而，这里只发现了一个spec块。  
__这让我对spec更疑惑。。。__，后面将解答这个疑问，因为发现了0x0c个spec块。

计算后续内容的偏移地址：0x161e0 + 0x0394 = 0x16574

## ResTable_type

每一个具体的type都有一个或者多个ResTable_type，包含了type的具体配置信息，比如对语言、屏幕等等18维空间的配置要求。
type对应了前面中的typeString块，ResTable_type中的id就是typeString的索引，从1开始。  

```
1319 /**
1320  * A collection of resource entries for a particular resource data
1321  * type. Followed by an array of uint32_t defining the resource
1322  * values, corresponding to the array of type strings in the
1323  * ResTable_package::typeStrings string block. Each of these hold an
1324  * index from entriesStart; a value of NO_ENTRY means that entry is
1325  * not defined.
1326  *
1327  * There may be multiple of these chunks for a particular resource type,
1328  * supply different configuration variations for the resource values of
1329  * that type.
1330  *
1331  * It would be nice to have an additional ordered index of entries, so
1332  * we can do a binary search if trying to find a resource by string name.
1333  */
/*
这是一个对于特定的resource data type的resourece entries的集合，紧接着一个uint32_tresource values数组，数组的内容就是从entriesStart开始，entry的索引。这个特定的resource data type属于ResTable_package::typeStrings string block中指定的某个typeString。也就是说，这个定义了一个属于单个type的所有资源值的所有entries，一个资源值对应一个entry，所以，一个type会携带与资源个数相同的enties。

Enties应当进行字符串排序，这样，我们可以通过对String name的二进制查找快速获得一个resource entry。
*/
1334 struct ResTable_type
1335 {
1336     struct ResChunk_header header;
1337 
1338     enum {
1339         NO_ENTRY = 0xFFFFFFFF
1340     };
1341     
1342     // The type identifier this chunk is holding.  Type IDs start
1343     // at 1 (corresponding to the value of the type bits in a
1344     // resource identifier).  0 is invalid.
1345     uint8_t id;
1346     
1347     // Must be 0.
1348     uint8_t res0;
1349     // Must be 0.
1350     uint16_t res1;
1351     
1352     // Number of uint32_t entry indices that follow.
1353     uint32_t entryCount;
1354 
1355     // Offset from header where ResTable_entry data starts.
1356     uint32_t entriesStart;
1357     
1358     // Configuration this collection of entries is designed for.
1359     ResTable_config config;
1360 };
```

根据0x16574获得信息：

```
00016570  00 00 00 00 01 02 4c 00  c4 1e 00 00 01 00 00 00  |......L.........|
00016580  e1 00 00 00 d0 03 00 00  38 00 00 00 00 00 00 00  |........8.......|
00016590  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
000165c0  00 00 00 00 1c 00 00 00  38 00 00 00 54 00 00 00  |........8...T...|
000165d0  70 00 00 00 b0 00 00 00  20 01 00 00 3c 01 00 00  |p....... ...<...|
000165e0  58 01 00 00 74 01 00 00  90 01 00 00 ac 01 00 00  |X...t...........|
000165f0  c8 01 00 00 e4 01 00 00  00 02 00 00 1c 02 00 00  |................|
00016600  38 02 00 00 54 02 00 00  70 02 00 00 8c 02 00 00  |8...T...p.......|
```

- RES_TABLE_TYPE_TYPE = 0x0201,
- 0x4c header size
- 0x1ec4 chunkSize
- 0x01 id -> 到typeString找到第一个type得'attr'.
- 0xe1 entriesCount
- 0x3d0 entriesStart 
- 0x38 接下来的0x38空间属于ResTable_config，后面会分析，这里不分析，知道它占了这么多空间就好了。

先计算下一块内容的地址：  
0x16574 + 0x1ec4 = 0x18438

粗略看一下0x18438的内容：  

```
00018430  08 00 00 10 03 00 00 00  02 02 10 00 60 01 00 00  |............`...|
00018440  02 00 00 00 54 00 00 00  00 01 00 00 00 00 00 00  |....T...........|
00018450  00 00 00 00 00 00 00 00  00 01 00 00 00 01 00 00  |................|
00018460  00 00 00 00 00 00 00 00  00 00 00 00 00 01 00 00  |................|
00018470  00 01 00 00 00 01 00 00  00 01 00 00 00 00 00 00  |................|
00018480  00 00 00 00 00 01 00 00  00 00 00 00 00 00 00 00  |................|
00018490  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
```

可见，其就是一个0x0202，就是一个RES_TABLE_TYPE_SPEC。这一块chunk，大小等于0x1ec4的空间里包含了0xe1个entries。我们尝试分析这些entries的具体信息。

entriesStart开始，entry的索引：  
0x16574 + 0x4c = 0x165c0，取内容：

```
000165c0  00 00 00 00 1c 00 00 00  38 00 00 00 54 00 00 00  |........8...T...|
000165d0  70 00 00 00 b0 00 00 00  20 01 00 00 3c 01 00 00  |p....... ...<...|
000165e0  58 01 00 00 74 01 00 00  90 01 00 00 ac 01 00 00  |X...t...........|
000165f0  c8 01 00 00 e4 01 00 00  00 02 00 00 1c 02 00 00  |................|
00016600  38 02 00 00 54 02 00 00  70 02 00 00 8c 02 00 00  |8...T...p.......|
00016610  a8 02 00 00 c4 02 00 00  e0 02 00 00 fc 02 00 00  |................|
00016620  18 03 00 00 34 03 00 00  50 03 00 00 6c 03 00 00  |....4...P...l...|
```

计算spec entry的起始地址(entriesStart)：

0x16574 + 0x3d0 = 0x16944，取内容：

```
00016940  9c 1a 00 00 10 00 01 00  00 00 00 00 00 00 00 00  |................|
00016950  01 00 00 00 00 00 00 01  08 00 00 10 01 00 00 00  |................|
00016960  10 00 01 00 01 00 00 00  00 00 00 00 01 00 00 00  |................|
00016970  00 00 00 01 08 00 00 10  40 00 00 00 10 00 01 00  |........@.......|
00016980  02 00 00 00 00 00 00 00  01 00 00 00 00 00 00 01  |................|
00016990  08 00 00 10 08 00 00 00  10 00 01 00 03 00 00 00  |................|
000169a0  00 00 00 00 01 00 00 00  00 00 00 01 08 00 00 10  |................|
000169b0  02 00 00 00 10 00 01 00  04 00 00 00 00 00 00 00  |................|
000169c0  04 00 00 00 00 00 00 01  08 00 00 10 00 00 01 00  |................|
000169d0  09 00 0b 7f 08 00 00 10  01 00 00 00 0a 00 0b 7f  |................|
000169e0  08 00 00 10 00 00 00 00  0b 00 0b 7f 08 00 00 10  |................|
```

### type entry


```
 387 /**
 388  *  This is a reference to a unique entry (a ResTable_entry structure)
 389  *  in a resource table.  The value is structured as: 0xpptteeee,
 390  *  where pp is the package index, tt is the type index in that
 391  *  package, and eeee is the entry index in that type.  The package
 392  *  and type values start at 1 for the first item, to help catch cases
 393  *  where they have not been supplied.
 394  */
/*
这是一个entry的引用，形如0xpptteeee，pp - package index(from 0x01)，tt - type index in that package(from 0x01)， eeee entry index in that type。
*/
 395 struct ResTable_ref
 396 {
 397     uint32_t ident;
 398 };
 399 
 400 /**
 401  * Reference to a string in a string pool.
 402  */
 403 struct ResStringPool_ref
 404 {
 405     // Index into the string pool table (uint32_t-offset from the indices
 406     // immediately after ResStringPool_header) at which to find the location
 407     // of the string data in the pool.
 408     uint32_t index;
 409 };

1362 /**
1363  * This is the beginning of information about an entry in the resource
1364  * table.  It holds the reference to the name of this entry, and is
1365  * immediately followed by one of:
1366  *   * A Res_value structure, if FLAG_COMPLEX is -not- set.
1367  *   * An array of ResTable_map structures, if FLAG_COMPLEX is set.
1368  *     These supply a set of name/value mappings of data.
1369  */
/*
entry包含了这个entry name的索引，还有一个Res_value 或者 ResTable_map structure.
*/
1370 struct ResTable_entry
1371 {
1372     // Number of bytes in this structure.
1373     uint16_t size;
1374 
1375     enum {
1376         // If set, this is a complex entry, holding a set of name/value
1377         // mappings.  It is followed by an array of ResTable_map structures.
1378         FLAG_COMPLEX = 0x0001,
1379         // If set, this resource has been declared public, so libraries
1380         // are allowed to reference it.
1381         FLAG_PUBLIC = 0x0002,
1382         // If set, this is a weak resource and may be overriden by strong
1383         // resources of the same name/type. This is only useful during
1384         // linking with other resource tables.
1385         FLAG_WEAK = 0x0004
1386     };
1387     uint16_t flags;
1388     
1389     // Reference into ResTable_package::keyStrings identifying this entry.
1390     struct ResStringPool_ref key;
1391 };

1393 /**
1394  * Extended form of a ResTable_entry for map entries, defining a parent map
1395  * resource from which to inherit values.
1396  */
1397 struct ResTable_map_entry : public ResTable_entry
1398 {
1399     // Resource identifier of the parent mapping, or 0 if there is none.
1400     // This is always treated as a TYPE_DYNAMIC_REFERENCE.
1401     ResTable_ref parent;
1402     // Number of name/value pairs that follow for FLAG_COMPLEX.
1403     uint32_t count;
1404 };

1406 /**
1407  * A single name/value mapping that is part of a complex resource
1408  * entry.
1409  */
1410 struct ResTable_map
1411 {
1412     // The resource identifier defining this mapping's name.  For attribute
1413     // resources, 'name' can be one of the following special resource types
1414     // to supply meta-data about the attribute; for all other resource types
1415     // it must be an attribute resource.
1416     ResTable_ref name;
1417 
1418     // Special values for 'name' when defining attribute resources.
1419     enum {
1420         // This entry holds the attribute's type code.
1421         ATTR_TYPE = Res_MAKEINTERNAL(0),
1422 
1423         // For integral attributes, this is the minimum value it can hold.
1424         ATTR_MIN = Res_MAKEINTERNAL(1),
1425 
1426         // For integral attributes, this is the maximum value it can hold.
1427         ATTR_MAX = Res_MAKEINTERNAL(2),
1428 
1429         // Localization of this resource is can be encouraged or required with
1430         // an aapt flag if this is set
1431         ATTR_L10N = Res_MAKEINTERNAL(3),
1432 
1433         // for plural support, see android.content.res.PluralRules#attrForQuantity(int)
1434         ATTR_OTHER = Res_MAKEINTERNAL(4),
1435         ATTR_ZERO = Res_MAKEINTERNAL(5),
1436         ATTR_ONE = Res_MAKEINTERNAL(6),
1437         ATTR_TWO = Res_MAKEINTERNAL(7),
1438         ATTR_FEW = Res_MAKEINTERNAL(8),
1439         ATTR_MANY = Res_MAKEINTERNAL(9)
1440         
1441     };
1442 
1443     // Bit mask of allowed types, for use with ATTR_TYPE.
1444     enum {
1445         // No type has been defined for this attribute, use generic
1446         // type handling.  The low 16 bits are for types that can be
1447         // handled generically; the upper 16 require additional information
1448         // in the bag so can not be handled generically for TYPE_ANY.
1449         TYPE_ANY = 0x0000FFFF,
1450 
1451         // Attribute holds a references to another resource.
1452         TYPE_REFERENCE = 1<<0,
1453 
1454         // Attribute holds a generic string.
1455         TYPE_STRING = 1<<1,
1456 
1457         // Attribute holds an integer value.  ATTR_MIN and ATTR_MIN can
1458         // optionally specify a constrained range of possible integer values.
1459         TYPE_INTEGER = 1<<2,
1460 
1461         // Attribute holds a boolean integer.
1462         TYPE_BOOLEAN = 1<<3,
1463 
1464         // Attribute holds a color value.
1465         TYPE_COLOR = 1<<4,
1466 
1467         // Attribute holds a floating point value.
1468         TYPE_FLOAT = 1<<5,
1469 
1470         // Attribute holds a dimension value, such as "20px".
1471         TYPE_DIMENSION = 1<<6,
1472 
1473         // Attribute holds a fraction value, such as "20%".
1474         TYPE_FRACTION = 1<<7,
1475 
1476         // Attribute holds an enumeration.  The enumeration values are
1477         // supplied as additional entries in the map.
1478         TYPE_ENUM = 1<<16,
1479 
1480         // Attribute holds a bitmaks of flags.  The flag bit values are
1481         // supplied as additional entries in the map.
1482         TYPE_FLAGS = 1<<17
1483     };
1484 
1485     // Enum of localization modes, for use with ATTR_L10N.
1486     enum {
1487         L10N_NOT_REQUIRED = 0,
1488         L10N_SUGGESTED    = 1
1489     };
```

前面得到entry的个数是0xe1，entry的索引内容的起始地址是0x165c0，entryStart是起始地址是0x16944，以及它们的相关内容。
这一节的内容参考上一节的内容，不再完整复制出来。

__第一个entry__

```
10 00 01 00  00 00 00 00 00 00 00 00  |................|
00016950  01 00 00 00 00 00 00 01  08 00 00 10 01 00 00 00
```

- 0x0010 -> size -> ResTable_entry 结构体占用空间
- 0x0001 -> flags -> complex entry, holding a set of name/value mappings. ResTable_map structures array.
- 00 00 00 00 -> 索引到ResTable_package::keyStrings -> 'drawerArrowStyle'
- 00 00 00 00 -> 属于ResTable_map_entry 结构体，0表示无parent
- 0x00000001 -> 表示后续有一个ResTable_map

剩余的内容就是ResTable_map structure了。

```
00016950  01 00 00 00 00 00 00 01  08 00 00 10 01 00 00 00
```

- 01 00 00 00 -> ResTable_ref name, means this mapping's name
- 00 00 00 01 -> 0x01000000 means the name of this map
- 08 00-> Res_value size
- 00 -> Always set to 0
- 10 -> dataType -> 整数
- 0x00000001 -> data -> int 1

__第二个entry__

```
00016960  10 00 01 00 01 00 00 00  00 00 00 00 01 00 00 00  |................|
00016970  00 00 00 01 08 00 00 10  40 00 00 00
```

- 0x0010 -> size -> ResTable_entry 结构体占用空间
- 0x0001 -> complex entry
- 01 00 00 00 -> 0x01 -> 索引到ResTable_package::keyStrings -> 'height'
- 00 00 00 00 -> 属于ResTable_map_entry结构体，表示无parent
- 0x01 -> 后续一个ResTable_map

`00 00 00 01 08 00 00 10  40 00 00 00`

- 0x01000000 -> map name，与第一个entry的map name相同
- 0x0008 -> Res_value size
- 0x00 -> always set to 0
- 0x10 -> dataType -> int
- 0x00000040 -> 一个等于0x40的int数

## 下一个type spec

前面计算得到这个type spec的地址是0x18438.取内容：  

```
00018430  08 00 00 10 03 00 00 00  02 02 10 00 60 01 00 00  |............`...|
00018440  02 00 00 00 54 00 00 00  00 01 00 00 00 00 00 00  |....T...........|
00018450  00 00 00 00 00 00 00 00  00 01 00 00 00 01 00 00  |................|
```

很明显它又是一个0x0202，RES_TABLE_TYPE_SPEC。

- 0x0202
- 0x10 -> header size 
- 0x160 -> chunkSize
- 0x02 -> type id
- 0x54 -> entryCount

计算下一块内容地址：  
0x18438 + 0x160 = 0x18598

取内容：  

```
00018590  00 00 00 00 00 00 00 00  01 02 4c 00 ac 03 00 00  |..........L.....|
000185a0  02 00 00 00 54 00 00 00  9c 01 00 00 38 00 00 00  |....T.......8...|
000185b0  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
000185e0  00 00 00 00 ff ff ff ff  ff ff ff ff 00 00 00 00  |................|
000185f0  10 00 00 00 ff ff ff ff  ff ff ff ff ff ff ff ff  |................|
00018600  20 00 00 00 30 00 00 00  ff ff ff ff ff ff ff ff  | ...0...........|
```

- 0x0201 -> ResTable_type 

分析跟上面一样了，只是这里有很多0xffffffff，说明没有entry。

那么，结构已然是清晰的，每一个RES_TABLE_TYPE_SPEC_TYPE块下面都跟着一个或者多个RES_TABLE_TYPE_TYPE块。  
每一个type都具备上面的两个内容，从而指定了这个type的规范和配置信息。

这个resources.arsc具有0x0c个type，所以，必定具有0x0c对RES_TABLE_TYPE_SPEC_TYPE和多个RES_TABLE_TYPE_TYPE（这里是0xe1）。  
RES_TABLE_TYPE_TYPE的个数等于属于当前type的资源的个数，也就是每个RES_TABLE_TYPE_TYPE指定了某个资源的配置信息。

直接看到最后一个RES_TABLE_TYPE_SPEC_TYPE 0x0202

```
00032220  02 02 10 00 20 00 00 00  0c 00 00 00 04 00 00 00  |.... ...........|
00032230  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
00032240  01 02 4c 00 9c 00 00 00  0c 00 00 00 04 00 00 00  |..L.............|
00032250  5c 00 00 00 38 00 00 00  00 00 00 00 00 00 00 00  |\...8...........|
00032260  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
*
00032290  10 00 00 00 20 00 00 00  30 00 00 00 08 00 00 00  |.... ...0.......|
000322a0  d9 03 00 00 08 00 00 10  dc 00 00 00 08 00 00 00  |................|
000322b0  da 03 00 00 08 00 00 10  96 00 00 00 08 00 00 00  |................|
000322c0  db 03 00 00 08 00 00 10  7f 00 00 00 08 00 00 00  |................|
000322d0  dc 03 00 00 08 00 00 10  e7 03 00 00              |............|
```

0x0202 对应的id正好是 0x0c，等于type的个数。  
后面还跟着一个0x0102，它的id是0x0c。

顺带的，根据struct ResTable_type，分析最后一个spec块对应的entries，它们内容比较少一点，整个chunk的大小才9c。

- 0x0c -> 查找typeString得到 integer
- 0x04 -> entryCount
- 0x5c -> entryStart -> 0x32240 + 0x5c = 0x3229c

根据struct ResTable_config：

- size = 0x38 -> 其实几乎都是0，默认嘛。
- mcc/mnc = 0x0000/0x0000 -> any
- language/country = 0x0000/0x0000 -> any
- locale = 0x00000000 -> any
- 其它等等等

config的结束地址： 0x32254 + 0x38 = 0x3228c

后续的是什么内容呢？ 应当是具体的entry了。

## aapt 分析resources 

`aapt d resources app-debug.apk`

取部分信息：  

```
4189     type 11 configCount=1 entryCount=4
4190       spec resource 0x7f0c0000 com.archos.myapplication:integer/abc_config_activityDefaultDur: flags=0x00000000
4191       spec resource 0x7f0c0001 com.archos.myapplication:integer/abc_config_activityShortDur: flags=0x00000000
4192       spec resource 0x7f0c0002 com.archos.myapplication:integer/cancel_button_image_alpha: flags=0x00000000
4193       spec resource 0x7f0c0003 com.archos.myapplication:integer/status_bar_notification_info_maxnum: flags=0x00000000
4194       config (default):
4195         resource 0x7f0c0000 com.archos.myapplication:integer/abc_config_activityDefaultDur: t=0x10 d=0x000000dc (s=0x0008 r=0x00)
4196         resource 0x7f0c0001 com.archos.myapplication:integer/abc_config_activityShortDur: t=0x10 d=0x00000096 (s=0x0008 r=0x00)
4197         resource 0x7f0c0002 com.archos.myapplication:integer/cancel_button_image_alpha: t=0x10 d=0x0000007f (s=0x0008 r=0x00)
4198         resource 0x7f0c0003 com.archos.myapplication:integer/status_bar_notification_info_maxnum: t=0x10 d=0x000003e7 (s=0x0008 r=0x00)
```

对于最后一个type 11(0x0c)，一个config表项，4个entry。有一个config，表示只有default的，没有其它的特定配置。

aapt输出config的格式如下：  

`resource <Resource ID> <Package Name>:<Type>/<Name>: t=<DataType> d=<Data> (s=<Size> r=<Res0>)`
  
Resource ID R.java中的资源ID   
Package Name 资源所在的的包   
Type 资源的类型   
Name 资源名称   
DataType 数据类型,按照以下枚举类型取值   
Data 资源的值,根据dataType进行解释   
Size 一直为0x0008   
Res0 固定为0x00  

比如：`resource 0x7f0c0000 com.archos.myapplication:integer/abc_config_activityDefaultDur: t=0x10 d=0x000000dc (s=0x0008 r=0x00)`

Resource ID   0x7f0c0000  
Package Name  com.archos.myapplication  
Type integer  
Name    abc_config_activityDefaultDur  
DataType 0x10表示integer
Data  0x000000dc 转换成十进制integer = 220

## 参考文献

[解析resources.arsc](http://blog.csdn.net/beyond702/article/details/51744082)







