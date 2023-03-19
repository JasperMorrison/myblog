---
layout: post
title: Protobuf（四）：语言指南
categories: Protobuf 
tags: Protobuf Language Guide
author: Jasper
---

* content
{:toc}

本文是protobuf的语言概要性指南，写了一些自认为比较重要和容易忘记的语言指导内容，详情请到官网查看。本文不会告诉你，在.proto头部需要定义`syntax = "proto3";`，这样的常规常见的知识点。



# Field Numbers

支持范围 1 ~ 2^29 - 1, 19000 ~ 19999作为protobuf内部使用的除外。

# File Rules

proto3中默认使用singular、repeated和maps三个字段属性，可选地使用optional，optional需要指定特殊的protoc编译参数。

其中，singular与optional几乎同义，区别在于singular是`no presence`模式的，具体看前面的文章，提到的Field Presence内容。

# Reserved Fields

```protobuf
message Foo {
  reserved 2, 15, 9 to 11;
  reserved "foo", "bar";
}
```

将Field number定义为reserved，可以保持.proto的向前兼容性，当使用相同的.proto文件来解析旧的已编码数据时，能避免出错。

指定 filed name为reserved，可以避免在解析JSON时出错，proto3是支持便捷的JSON互转的。

# Scalar Value Types

标量数据类型很重要，可以直接通过查表获得，它体现了.proto中的数据类型与各种支持语言的数据类型之间的关系。设计和开发过程中，我们会经常需要查表。

# Default Values

字段的默认值，在proto3中是工具默认指定的，开发者无法设置自定义的默认值。

![](/images/protobuf/default_values.jpg)

# 枚举变量

枚举变量在不同的语言中，会有不同的表示和处理方式，而且它的兼容性也不大好，如果不是特别必要，不使用枚举是最好的选择。

枚举的实际行为分为两种：
- open
- closed

主要描述了对一个Enum变量赋值为其它不在Enum范围内的值时，具体的表现行为。由于这两种行为的存在，多种语言在proto2和proto3中不具备很好的兼容性。

具体参考：[Enum Behavior](https://protobuf.dev/programming-guides/enum/)

## 枚举默认值

与字段默认一样，可以定义field number和field name为reserved，并且，可以使用to和max表示一些范围的数值。

```protobuf
enum Foo {
  reserved 2, 15, 9 to 11, 40 to max;
  reserved "FOO", "BAR";
}
```

# 更新message类型

当对.proto文件进行类型更新时，需要遵循一定的规则以保持兼容性：

- 不要变更field number；
- 新增field后，新代码可以解析由旧代码序列化的数据流，并注意默认值；当然，旧代码肯定可以解析由新代码序列化而来的数据流；
- 删除字段只需要将其置为reserved；
- int32, uint32, int64, uint64, and bool，它们是完全兼容的，如果解析端与编码端类型不一致，会进行强制的类型转换，比如int64会被强制类型转换为int32；
- sint32 and sint64是相互兼容的，但与其它类型并不兼容；
- string and bytes在UTF-8模式下是完全兼容的;
- fixed32与sfixed32兼容，fixed64与sfixed64兼容；

# Unknown Fields

未知字段的处理，目前还不清楚它的重要性。以往，proto3总是在解析是丢弃位置字段，但在3.5版本之后，会保留这些未知字段的值，并在序列化时将它们重新放到序列化输出中。

也就是说：我不丢弃，但我也不处理，直接原封不动的返还到序列化输出中，以便下一级有人需要可以使用。

# Any类型的字段

Any是比较牛逼的存在，可以理解为泛型。在解析端，我们可以利用类似java中的instanceof来判断是否与既定的类型匹配，如果匹配，则进一步解析为既定的类型。

```protobuf
import "google/protobuf/any.proto";

message ErrorStatus {
  string message = 1;
  repeated google.protobuf.Any details = 2;
}
```

可以看到，我们需要import Any的实现，默认的库是不支持的。

```protobuf
// Storing an arbitrary message type in Any.
NetworkErrorDetails details = ...;
ErrorStatus status;
status.add_details()->PackFrom(details);

// Reading an arbitrary message from Any.
ErrorStatus status = ...;
for (const google::protobuf::Any& detail : status.details()) {
  if (detail.Is<NetworkErrorDetails>()) {
    NetworkErrorDetails network_error;
    detail.UnpackTo(&network_error);
    ... processing network_error ...
  }
}
```

# Oneof类型的字段

Oneof与Any含义上一致，只是Oneof只能从指定的类型中选择，不能是任意的。而且，Oneof以最后一个设置的类型值为准，同时，Oneof不支持map和repeated。

```protobuf
message SampleMessage {
  oneof test_oneof {
    string name = 4;
    SubMessage sub_message = 9;
  }
}
```

test_oneof 字段，最终可以是string类型，也可能是SubMessage类型。

由于最终的类型不确定，所以，在使用的时候，就要特别注意，像C++这种，很容易导致crash问题发生。

同样在C++中，如果我们对两个Message执行Swap()操作，Oneof的类型会被替换为目标Message中对应的字段类型。

## Oneof的兼容性问题

Oneof不具备很好的兼容性，笔者干脆也不建议使用。

# Maps类型的字段

Map与我们一般语言的map相同，并且，Map中的key是有序的。

## Maps的兼容性

由于Map是被实现为Message和repeated的组合形式，所以，它的兼容性是很好的。

# Packages

在C++中，Packages被当做namespace，在java中会被当做packge。我们提议，在Packages中尾部多加.proto后缀，可以避免namespace冲突和包名冲突。

比如将com.android.something，定义为com.android.something.proto

# JSON Mapping

在proto3中，是支持编码为JSON的，同样，这个功能默认不在库中支持，需要自己在编译时加上支持的src。

具体使用的时候，参考官网的规则：[https://protobuf.dev/programming-guides/proto3/#json](https://protobuf.dev/programming-guides/proto3/#json)

# 参考

[https://protobuf.dev/programming-guides/proto3](https://protobuf.dev/programming-guides/proto3)


