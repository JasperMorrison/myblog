---
layout: post
title: Android-JIT-AOT
categories: Android逆向工程
tags: Android Reverse JIT AOT APK
author: Jasper
---

* content
{:toc}

本文记录对[JIT Compiler](https://source.android.com/devices/tech/dalvik/jit-compiler.html)的阅读理解。



## Profile-guided JIT/AOT Compilation

In Android 7.0, we've added a Just in Time (JIT) compiler with code profiling to ART, which lets it constantly improve the performance of Android apps as they run. The JIT compiler complements ART's current Ahead of Time (AOT) compiler and helps improve runtime performance, save storage space, and speed up app updates and system updates.  
从Android7.0开始，我们添加了一个JIT编译器，已提供一个code profile给ART，以此提升Android App运行性能。  
Profile-guided compilation lets ART manage the AOT/JIT compilation for each app according to its actual usage, as well as conditions on the device. For example, ART maintains a profile of each app's hot methods and can precompile and cache those methods for best performance. It leaves other parts of the app uncompiled until they are actually used.  
Profile-guided编译让ART能根据App的在具体设备上运行的实际需求来管理AOT/JIT编译行为。对于App中暂时不需要运行的部分，不进行编译，直到它们需要运行。
Besides improving performance for key parts of the app, profile-guided compilation helps reduce an app's overall RAM footprint, including associated binaries. This feature is especially important on low-memory devices.  
除了提供App关键部分的性能外，profile-guided编译还能降低App的RAM占用，包括相关联的二进制文件。这个特性对低RAM设备尤其有用。
ART manages profile-guided compilation in a way that minimizes impact on the device battery. It does precompilation only when then the device is idle and charging, saving time and battery by doing that work in advance.  
ART以一种最小化电池消耗的方式来管理profile-guided编译。他仅在设备空闲和充电的状态下进行预编译，节省时间和电池。

以上JIT的特性，能避免设备在更新app的时候运行变慢，或者能在执行OTA过程中对app进行预编译。

JIT与AOT使用几乎完全相同的编译器，但是所产生的目标文件不一定相同，看情况吧。JIT使用运行时类型信息，能够做更好的内联。有时候，JIT会做OSR汇编，会产生不相同的代码。

[What is the difference between JIT and AOT in Java?](http://stackoverflow.com/questions/9105505/differences-between-just-in-time-compilation-and-on-stack-replacement)  
大意是，JIT编译和执行本地代码，某些引擎如Google V8甚至没有解释器，JIT负责所有编译解释工作。  
OSR（栈替换），当JIT编译完本地代码后，OSR技术提供从解释运行切换到本地代码运行的特性。  
有时候，虽然一个方法执行一次，但是它处于一个大循环中，从而会消耗很多CPU时间，优化的需求是很明显的，这时，OSR还可以将需要优化的方法栈内容替换成优化后的代码，这些代码指向不同的地址。  
OSR还会在其它情况下触发，从优化的代码转换成未优化的代码或者解释执行。优化代码可能是基于设备前一个运行环境得来的，如此不一定适应所有情况下的运行环境，这时候就需要执行预编译或者优化roll back。  
总结：OSR可以进行本地执行与解释执行的动态切换，还可以执行方法栈优化替换，执行roll back处理。

## Architectural Overview

![](/images/Reverse/jit-arch.png)  
Figure 1. JIT architecture - how it works

## Flow(流程)

JIT编译工作方式： 

- 运行app，触发ART加载.dex文件
- 如果app的.oat文件(对于app，一般名称是.odex后缀)可用，则ART直接使用.oat文件。注意，.oat文件通常是会产生的，但不表示它包含AOT binary code。
- 如果.oat不存在，ART通过JIT或者一个解释器执行.dex文件。一旦.oat文件可用，ART便会使用它。否则，它会使用apk然后解压里面的.dex文件到内存，从而自然的会占用内存空间。
- JIT在这种情况下会被使能，就是当apk不是使用"speed"作为编译过滤器的时候（"speed"的意思是：尽最大可能编译app，意味着会产生.oat文件）
- JIT轮廓数据（JIT profile data，意思是决定JIT运行所需要的重要摘要信息）保存在一个系统目录里的文件内，这个目录只有当前app有权限访问。
- AOT编译器（dex2oat）根据上面提到的JIT profile文件对.dex进行编译。

![](/images/Reverse/jit-profile-comp.png)  
Figure 2. Profile-guided compilation

![](/images/Reverse/jit-daemon.png)  
Figure 3. How the daemon works


## JIT Workflow(JIT工作流程)

![](/images/Reverse/jit-workflow.png)   
Figure 4. JIT data flow

This means:

- Profiling information is stored in the code cache and subjected to garbage collection under memory pressure.  
Profiling信息是保存在code cache中的，接受GC的管理。
- As a result, there’s no guarantee the snapshot taken when the application is in the background will contain the complete data (i.e. everything that was JITed).  
前面cache接受GC管理的结果是，并不保证后台的快照包含app所有的数据（也就是说，任何东西都是即时的JITed）
- There is no attempt to make sure we record everything as that will impact runtime performance.  
我们并没有尝试记录所有信息，因为这将会降低运行性能。
- Methods can be in three different states（方法可能是以下三种不同的状态）:  
  - interpreted (dex code)
  - JIT compiled
  - AOT compiled
- If both, JIT and AOT code exists (e.g. due to repeated de-optimizations), the JITed code will be preferred.  
当JIT code 和AOT code同时存在时，JITed code是首选的。也就是说profile cache和.oat内都包含同一个method，那么，JITed的method将会被执行。
- The memory requirement to run JIT without impacting foreground app performance depends upon the app in question. Large apps will require more memory than small apps. In general, big apps stabilize around 4 MB.  
JIT对前台性能的影响取决于具体的app，越大的app，JIT会占用越多的内存，一般是4M。

## System Properties

*   `dalvik.vm.usejit  <true|false></true|false>`- Whether or not the JIT is enabled.
*   `dalvik.vm.jitinitialsize` (default 64K) - The initial capacity of the code cache. The code cache will regularly GC and increase if needed. It is possible to view the size of the code cache for your app with:
    `$ adb shell dumpsys meminfo -d <pid>`
*   `dalvik.vm.jitmaxsize` (default 64M) - The maximum capacity of the code cache.
*   `dalvik.vm.jitthreshold <integer>` (default 10000) - This is the threshold that the "hotness" counter of a method needs to pass in order for the method to be JIT compiled. The "hotness" counter is a metric internal to the runtime. It includes the number of calls, backward branches & other factors.
*   `dalvik.vm.usejitprofiles <true|false>` - Whether or not JIT profiles are enabled; this may be used even if usejit is false.
*   `dalvik.vm.jitprithreadweight <integer>` (default to `dalvik.vm.jitthreshold` / 20) - The weight of the JIT "samples" (see jitthreshold) for the application UI thread. Use to speed up compilation of methods that directly affect users experience when interacting with the app.
*   `dalvik.vm.jittransitionweight <integer>` (`dalvik.vm.jitthreshold` / 10) - The weight of the method invocation that transitions between compile code and interpreter. This helps make sure the methods involved are compiled to minimize transitions (which are expensive).

## Tuning（打开关闭JIT）

Device implementers may precompile (some of) the system apps if they want so. 
Initial JIT performance vs pre-compiled depends on the the app, but in general they are quite close. 
It might be worth noting that precompiled apps will not be profiled and as such will take more space and may miss on other optimizations.  
部分系统apps被执行AOT预编译，虽然JIT与AOT非常相近，但是，错过JIT将不会获得好处，不仅占用空间而且可能错过某些优化。

其它的不记录。

## 建议配置

```
pm.dexopt.install=interpret-only - 加快安装
pm.dexopt.bg-dexopt=speed-profile - AOT deamon 基于profile完全编译，idle或者charging是执行AOT deamon compilation。
pm.dexopt.ab-ota=speed-profile - A/B ota 基于profile执行speed模式预编译，因为有一个系统(A或者B)是在运行中的
pm.dexopt.nsys-library=speed - 这是什么？？？
pm.dexopt.shared-apk=speed - 共享apk采用speed模式预编译，比如Google play service，被其它app所使用，更像是shard-library
pm.dexopt.forced-dexopt=speed - 强制预编译时采用speed模式
pm.dexopt.core-app=speed - 系统核心app采用speed，JIT不支持对核心app的JITing
pm.dexopt.first-boot=interpret-only - 第一次启动更快
pm.dexopt.boot=verify-profile - 用于OTA后的第一次启动，校验profile，否则会对新增加的非系统app执行默认的dex2oat。
```

附上华为P9的系统配置：

```
➜  ~ adb shell getprop | grep pm.dexopt
[pm.dexopt.ab-ota]: [speed-profile]
[pm.dexopt.bg-dexopt]: [speed-profile]
[pm.dexopt.boot]: [verify-profile]
[pm.dexopt.core-app]: [speed]
[pm.dexopt.first-boot]: [interpret-only]
[pm.dexopt.forced-dexopt]: [speed]
[pm.dexopt.install]: [interpret-only]
[pm.dexopt.nsys-library]: [speed]
[pm.dexopt.shared-apk]: [speed]
```

## 总结

Android7.0开始，ART模式采用两个具有几乎相同优化功能的编译器AOT和JIT。AOT是预编译器，可以预编译.dex生成.oat文件（或者说.odex文件），也可以根据JIT生成的profile cache信息
.oat文件。prifile cache是JIT动态优化methods产生的位于内存中的方法缓存，接受GC的管理，AOT依据JIT动态优化的code执行预编译生成.oat文件，能获得比默认方式下生成的.oat文件更高的性能。

JIT的工作模式是：

- 对于系统核心app和共享app，不执行JIT过程，直接执行默认的AOT speed模式预编译
- 对于普通app，安装和系统启动时都不执行AOT，一旦app运行过，便会被JIT产生methods的profile cache，当系统进入idle或者charging时，执行基于prifile cache的AOT
- 对于OTA，利用A/B系统对B/A系统的app进行基于profile的AOT，然后保存到storage中。
- 正因为AOT基于prifile cache，如果JIT认为.oat中的method code需要优化，它会照做，从而导致一个method有两个code，一个是JITed code，一个是AOT code。默认使用JITed code

问：pm.dexopt.nsys-library=speed 是干嘛的？

问：如前文所说，一个apk的.oat文件可用就使用它，通常是有.oat文件，但是不一定包含AOT code。那么这个.oat文件里面会是什么？  
jaren> phh: https://source.android.com/devices/tech/dalvik/jit-compiler.html#flow said, an app may has an .oat file but may not contains AOT code, such it may contains what?  
phh> jaren: well, it already happens on 6.0, when you use interpret-only. I think it contains nothing but is just there as a flag to say the apk has been checked and is valid  
jaren> phh: thx, excepted explain  
phh> jaren: fwiw, we've got infos for android 8, and the oat will initially contain which methods have been verified. on android 7, it checks the full apk on installation  


