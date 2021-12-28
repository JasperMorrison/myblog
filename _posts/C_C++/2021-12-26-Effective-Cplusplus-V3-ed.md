---
layout: post
title: Effective-Cplusplus-V3-ed
categories: C/C++
tags: C/C++ Effective-Cplusplus-V3-ed
author: Jasper
---

* content
{:toc}
本文列举一些自己容易忽略或者本身比较重要的《Effective C\+\+ V3 ed》 skill or experiences。



## 03 const

以const 和 char的组合为例，介绍const不同的位置表示的含义。

```
const char *p // p是一个指向const char的指针，我们无法通过p修改该char的值
char const *p // 同上，当使用typedef，往往需要将const放到类型之后
char * const p // p是一个const 指针，我们不能修改p，将其指向其它char
const char * const p // p 和 char都是const，既无法修改p的指向，也无法通过p修改char的内容
char const * const p // 同上，当使用typedef，往往需要将const放到类型之后
```

习惯用const的好处很多，避免了意想不到的赋值操作。比如：

```
Rational a,b,c;
Rational func();
如果我们用const限定，则，下面的问题就能不会发生，编译失败。
(a*b) = c;
if (a*b = c) ...;
```

STL中如何使用const迭代器，两个概念：  
1. iterator是const的，我们无法修改iterator指向下一个位置；  
2. iterator指向的内容是const，我们无法通过iterator修改该值。

```
const std::vector<int>::iterator iter = vec.begin(); // const iterator，iterator不可指向下一个位置
std::vector<int>::const_iterator iter = vec.begin(); // iterator const，内容不可修改
```

const修饰成员函数

const在函数前面，表示返回值是const类型。const在函数后面，表示这个成员函数不允许修改成员变量（编译时会报错）。
当我们定义op时，就可以通过const来指定这个op的读写属性。这种概念称为bitwise_constness

但是，如果我们希望在读取const成员变量的同时，先更新该变量，再返回给调用端。从调用端的角度看，该函数并没有修改成员变量，调用端获得了最新的可靠值。但从成员函数看来，这个成员函数不是严格意义的const函数，因为它的确修改了const变量。这种概念称为logic_constness。

## 04 确认对象被使用前已先初始化

对于内置类型（C part of C++），初始化行为是不确定的，我们应该手工初始化；对于non-C part of C++，初始化行为依赖于“构造函数”，我们应该明确初始化。

C++对象的成员初始化发生在进入构造函数之前，也就是说，构造函数发生在初始化行为之后。只是我们的看到的行为是，好像是构造函数完成了初始化。所以，应该为构造函数提供一个member inittialization list。这样做的好处是避免了多了一次copy assignment操作，从而影响了效率。

对于内置类型，是否写在member initialization list中，效率都是一样的，这是因为，内置类型我们在创建一个内存空间，并初始化为默认值（赋值），和创建后在构造函数中执行赋值操作，行为并没有区别。但是，为了代码好维护，或者忘记了哪些内置类型需要在构造函数体内进行初始化，建议还是在member initialization list写上内置类型的初始化。

对于不同文件的non-local static对象（同时也是non-const），初始化的顺序是得不到保证的，为了保证获得non-local static对象时，该对象已经初始化完成，应当使用一个函数（被称为reference-returning function）将non-local static转换为local static对象，并返回static对象的引用。

non-const static对象（包括local和non-local），我们通过函数封装并返回引用的方式的确解决了单线程问题，但在多线程中，依然存在不确定性。在多线程系统中，最佳做法应当是在单线程（主线程）启动阶段，主动调用所有的reference-returning funtcion。

样例：

```
Object& func()
{
    static Object obj;
    return obj;
}
```

## 05 了解C++默默编写并调用哪些函数

如果没有手工声明，编译器会自动为class声明几个东西：

1. default构造函数（这是一个无实参构造函数）（如果没有声明构造函数）
2. copy构造函数（如果成员变量是class，会自动调用成员函数的copy构造函数完成成员的copy操作，比如std::string）
2. copy assignment 操作符
3. 析构函数

所有的函数都是virtual属性，但如果该class的Base class是一个virtual class（析构函数是virtual，拥有或者没有virtual function），则析构函数默认集成Base Class的virtual属性。

对于copy assignment操作符，以下情形编译器会拒绝生成：
1. 有成员是引用类型
2. 有成员是const类型
3. Base class将copy assignment声明为private

## 07 多态基类应当声明virtual析构函数

当备忘吧，不这么做，Derived对象无法通过Base引用释放空间。

## 08 别让异常逃离析构函数

析构函数中抛出异常，会导致剩余应该释放的内存得不到释放，最终导致内存泄漏；  
抛出异常会导致变量析构，如果析构又抛出异常，连续抛出两个异常，会触发terminate函数，结束程序；

那么，当对象内发生异常时，成员对象的析构函数会不会被调用呢？

1. 普通函数抛出异常，局部变量对象（非指针）的析构函数会被调用；
2. 对象的构造函数抛出异常时，其成员对象以及基类成分的析构函数都会被调用，但对象本身的析构函数不会被调用。

Refs [异常与构造函数、析构函数](https://www.iteye.com/blog/jarfield-811703)

其中有描述到，《Inside The C++ Object Model》一书中所描述的内容，对于`Point* p = new Point()`，分为两个步骤，
1. new一份空间；
2. Point的构造函数被执行。
这两个过程，无论哪个出现异常，内存都会被自动回收。

## 09 不在构造析构函数中调用virtual函数

这是因为，base class的virtual函数从不会下降到derived class层面。

在derived class的构造函数执行前，必先执行base class的构造函数，此时，derived class尚未构建，哪来的实际函数可以调用呢？除非base class的函数是non-virtual函数，非pure的virtual函数也不行，非pure的virtual函数执行的仍然是base class中的virtual，与你认识的行为不会相符。

析构函数也是相同的道理，先析构derived class，如果还在base class的析构函数中调用virtual函数，同样存在问题。

## 10 令operator=返回一个reference to *this

这样的做法是为了与内置类型和标准库的行为保持一致，避免了使用上的误导，在=号的连续赋值的情况下就能明显体现出来。

## 11 令operator=处理“自我赋值”

使得下面这种看起来不会发生的事情合法并“安全”。
```
Widget w;
w = w;
```

应当使用swap机制完成赋值，而不是delete之后重新创建，我们必须保证有东西可以返回，无法赋值时，保持原样，所谓的copy\-and\-swap。

## 13 在资源管理器中小心coping行为

首先，我们建议以对象管理资源，并使用RAII方式在获得资源时立即建立资源的管理对象，而不是在构造函数中进行一次赋值操作。

我们可以简单的使用auto\_ptr或者shared\_ptr进行资源管理，但是，并不是所有的资源都适用。当我们需要自己的class进行资源管理时，应当充分考虑资源的特性，总得来说，我们应当小心资源的coping行为。

当RAII对象被复制时，会发生什么？

比如我们使用一个class管理一个Mutex，在初始化列表中对成员变量进行赋值，在构造函数中进行Mutex上锁，在析构函数中，对Mutex进行解锁。但这个RAII对象被复制，会发生什么？很难说，复制一个锁，并同时被两个RAII释放锁会发生什么事情。

我们可以这样：
1. 禁止复制，比如继承boost::noncopyable可以禁止复制；
2. 底层资源使用“引用计数”，复制增加引用，当没有引用时，表示可以释放；
3. 手动复制底层资源；
4. 转移所有权，比如unique\_lock，赋值行为导致“移动”而不是“复制”。

## 17 独立语句将newed对象植入智能指针

很多同学自以为自己写出了漂亮的代码：

```
func(std::shared_ptr<Widget>(new Widget), priority());
```

上述代码存在三个行为：
1. new Widget
2. make shared\_ptr
3. call priority()

而且，这三个行为的先后顺序是得不到保证的，当然，new一定在make shared\_ptr之前完成。

如果call priority()在第二步被执行，然后抛出异常，程序不会继续将Widget对象装入shared\_ptr，这个没人管的野孩子最终会导致资源泄漏。

## 20 传引用替代传值

如果我们函数内部明确不需要copy操作，传引用往往比传值高效（避免了copy操作）。更重要的是，传值有时候会导致对象被“切割”：

```
void func(Base w) // 对象可能被“切割”
{
    w.func1();
}
Derived d;
func(d);
```

上述代码中，func内调用了Base的func1，而不是Derived的func1。
题外话：如果func1是一个virtual function，则不能是一个pure virual funcion，此时Base属于一个abstract type，我们无法为abstract type创建对象，也就保证了传递给func的参数一定是一个衍生类对象。

当传递引用后，如果我们希望在函数内获得一个新的对象，而不是对象的引用。我们应当手动通过复制构造函数创建一个，like this:

```
void func(Object& o)
{
    Object new_o(o);
    // Derived new_o(o); // Derived: public Object，错误，无法从Object创建Derived，除非我们有特定的构造函数。
}
```

## 23 宁以non-menber，non-friend函数替代member函数

当我们需要添加一些Class的辅助函数，而这些辅助函数有不会有实质性的新增操作，就应当设计为non-menber，non-friend函数。比如，Class原本有clearA，clearB等清理函数。我们希望新增一个辅助函数clearALL来执行所有的清理操作，由于clearALL并没有新增任何实质性的操作，仅仅是提一个便利，将其添加到Class中，将增加了一个可以操作private变量的成员函数，反而影响了Class的封装性。

应当定义在同一个namespace中的普通函数，比如：clearALL(Class& obj);

## 27 少做转型动作

- const\_cast: 唯一具备将const属性移除的转型操作
- dynamic\_cast: 动态执行向下转型，执行前进行类型检查，如果不匹配返回空，较耗时
- reinterpret\_cast: 执行低级转型，比如将pointer转换为int等，依赖编译器行为
- static\_cast: 强制转型，除了const\_cast，任何转型行为都可以做

我们不能通过dynamic\_cast将一个Derived Class转型为Base Class，再调用Base Class的func作用于Derived Class，dynamic\_cast会创建一个转型副本。

为了避免转型，我们可以通过Derived Class直接调用func，或者通过Base Class设计 virtual function的方式实现多态。

## 31 将文件间的编译依存关系降至最低

本意是将接口和实现分离，将声明式和定义式分别存放在两个文件中，客户端在库的实现变更后，无需重新编译代码。实现方式有两种：

1. Handle classes：参考pimpl实现方式；   
2. Interface classes：将接口声明为virtual function。

拓展的，QT的实现方式也是一种。

但是应当注意的是，Interface classes的实现方式不建议使用于库接口开发，因为COM的层层继承关系网被人们诟病。

## 35 考虑virtual函数以外的其它选择

除了使用virtual实现多态，还可以使用non-virtual。Base Class中定义一个public的non-virtual funcion，和一个private的virtual function，并在non-virtual中调用virtual。Derived Class中复写这个virtual function，每一个Derived的行为由自己决定。这样在Base Class中的non-virtual中，就可以做一些统一的操作，比如加锁、某些公共的前处理等。

还可以使用tr1::function来进行函数绑定，如果是非静态成员函数，则需要使用std::bind进行动态函数绑定。关于tr1::function和std::bind，可以查阅网络资料，tr1::function就好比一个函数指针，但比函数指针要更强大一些。

## 37 不要重新定义继承而来的缺省参数值

这是因为C++对virtual function的绑定方式（动态绑定）和对缺省参数值的绑定方式（静态绑定）不相同，导致通过不同的Class类型引用函数时，获得的缺省参数值可能不一致。

简单来说，不同类型的指针引用到同一个对象，调用函数时，缺省参数值的默认值不是同一个。

```
Base *b = new Derived();
b->func(); // virtual void func(int param=0);，正确调用，默认参数值是0
Derived *d = b;// virtual void func(int param=1);，正确调用，但默认参数值是1，而不是Base中的0.
```

处理方法：
1. 不要给缺省值
2. 使用non-virtual中调用virtual的方式进行替代

有人可能会问，我保证Base和Derived中的缺省值一样行吗？答案是可以，不过一旦要变更时，两份代码都得保持一致，你完美得创建了一个潘多拉盒子。

# 参考

《Effective C\+\+ V3 ed》