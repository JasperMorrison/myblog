---
layout: post
title: C++基于对象程序设计
categories: C/C++
tags: C/C++ function bind
author: Jasper
---

* content
{:toc}

基于对象的程序设计有别于面向对象程序设计，面向对象的三要素是封装、继承、多态，而基于对象仅仅使用了封装这个要素。在基于对象程序设计中，继承和多态通过boost::function、boost::bind来实现。C\+\+11之后，`std::tr1::function、std::tr1::bind`实现了这带个接口的标准化，但是与boost有一些区别。写本文的目的，1. 这是一种让人眼前一亮的程序设计方式，之前有了解function和bind，但没想到能用到这个程度，影响整个项目的框架设计；2. 更全面的了解该技术，以及其在muduo中的应用；3. 在C++程序设计中是非常具有实战参考价值。



# 1. 基本用法

```c++
class Foo
{
public:
void methodA();
void methodInt(int a);
};

boost::function<void()> f1; // 无参数，无返回值
Foo foo;

f1 = boost::bind(&Foo::methodA, &foo);
f1(); // 调用 foo.methodA();

f1 = boost::bind(&Foo::methodInt, &foo, 42);
f1(); // 调用 foo.methodInt(42);

boost::function<void(int)> f2; // int 参数，无返回值

f2 = boost::bind(&Foo::methodInt, &foo, _1);
f2(53); // 调用 foo.methodInt(53);
```

function在定义时，内部的函数声明方式与调用方法完全相同，比如void()，则调用时无参；void(int)，调用时有一个int参数。

bind可以将对象的有参成员函数绑定为无参，也可以绑定为有参。

总得来说，在基于对象的程序设计中，仅需要一个基类，做到替代虚函数实现多态，不同的bind方式，有不同的行为。

更甚者，后面会看到，可以将一个对象的成员函数绑定到另一个对象上，从而改变另一个对象的成员函数的行为。

# 2. 对程序库的影响

程序库的目的是解耦合，但继承本身也是一种增加耦合关系的设计方式，我们能不能不使用继承也能实现程序库的多态行为呢。下面以[muduo-EchoServer](https://github.com/chenshuo/muduo-tutorial/blob/master/src/echo.cc)为例进行展示。

首先，有一个TCPServer，具备网络连接和信息传递等功能，我们希望设计一个EchoServer，能够指定其连接后的log打印和传递信息后的log打印。

思路：往TCPServer中插入一个函数指针（boost::function）。

先定义一个全局的function type：
```c++
typedef std::function<void (const TcpConnectionPtr&)> ConnectionCallback;
```

TCPServer内部定义一个前面定义的function type的成员函数，并提供接口setConnectionCallback来设置回调：
```c++
class TCPServer{
    void setConnectionCallback(const ConnectionCallback& cb)
    { connectionCallback_ = cb; }
    ConnectionCallback connectionCallback_;
}
```

EchoServer根据需要设置回调：
```c++
class EchoServer
{
 public:
  EchoServer(EventLoop* loop, const InetAddress& listenAddr)
    : loop_(loop),
      server_(loop, listenAddr, "EchoServer")
  {
    server_.setConnectionCallback(
        std::bind(&EchoServer::onConnection, this, _1));
    server_.setMessageCallback(
        std::bind(&EchoServer::onMessage, this, _1, _2, _3));
  }

  void start()
  {
    server_.start();
  }

 private:
  void onConnection(const TcpConnectionPtr& conn);

  void onMessage(const TcpConnectionPtr& conn, Buffer* buf, Timestamp time);

  EventLoop* loop_;
  TcpServer server_;
};
```

EchoServer的自定义函数：
```c++
void EchoServer::onConnection(const TcpConnectionPtr& conn)
{
  LOG_TRACE << conn->peerAddress().toIpPort() << " -> "
            << conn->localAddress().toIpPort() << " is "
            << (conn->connected() ? "UP" : "DOWN");
}

void EchoServer::onMessage(const TcpConnectionPtr& conn, Buffer* buf, Timestamp time)
{
  string msg(buf->retrieveAllAsString());
  LOG_TRACE << conn->name() << " recv " << msg.size() << " bytes at " << time.toString();
  conn->send(msg);
}
```

其实，上面的应用就是一个，使用function和bind进行回调函数设置，只是bind要比直接的明确定义的函数指针更灵活。

# 3. 对面向对象程序设计的影响

有了上面的铺垫，作者提出，我们也许应该重新思考面向对象程序设计，继承和多态是否有更加值得推广的方法，比如说function+bind。

在我看来，功能性的继承还是应该保留的，function+bind并不能将一个子类直接继承父类的成员变量。而作者思考的更多是继承这个设计是否真的有必要，毕竟它存在缺点：

1. 企鹅是鸟，但不会飞这样的例子说明，继承是不完美的；
2. 继承一旦使用，只能不断的继承+继承，程序的改进和重构摆脱不了继承的束缚；
3. 增加了代码的耦合性。

# 4. 对面向对象设计模式的影响

有了function+bind的灵活性，很多面向对的设计模型可以拜托继承又继承的那一套设计思路。

# 5. 对依赖注入和单元测试的影响

就好比上面的EchoServer，我们可以往TCPServer注入一个function，不同的bind方式得到不同的注入依赖。

对于单元测试也是同理，我们将单元测试function注入到MockServer中，替代虚函数和继承的那一套。

# 6. 什么情况下用继承

作者认为，完全可以不使用继承，必要时重构就好。

如果真的需要，会考虑使用boost::noncopyable 或 boost::enable\_shared\_from\_this。

同样的，C\+\+11标准已经集成了`enable_shared_from_this`。

`enable_shared_from_this`是一个可以将对象的this转换为shared\_ptr，避免一个shared\_ptr拥有指定对象的全部所有权的问题。直观来说，多个shared\_ptr共同维护一个对象的智能指针，引用计数同时变化，且在shared\_ptr析构时不会造成多次调用目标对象之析构函数的问题。

不过，我并没有想出来如何将其与继承挂钩。。。

# 7. 总结

function、bind的确是好东西，在替代多态，在简洁程序设计方面，替代函数继承方面，具有极佳的效果，但它不能完全替代继承。在实际使用中，灵活应用是王道。

# 8. 参考

《C\+\+工程实践经验谈--陈硕》  
《Effective C\+\+ 3rd ed 第 35 条》