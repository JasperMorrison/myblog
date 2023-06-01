---
layout: post
title: Android simpleperf
categories: 性能分析 
tags: Android simpleperf perf
author: Jasper
---

* content
{:toc}

本文介绍一下simpleperf的作用以及用法，这是一个在Android上的完整使用向导。网上有很多simpleperf的文章，有的是simpleperf README的片面翻译，有的是个人理解和实践，感觉都不足以支撑对其理解和使用。



# 1. perf介绍

perf是linux是一个性能分析工具，通过系统event的记录和分析，可以获得性能全面的性能状况。

![](/images/Android/perf/perf.png)

1. probes：通过k/uprobes动态记录event，开发者可进行自定义；
2. tracepoints：获得系统中预先埋设的tracepoints；
3. software event：软件级别的event，如调度信息、缺页异常，很明显，这里的软件是指操作系统中相对硬件而言的软件；
4. PMCs：即PMU提供的信息，linux将PMU的硬件信息记录起来；

使用perf的一般流程是：
1. record：获得记录信息，默认得到perf.data；
2. report：对信息进行分析统计，形成图表；

# 2. simpleperf介绍

simpleperf是Android平台上的本地进程的profile工具，可以同时profile java代码和c++代码，这个工具同时提供了simpleperf二进制可执行程序，以及配套的python脚本。

对perf的对比：

1. simpleperf还采集符号信息、设备信息和record时间；
2. --trace-offcpu 选择同时采集on-cpu和off-cpu两种信息；
3. 可以通过属性来开启profile任务，比如对开机过程进行profile，已获得开机的性能信息，分析开机流程；
4. 可以在应用的上下文中运行profile，而不需root权限；
5. 支持读取符号和调试信息；
6. 与其它Android工具兼容；
7. 独立的simpleperf程序，不依赖运行库，可以推到任何Android设备中执行；
8. 同时支持Linux、Mac、Windows平台，在Windows上一般是用作report工具使用；
9. 提供了完善的python script；

# 3. app profile

特指：Android application profiling

1. 对于debug build App：无需任何修改，可以只是使用simpleperf。
2. 对于release build App：则需要具备以下条件之一：
   1. 拥有设备的root权限；
   2. 在AndroidManifest.xml中添加`<profileable android:shell="true" />`;
3. profile c/c++ code：app_profiler.py中添加选项 `-lib`；
4. profile java code：Android P以上默认支持；

具体用法，可以参考下方的script说明，支持对app的启动过程进行profile。

支持在应用代码中控制 profile，包括 `start/pause/resume/stop`.

更多内容参考：[android application profiling](http://www.aospxref.com/android-13.0.0_r3/xref/system/extras/simpleperf/doc/android_application_profiling.md)

# 4. platform profile

特指：android platform profile

在支持root的android设备，可以通过simpleperf来profile任意的app和native进程。

同样使用app_profile.py就可以完成数据收集：

`./app_profiler.py -np surfaceflinger -r "-g --duration 10"`

## 4.1. 从 system_server启动simpleperf的做法

1. `adb shell setenforce 0`;
2. 在需要触发的地方添加下面的代码：

```java
try {
  // for capability check
  Os.prctl(OsConstants.PR_CAP_AMBIENT, OsConstants.PR_CAP_AMBIENT_RAISE,
           OsConstants.CAP_SYS_PTRACE, 0, 0);
  // Write to /data instead of /data/local/tmp. Because /data can be written by system user.
  Runtime.getRuntime().exec("/system/bin/simpleperf record -g -p " + String.valueOf(Process.myPid())
            + " -o /data/perf.data --duration 30 --log-to-android-buffer --log verbose");
} catch (Exception e) {
  Slog.e(TAG, "error while running simpleperf");
  e.printStackTrace();
}
```

## 4.2. 获取设备启动过程中的profile

要求是 userdebug/eng 版本。

`# simpleperf boot-record --enable "-a -g --duration 10 --exclude-perf"`

上述命令会设置属性 `persist.simpleperf.boot_record`。

重启设备后，数据保存在`/data/simpleperf_boot_data`目录下。

![](/images/Android/perf/boot_time_profile.png)

# 5. script reference

[script reference](http://www.aospxref.com/android-13.0.0_r3/xref/system/extras/simpleperf/doc/scripts_reference.md)

## 5.1. record

主要使用`app_profiler.py`进行record。

app record:`$ ./app_profiler.py -p simpleperf.example.cpp -a .SleepActivity`  
使用 -p 参数指定应用会先kill再启动应用

-a：指定activity  
-np ： native process  
--pid：指定进程，不会重启应用  
-cmd：指定命令，并对其进程进行record  
-r：send option to simpleperf cmd  
--app：获得应用启动profile  

api_profiler.py：用于在应用代码中控制profile过程

run_simpleperf_without_usb_connection.py：在断开usb之后也能执行profile任务，适用于不应当连接usb来进行调试的场景

binary_cache_builder.py：用于指定二进制库，这些库应当包含符号信息。app_profile.py会自动拉取二进制库，但是在断开usb和调试系统进程的场景，这个脚本就能派上用场。

run_simpleperf_on_device.py：是自动调用simpleperf的自动化脚本，省去了人工操作。

## 5.2. report

report.py：在host端调用`simpleperf report`的脚本。

report_html.py：自动生成html报告的脚本，是`view the profile`的一种方式。

inferno：生成html版本的flamegraph的工具。

更多的可视化工具，见下方的`view the profile`.

# 6. view the profile

1. Continuous PProf UI
2. Firefox Profiler
3. FlameScope
4. Differential FlameGraph
5. Android Studio Profiler（推荐）
6. Simpleperf HTML Report
7. Simpleperf Report Command Line
8. Custom Report Interface（使用API自定义）

最推崇使用Android Studio Profiler，类似trace的形式，展示每个函数的调用栈和调用时长，跟我们分析perfetto trace一样。

将perf.data转换为Android Studio Profiler所支持的trace文件：  
```
simpleperf report-sample --show-callchain --protobuf -i perf.data -o perf.trace
或者：
simpleperf report-sample --show-callchain --protobuf -i perf.data -o perf.trace --proguard-mapping-file proguard.map
```

打开trace文件：Android Studio -> Open File -> Open -> Select perf.trace

![](/images/Android/perf/android_studio_profiler_open_perf_trace.png)


# 7. 参考

[simpleperf](http://www.aospxref.com/android-13.0.0_r3/xref/system/extras/simpleperf/doc/)  
[perf和火焰图使用方法](https://cloud.tencent.com/developer/beta/article/2245316)  
