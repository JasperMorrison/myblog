---
layout: post
title: Protobuf（六）：Android-Framework实战
categories: Protobuf 
tags: Protobuf RPC gRPC Android Framework
author: Jasper
---

* content
{:toc}

目前protobuf在Android-Framework被大量用于dump信息的输出，可以将dumpsys的输出压缩，更便于数据的存储和上传。除了压缩存储和网络传输外，protobuf使用在跨进程或者跨模块通信也是一个不错的选择。在Binder通信中，protobuf额外多了一次copy，你知道是为什么，以及如何改进吗？本文提供了一个思路。



# protobuf大量用于dump输出

比如AMS

```java
private void doDump(FileDescriptor fd, PrintWriter pw, String[] args, boolean useProto) {
```

如果指定最后一个参数useProto为true，将使用protobuf存储dump信息，并将其保存到fd指定的文件中。

在Android Framework中，原生提供了两个继承自ProtoStream的类：

- ProtoOutputStream：支持将数据流直接写入文件，避免了保存在buffer中，减少了一次copy；
- ProtoInputStream：读取文件，无需一次性全部从文件中读取，就能逐步解析proto二进制数据；

如果我们理解了protobuf的编解码，这两个文件的操作是非常容易理解了，这里不做解释。

# 在Binder通信中使用protobuf

与dump中使用ProtoOutputStream的方式有点不同，我们需要将其写入到byte[]。

有两种方式：  
- ProtoOutputStream创建的时候指定为保存到buffer；
- 使用Protobuf自带的SerializeToArray()接口序列化到一个buffer中，或者使用SerializeToString序列化到一个String（String必须使用UTF-8格式）；

然后，我们顶一个binder/aidl接口来传输byte[];

比如:

`byte[] getData()`

解析的时候，使用ParseFrom接口。

上述设计的序列化和反序列接口不需要记忆，在protobuf生成的源代码中，用时查询即可。

# Binder通信中protobuf会多一次copy

正如上一小节的内容，由于先序列化到byte[]，在Binder通信时，需要copy到Parcel关联的buffer中。

思路一：我们自定义一个类继承自Parcelable，然后在writeToParcel()接口中，执行protobuf的编码。而具体的编码过程，需要仿照ProtoOutputStream做一个。

思路二：如果输入发生在C++中，我们可以将Parcel的data属性强制去除const属性，然后传给protobuf的SerializeToArray().

思路三：直接使用共享内存；

# 编译脚本样例

推荐编译为独立的lib，也可以直接打包为filegroup，然后在编译c++或者java时在Android.bp中指定proto字段。

![](/images/protobuf/android_proto_build_java.jpg)

![](/images/protobuf/android_proto_build_c++.jpg)

当我们执行: `m <model_name>`， model_name是Android.bp对应库的name:后面的名称。

编译完成后，会在`out/soong/.i*/`目录下的相同相对路径中找到生成的c++源码或者java包，参考着完成你的业务编码。

# 我为什么选择在Binder通信中使用protobuf

Binder通信并不是重点，跨模块才是重点。当我们与其它业务组或者部门进行跨模块对接时，在使用protobuf是一件非常哇塞的做法。类比与微服务的开发理念，借助protobuf，可以实现具备超强前后兼容性的接口，为后续的升级维护打下很好的基础。

# 参考

源码：frameworks/base/proto/  


