---
layout: post
title: Protobuf（五）：最佳实践
categories: Protobuf 
tags: Protobuf RPC gRPC
author: Jasper
---

* content
{:toc}

本文是protobuf best practices的概要性比较，整理了一下实际使用过程中比较常见的注意点和实践经验。



# Proto Best Practices

- Don’t Re-use a Tag Number   
  别重用tag number ，这个会破坏反序列化的正确性。
- Don’t Change the Type of a Field  
  满足兼容性的field可以变更type，但在工程上，我们极力不推荐去做这个事。
- Don’t Add a Required Field  
  required field从长远来看，就是一个破坏兼容性的做法，proto3干脆直接去掉这个option。
- Don’t Make a Message with Lots of Fields  
  何为“多”？百个或者说几百个为多，C++里面，最多使用8个字节来存储字段的长度，但是，还需要存储一些其它辅助信息，比如字段是否被赋值过等等。具体多少是上限，官网没有给出来。
- Enum相关的这里直接忽略；
- Do Use Well-Known Types and Common Types  
  推荐使用一些公开常用的公共类型，这些类型会给我们带来较多的便利；
  ![](/images/protobuf/shared_common_types.jpg)
- Do Define Widely-used Message Types in Separate Files  
  倡导将需要提供给外部“广泛使用”的Message，定义在独立的文件中，不要与工程内部的protobuf定义混淆在相同的文件中。
- Do Reserve Tag Numbers for Deleted Fields  
  注意将已删除的field number和 field names置为reserved。
- Don’t Change the Default Value of a Field  
  这里涉及field presence问题，我们认为，保持让工具本身设置默认值是最佳的兼容性做法。
- Don’t Go from Repeated to Scalar  
  标量与重复量之间转换要慎重，笔者认为，直接避免这种做法为好。
- Never Use Text-format Messages for Interchange  
  Text-format是仅供调试使用的，不要使用于消息交换。因为protobuf的兼容性保证并不包括field name。
- Never Rely on Serialization Stability Across Builds  
  这里的意思是proto编译工具的跨版本问题，跨版本编译工具得到的代码相互之间是不保证兼容性的。实际上，处理C++，相同Major版本的编译工具是保证兼容性的，官方有这样的承诺。
- Don’t Generate Java Protos in the Same Java Package as Other Code  
  这里意思是，最好你现有的java package的后面加上".proto"作为protobuf所生成java代码的包名。

# API Best Practices

这里不是特定语言（如：C/C++、 Java等）的API最佳实践，而是对上一个小节的补充，我们希望这个小节，可以帮助开发者开发出长期稳定、API兼容性极佳的protobuf程度。


- Use Different Messages for Wire and Storage  
  存储和交换使用不同的Message，这样会给兼容性开发带来极大的好处。
- Don’t Include Primitive Types in a Top-level Request or Response Proto  
  这个记录一下，提示：不要在Top-level的请求或者响应的proto中包含原始类型，可以保持请求或者响应proto不用频繁变更。
- Rarely Use an Integer Field for an ID  
  不要使用整型数作为对象的唯一标识，int64很诱人，但是不一定够。使用string反而可以保持较好的拓展性。
- Don’t Encode Data in a String That You Expect a Client to Construct or Parse  
  这是说，不要把你的结构型数据编码为string。我常常看到有同事将结构型数据编码为string，并为某种字符将其隔开，比如逗号、分号。
- Make Repeated Fields Messages, Not Scalars or Enums  
  这个的思路与前面的封装思想是一样的，在创建repeated字段时，不要使用原始类型，是应该创建一个message来包装这个原始类型，这样做的好处是，可以对这个message进行升级，而无需修改顶层结构。
- Bound Request and Response Sizes  
  这个很重要，我们应该限定proto message的大小，往repeated中传递数据时，应当先进行大小检查。
- Returning Repeated Fields  
  repeated field如果是empty的，接收端无法仅仅通过这个信息判断是否正确响应，有可能是发送端因出错而没有填充数据，也有可能是数据的确是empty的。建议的方案是使用一个mask字段来表示哪些字段已经正确填充或者故意留空。笔者认为，这个有点类似field presence问题，可以根据自己的业务实际情况，选择性使用[field mask](https://protobuf.dev/programming-guides/api/#include-field-read-mask)  
- Order Independence in Repeated Fields  
  这是一个设计上的改进建议，我们应该保证重复字段的次序独立性。什么意思呢？就是说，我们不应该将repeated包含原始类型，而应该对原始类型封装一下。这样，repeated中的每一个具体的值，相互的关系有封装的类型决定，而不是它们的位置决定。这个设计理念也是重复出现了，可以根据实际应用来进行考量。
- Performance Optimizations  
  性能优化是实际中比较值得学习的地方。  
  - 少量的字段肯定比大量的字段解析得更快；
  - 将大的message分割为多个小的message；
  - 声明延迟解析，“lazily parsed” with [lazy=true]；
  - 直接将filed声明为bytes，并指定其类型，让解析端根据需要将其解析为对应的数据类型；但这是一个危险的做法，不建议做；

# 参考

[https://protobuf.dev/programming-guides/dos-donts/](https://protobuf.dev/programming-guides/dos-donts/)  
[https://protobuf.dev/programming-guides/api/](https://protobuf.dev/programming-guides/api/) 
