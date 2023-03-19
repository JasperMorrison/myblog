---
layout: post
title: Protobuf（三）：技术探讨
categories: Protobuf 
tags: Protobuf RPC gRPC
author: Jasper
---

* content
{:toc}

本文描述了几个protobuf在技术设计和实现方面的几个技术问题，以增强对protobuf设计原理的理解。包括：单文件多message、大数据、自描述性、字段存在性。



# 多个message写入文件或者stream

protobuf本身不支持将多个独立的message写入同一个文件或者stream中，protobuf不具备message的开始和结束标志。

替代方案是，可以在message之前插入一个代表message占用空间大小的数字，读取的时候，根据长度读取每一个message。

或者，干脆不要这样做。

# 大文件

protobuf对大文件操作不友好，它在解析的时候，需要将所有数据都读进内存再进行解码，原则上需要根据内存大小设计protobuf协议。

但是，如果你的单个protobuf数据超过1MB，是否应该考虑你的设计是否存在问题。替代方案，如数据库之类的更适合你。

# message的自描述性

`Self-describing Messages`，指的是在解析端，不需要对应的.proto文件，就可以从二进制数据流中解析出protobuf message object。

proto支持这样做，但是，这个功能并不包含在默认的protobuf库中，因为，我们没有发现有人需要这样用。


```protobuf
syntax = "proto3";

import "google/protobuf/any.proto";
import "google/protobuf/descriptor.proto";

message SelfDescribingMessage {
  // Set of FileDescriptorProtos which describe the type and its dependencies.
  google.protobuf.FileDescriptorSet descriptor_set = 1;

  // The message and its type, encoded as an Any message.
  google.protobuf.Any message = 2;
}
```

By using classes like DynamicMessage (available in C++ and Java), you can then write tools which can manipulate SelfDescribingMessages.

在C++和Java语言中，有支持的类供使用。

# Field Presence

我翻译为“字段存在性”，它表述了一个protobuf field是否存在value的概念。存在性有两种说法：

- no presence，代表有没有值，从值的"有没有"单纯考虑
- explicit presence，除了"有没有"值，还表述了是有调用过API设置过字段的值

大片的英文解释就不翻译了，总得来说，它在思考要不要字段默认值的问题。

在proto3中，默认是使用no presence模式，如果有值，表示已经被设置过了，如果没有值，则留空，解析的时候使用规定的默认值，而不直接关心值是否有被API设置过，也不允许在.proto中显示指定字段的默认值。

可选的，在proto3中，可以通过`--experimental_allow_proto3_optional`使能explicit presence模式，该模式允许像proto2一样标注field的optional属性，在生成的API中，可以明确通过has\*()来判断field是否被API设置过，如果没有设置过，则可以使用.proto中指定的默认值。

```protobuf
syntax = "proto3";
package example;

message MyMessage {
  // No presence:
  int32 not_tracked = 1;

  // Explicit presence:
  optional int32 tracked = 2;
}
```

最后，笔者觉得no presence模式比较好用。

# 参考

[https://protobuf.dev/programming-guides/techniques/](https://protobuf.dev/programming-guides/techniques/)  
[https://protobuf.dev/programming-guides/field_presence/](https://protobuf.dev/programming-guides/field_presence/)