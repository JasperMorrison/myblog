---
layout: post
title: 关于Protobuf
categories: Protobuf 
tags: Protobuf RPC gRPC
author: Jasper
---

* content
{:toc}

本文介绍什么是Protobuf，简述原理概念，描述它的历史和应用场景。希望可以给读者一个Protobuf的入门认识，以及给进一步学习和应用Protobuf提供帮助。




# 什么是Protobuf

> Protocol buffers are Google’s language-neutral, platform-neutral, extensible mechanism for serializing structured data

引用并翻译官方的原话，Protobuf 是Google开发的，一种与语言无关、平台无关、可拓展的结构数据序列化机制。可类比于XML、Json以及Android的Parcelable。

protobuf以message为对象定义在.proto后缀的文件中，形如：

```
syntax = "proto3";

message Person {
  string name = 1;
  int32 id = 2;
  string email = 3;
}
```


它目前有两个版本，分别是proto2和proto3，版本的相互兼容性做得较好，基本可以互相解析，但是新的序列化需求，还是建议使用proto3，更简洁好用。

proto2支持Java, Python, Objective-C, and C++；proto3额外支持Kotlin, Dart, Go, Ruby, PHP, and C#.

# Protobuf应用场景

Protobuf被应用在gRPC、Google Cloud、Envoy Proxy、众多微服务架构，以及Android对象序列化。使用Protobuf的初衷，除了序列化需求以外，更多的可能是看上了它的超高兼容性、高压缩率、语言和平台无惯性。

除了应用于RPC通信，将protobuf用于本地文件存储也是一种不错的应用场景。

## gRPC

![](/images/protobuf/gRPC.png)

RPC：远程过程调用机制，比如Android中的Binder，就是一种典型的RPC机制的实现。

gRPC是众多网络RPC中的大佬，基于http/2和protobuf实现，目前具有绝对的优势。

## Android对象序列化

原生的Android Framework，protobuf主要用于对log的压缩，比如AMS中打印dump信息到protobuf，就是一种log压缩的应用。  
但是，由于我们看上了其除了序列化意外的其它特性，仍然有信心将其应用于本地Binder通信，可以达到对数据进行压缩、提高模块间接口版本兼容性的目的。

# protobuf原理简述

protobuf是这么个工作流程：

![](/images/protobuf/protocol-buffers-concepts.png)

编译器（protoc工具）将.proto文件编译为指定的目标语言的源代码，RPC的client端和server端持有相同的.proto文件，各自生成自己的目标源代码。这些源代码与工程代码一起编译，最终由protobuf完成对数据的序列化。

在客户端，以java为例，如此序列化对象：

```java
Person john = Person.newBuilder()
    .setId(1234)
    .setName("John Doe")
    .setEmail("jdoe@example.com")
    .build();
output = new FileOutputStream(args[0]);
john.writeTo(output);
```

在服务端，可以使用任意支持的语言来解析反序列化，还是以java为例：

```java
Person john;
fstream input(argv[1], ios::in | ios::binary);
john.ParseFromIstream(&input);
int id = john.id();
std::string name = john.name();
std::string email = john.email();
```

一个完成的RPC的序列化和反序列化过程可以概括为：  
![](/images/protobuf/rpc-concepts.png)

# protobuf的历史

最初，在Google内部，protobuf仅仅是开发人员期望为一个名为ProtocolBuffer的clsses通过一个唯一的函数`AddValues(tag, value)`来添加tag/value数据对，数据被保存在buffer中，并支持将其写出（应该是文件）。

从那时候起，大家就喜欢用“protocol message”表示一个抽象的message，“protocol buffer”表示一个已经被序列化的message，“protocol message object”表示一个存在内存中已解析好的message。

历史线：  
2001(version1)：闭源，内部使用，几经修改；  
2008(version2)：开源，去除了对Google闭源库的依赖；  
2016(version3)：更简洁好用，更多的语言支持；

# xml json protobuf的对比

对比主要从几个方面考虑：  
1. 存储格式；
2. 大小；
3. 序列化和反序列化性能；
4. 项目实用性；
5. 兼容性；

先看看三者的数据样例：  
值得注意的是，样例中大部分都是以字符串的形式表示数据，这个与实际使用比较相符。具体的压缩率与数据形式关系很多大。

![](/images/protobuf/xml_json_protobuf_diff_data_json.webp)

![](/images/protobuf/xml_json_protobuf_diff_data_xml.webp)  

![](/images/protobuf/xml_json_protobuf_diff_data_protobuf.webp)

## 存储格式

二进制的存储格式无法直接阅读，需要对应的.proto文件进行解析；  
![](/images/protobuf/xml_json_protobuf_diff_1.jpeg) 

不过protobuf支持使用json-format保存数据，不过仅限本地。  
同时protobuf也支持使用可解释的protobuf二进制文件，对端可以不用知道.proto文件解析出原始数据格式，当然，这也需要用到更多的存储空间。

## 大小及性能

从理论上将，同一份数据，以json作为基线，若转换为xml格式，key可能会double一份，若转换为protobuf格式，直接省略了key，并在数据上会得到一定的压缩。所以，最终的数据大小可能是, json:xml:protobuf = 1:2:0.5 。

![](/images/protobuf/xml_json_protobuf_diff_2.jpeg)

![](/images/protobuf/xml_json_protobuf_diff_3.jpeg)

![](/images/protobuf/xml_json_protobuf_diff_4.webp)

![](/images/protobuf/xml_json_protobuf_diff_5.webp)

## 项目实用性

protobuf不利于对数据进行可视化，不利于web调试。但配合使用json格式来传输对应protobuf的文件名，那么RPC的对端可以很轻易的快速解析出protobuf二进制数据为可视化数据。

json和xml可读性强，但是解析代码没有protobuf简洁。

## 兼容性

protobuf可以做到极好的前后兼容性， 这里说的兼容性，主要是.proto文件的兼容性。在新增和删除字段后，利用旧.proto文件解析二进制数据仍然可以正常工作，反之亦然。

在源码方面，不同版本的protoc工具，生成的c++代码不具备兼容性。同一个主版本的生成工具生成的源代码，除了c++语言之外的其它语言，保证具有兼容性。不过源代码一般不用担心兼容性问题，项目上基本都是编译时根据.proto文件自动生成的。

# 参考

[https://protobuf.dev/](https://protobuf.dev/)  
[https://zhuanlan.zhihu.com/p/91313277](https://zhuanlan.zhihu.com/p/91313277)  
