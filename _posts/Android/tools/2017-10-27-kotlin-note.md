---
layout: post
title: Kotlin 的那些坑
categories: Kotlin
tags: Android Kotlin
author: Jasper
---

* content
{:toc}

Kotlin这门新语言，支持面向对象与函数式编程，它的高级特性带来让人爽翻的编程感觉，同时，也小心掉坑。这里就记录本人遇到的种种



# 作用域

```kotlin
fun main(args: Array<String>) {     
    val a:ArrayList<Int> = with(ArrayList<Int>(), {
        add(2)
        add(3)
        this
    })
	
    fun add(i: Int) {
        println(i)
    }
    add(1)
    
    with(a) {
        this.add(4) //调用ArrayList的add函数
		add(5) //调用main中的add函数
    }
    
    println(a)
}
```

输出结果：

```
1
5
[2, 3, 4]
```