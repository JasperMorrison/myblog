---
layout: post
title: 使用Optional实现可链式调用的策略模式
categories: Java
tags: Java 设计模式 策略模式 链式调用
author: Jasper
---

* content
{:toc}

本文介绍一个使用Java Optional实现策略模式的链式调用，以加减法运算为例，假设一个运算操作需要由一个加法策略和一个减法策略来公共完成，加法策略和减法策略都可以调用任意次。我们希望链式调用可以**从中间退出**。



# 1. 实例

一个链式调用的策略模式，使用起来就像这样，认真看下面的代码：
```java
Choreographer grapher = new Choreographer();
Choreographer t = Optional.ofNullable(grapher)
    .map(g -> g.apply(new ActionAdd(), 1))
    .map(g -> g.apply(new ActionAdd(), 2))
    .map(g -> g.apply(new ActionSub(), 1))
    .orElse(grapher);
int result = Optional.ofNullable(t).map(g -> g.getResult()).orElse(0);
System.out.println("Got result:" + result);
```
上述代码实现了运算0+1+2-1=2。我们只需要往map后面追加Action，就能添加更多的加减运算。每一个加减运算都可以认为是一个策略，策略的添加、删除、调整顺序都是非常方便的。更重要的是，它可以从中途退出，比如这样，假设中间某个策略出错了，用函数end()代替。代码就像这样：

```java
Choreographer grapher = null;
IAction add = new ActionAdd();
Choreographer t = Optional.ofNullable(grapher)
    .map(g -> g.apply(add, 1))
    .map(g -> g.end())
    .map(g -> g.apply(add, 1))
    .orElse(grapher);
int result = Optional.ofNullable(t).map(g -> g.getResult()).orElse(0);
System.out.println("Got result:" + result);
```
上述代码本来要做0+1+1=2，结果中间的end()提前退出了，导致只得到0+1=1.
也就是说，策略链中某个策略如果判定应当退出，就可以立即推出，后续的策略都不会继续执行了。

# 2. Action

我把策略定义了一个个Action，Action作用在目标上，使得目标发生变化。

IAction.java

```java
public interface IAction {
    public int doCmd(int a, int b);
}
```

由于我们只是加减法，仅对两个数执行操作。

定义一个加法类，ActionAdd.java

```java
public class ActionAdd implements IAction {
    public int doCmd(int a, int b) {
        return a+b;
    }
}
```

再定义一个减法类，ActionSub.java

```java
public class ActionSub implements IAction {
    public int doCmd(int a, int b) {
        return a-b;
    }
}
```

# 3. Choreographer

定义一个编舞者，它来编织整个计算过程，调用加减法Action来完成。

```java
public class Choreographer {
    private int result = 0;
    Choreographer apply(IAction action, int a) {
        result = action.doCmd(result, a);
        return this;
    }
    Choreographer end() {
        return null;
    }
    int getResult() {
        return result;
    }
}
```

apply()：用来对编舞者的状态进行变更，利用传进来的Action和整数对自身的整数运行一个策略行为。

# 4. App

在App中，利用编舞者，传入Action，让编舞者执行各个Action，完成运算任务。  
值得注意的是，编舞者的内部数组是0。

```java
import java.util.Optional;

/**
 * 用链式调用来调用各种算术算子，假设结果一定不会等于0，等于0表示出错。
 */
public class App {
    /**
     * 看：1+1=2
     */
    private static void test1() {
        Choreographer grapher = new Choreographer();
        IAction add = new ActionAdd();
        Choreographer t = Optional.ofNullable(grapher)
            .map(g -> g.apply(add, 1))
            .map(g -> g.apply(add, 1))
            .orElse(grapher);
        int result = Optional.ofNullable(t).map(g -> g.getResult()).orElse(0);
        System.out.println("Got result:" + result);
    }
    /**
     * 策略链：很多策略连接在一起，形成了一条长长的策略链。
     * 链式调用的中间出错，或者我们想中途退出策略链，有一个null返回，导致：1+1=1
     */
    private static void test2() {
        Choreographer grapher = new Choreographer();
        IAction add = new ActionAdd();
        Choreographer t = Optional.ofNullable(grapher)
            .map(g -> g.apply(add, 1))
            .map(g -> g.end())
            .map(g -> g.apply(add, 1))
            .orElse(grapher);
        int result = Optional.ofNullable(t).map(g -> g.getResult()).orElse(0);
        System.out.println("Got result:" + result);
    }
    /**
     * 如果调用链的开始对象是null，则整个代码什么也没做，导致：1+1=0
     */
    private static void test3() {
        Choreographer grapher = null;
        IAction add = new ActionAdd();
        Choreographer t = Optional.ofNullable(grapher)
            .map(g -> g.apply(add, 1))
            .map(g -> g.end())
            .map(g -> g.apply(add, 1))
            .orElse(grapher);
        int result = Optional.ofNullable(t).map(g -> g.getResult()).orElse(0);
        System.out.println("Got result:" + result);
    }
    /**
     * 可以添加多个Action，组合在一起，结果：1+2-1=2
     */
    private static void test4() {
        Choreographer grapher = new Choreographer();
        Choreographer t = Optional.ofNullable(grapher)
            .map(g -> g.apply(new ActionAdd(), 1))
            .map(g -> g.apply(new ActionAdd(), 2))
            .map(g -> g.apply(new ActionSub(), 1))
            .orElse(grapher);
        int result = Optional.ofNullable(t).map(g -> g.getResult()).orElse(0);
        System.out.println("Got result:" + result);
    }
    public static void main(String[] args) throws Exception {
        System.out.println("Hello, World!");
        test1();
        test2();
        test3();
        test4();
    }
}
```

test1(): 0+1+1=2，并正确拿到结果；  
test2(): 用end()来模拟中间某个策略环节出了问题，或者不符合计算条件，或者说已经完成任务了，可以提前退出，0+1=1.  
test3(): 充分体现了Optional的优势，不用处理null的情况。  
test4(): 可以将很多Action堆积起来，按顺序执行策略，添加、删除、调整顺序都是非常方便的。

# 5. 总结

1. 从java8开始，Optional可以避免处理空指针异常，但是使用起来没有Kotlin、Groovy的'?.'用起来方便。  
2. 利用Optional也可以实现链式调用，在函数的结尾返回this即可。
3. 如果Action需要指示Choreographer提前退出，重构为返回IAction，然后Choreographer返回end()，调用链自动退出（这一点需要读者自己重构一下）。


# 6. 参考

[Tired of Null Pointer Exceptions? Consider Using Java SE 8's "Optional"!](https://www.oracle.com/technical-resources/articles/java/java8-optional.html)
