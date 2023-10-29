---
layout: post
title: Android Jank Detection by FrameTimeline
categories: Android
tags: Android SurfaceFlinger Jank
author: Jasper
---

* content
{:toc}

本文搞懂Android卡顿检测之FrameTimeline，对很多概念进行了介绍，看懂trace图，从而可以熟悉Jank检测方法及Jank类别，进一步评估FrameTimeline的准确性及卡顿检测的局限性。（本文基于Android 13，针对硬件绘制模式）



# Trace图

本文针对硬件绘制，软件绘制、SurfaceView的App侧没有VSyncId，绘制完直接提交给SurfaceFlinger合成，FrameTimeline目前对它们还是无能为力的，官方未来会支持。

从Trace图上找到FrameTimeline相关踪迹，App侧和Sf侧，同时包含两个时间，Expected Time和Actual Time。

我从自用的OPPO系手机上抓了一份滑动美团的trace，并使用perfetto-ui打开。

App端的Expected Time和Actual Time概览：
![](/images/Android/framework/FrameTimeline-app.png)

Sf端的Expected Time和Actual Time概览：
![](/images/Android/framework/FrameTimeline-sf.png)

同时可以发现，App-18961627 与 sf-18961630 产生了一个关联，这是因为，sf-18961630 是一个DisplayFrame，它包含了App-18961627 这个SurfaceFrame。表示 App-18961627 这个Surface在 VSync=sf-18961630 时被推到屏幕显示，推到屏幕显示出来这件事也叫presented。

# FrameTimeline Item

先明确一个Timeline的表示：

```c++
struct TimelineItem {
    TimelineItem(const nsecs_t startTime = 0, const nsecs_t endTime = 0,
                 const nsecs_t presentTime = 0)
          : startTime(startTime), endTime(endTime), presentTime(presentTime) {}

    nsecs_t startTime;
    nsecs_t endTime;
    nsecs_t presentTime;

    bool operator==(const TimelineItem& other) const {
        return startTime == other.startTime && endTime == other.endTime &&
                presentTime == other.presentTime;
    }

     bool operator!=(const TimelineItem& other) const { return !(*this == other); }
};
```

startTime ：表示绘制/合成的开始时间点，对于App侧，表示doFrame的开始，对于sf侧，表示setTransactionState被调用，即sf被唤醒的时间；  
endTime ：表示绘制/合成的完成时间点，对于App侧，表示GPU完成了渲染，即acquireFence的signalTime，对于sf侧，表示commit完成的时间；  
presentTime ：表示显示的时间点，表示一帧被显示在屏幕上的时间，即presentFence的signalTime，这个就不区分App侧和sf侧了，毕竟Surface也是需要由sf合成并显示的。

# VSync

VSync，都知道是屏幕的垂直同步信号。我们思考更深一点，VSync到来，意味着一帧图像将显示在屏幕上。这种与刷新直接相关的VSync，其实是硬件VSync(HW VSync)。

我们还知道，Android sf有一个模拟的软件VSync，它来自于对硬件VSync的预测，使用6个硬件VSync的采样点，就能推算出斜率和截距。当给定一个时间点time point的时候，可以估算出该时间之后最近的VSync，该VSync落在斜率和截距所代表的直线上，并将其作为软件VSync，在绝对时间上，它几乎等于对应硬件VSync。

所以，VSync有两个实际含义：  
1. 屏幕显示一帧图像；（HW VSync）
2. 软件VSync驱动app去绘制，驱动sf去合成。

但软件VSync不是立即驱动app和sf工作，而是存在相位差，在app侧和sf侧分别偏移app phase和SF phase的时间，这两个phase可以通过dumpsys SurfaceFlinger直接看到。

该帧预期显示的VSync时间：在FrameTimeline中，我们需要找到一帧未来可能在哪个VSync上显示到屏幕上。在拥有三缓冲的Android显示系统中，一帧很可能在3个VSync周期后显示到屏幕上。  
1. 第1个VSync：CPU执行doFrame
2. 第2个VSync：GPU执行渲染
3. 第3个VSync：sf合成并送显
4. 第4个VSync触发：正好可以在屏幕上显示

所以，该帧预期显示的VSync时间 = now + 3个VSync的周期。

对于120pfs/8ms一帧的刷新率，该帧预期显示的VSync时间 = now + 8x3 = now + 24ms。

对于60pfs/16.7ms一帧的刷新率，该帧预期显示的VSync时间 = now + 16.7x3 = now + 50ms。

Android模拟的软件VSync，其实就是这个“该帧预期显示的VSync时间”，也就是距今近似等于24ms和50ms之后的时间点。

（这一点非常重要，十几年的Android老牛也未必知道这个）Trace图上显示的，或者说驱动app绘制和sf合成的VSync-app/VSync-sf，其实是软件VSync的调整时间，也就是SurfaceFlinger代码中提到的wakeupTime。

# Fence

Fence是同步用的，用于保护某些绘制/合成过程，分为：

1. acquireFence：当对Surface queueBuffer到BufferQueue中后，只有signal后才能被消费端acquire，此时表示GPU已经完成渲染；
2. releaseFence：dequeueBuffer后，singal触发，表示合成工作已经完成，可以被App拿去绘制了；
3. presentFence：commit到Display后，signal触发，表示该帧已经被显示到屏幕上，表示一个Buffer最终显示出来了。

# work duration & ready duration

FrameTimeline的时间是否满足预期，duration是一个基础，它来源于offset。

对于App侧，完成一帧的绘制需要work duration这么久，将绘制好的一帧的显示出来需要 ready duration这么久。work duration也代表了App绘制一帧的时长，是从doFrame开始到GPU完成绘制的时长（使用硬件加速的情况下）。ready duration表示sf将这一帧合成并显示到屏幕上的时长，是从sf被唤醒到presentFence signalTime的时长。

对于sf侧，就不存在绘制的时长了，主要是合成时长，直接使用work duration表示。表示sf将所有帧合成并显示到屏幕上的时长，是从sf被唤醒到presentFence signalTime的时长。sf侧的ready duration始终等于0。

在 `adb shell dumpsys SurfaceFlinger`命令显示的dump信息中:

```shell
60.00fps: 3d01:39:51.482

           app phase:      2400001 ns	         SF phase:    -10933333 ns
           app duration:  20000000 ns	         SF duration:  27600000 ns
     early app phase:      2400001 ns	   early SF phase:    -10933333 ns
     early app duration:  20000000 ns	   early SF duration:  27600000 ns
  GL early app phase:      2400001 ns	GL early SF phase:    -10933333 ns
  GL early app duration:  20000000 ns	GL early SF duration:  27600000 ns
       HWC min duration:  17000000 ns
      present offset:         0 ns	     VSYNC period:  16666667 ns
```

app侧的work duration == app duration。  
app侧的ready duration == sf duration == sf侧的work duration。

sf中，根据offset计算duration：

```c++
namespace {
std::chrono::nanoseconds sfOffsetToDuration(nsecs_t sfOffset, nsecs_t vsyncDuration) {
    return std::chrono::nanoseconds(vsyncDuration - sfOffset);
}

std::chrono::nanoseconds appOffsetToDuration(nsecs_t appOffset, nsecs_t sfOffset,
                                             nsecs_t vsyncDuration) {
    auto duration = vsyncDuration + (sfOffset - appOffset);
    if (duration < vsyncDuration) {
        duration += vsyncDuration;
    }

    return std::chrono::nanoseconds(duration);
}
} // namespace
```

盗了一张图，大意是对的，但在Android13上，还不完全对：
1. offset不是与HW_VSYNC的相对时间，而是与软件VSYNC的相对时间；
2. sf offset是一个负数，在VSYNC的前面，表示比VSYNC早。
   
![](/images/Android/framework/FrameTimeline-offset2duration.jpg)

再看上面的代码，sf duration 是 `vsyncDuration - sfOffset`，这个值比VSYNC周期大。

同理，app duration = `vsyncDuration - appOffset`，但还不行，因为sf偏移了，app侧偏要移少一点，才能让一帧图像正好在VSYNC到来前完成绘制，这样效率是最高的。

所以，app duration 变为 `vsyncDuration - appOffset + sfOffset = vsyncDuration + (sfOffset - appOffset)`。如果小于一个vsyncDuration，多加一个，这样才能满足3个VSYNC完成绘制的三缓冲机制，才是最佳的绘制效率。

# FrameTimeline-App侧

重点来了，App侧的Expected Time和Actual Time是怎么来的？

首先，它们是 FrameTimeline Item 开始时间和完成时间的组合，Actual Time 表示实际时间，Expected Time表示预测的时间。

对于上图中的token=18961627来说，Actual Timeline = 10.2ms，Expected Timeline = 20ms。

## Actual Timeline

![](/images/Android/framework/FrameTimeline-trace-SurfaceFrame-actual.png)

startTime等于doFrame开始的时间，下面是整个调用过程：  

```java
    Choreographer.java
        doFrame() --> do the registered Callback
    ViewRootImpl.java
        performDraw() --> draw()
            mAttachInfo.mThreadedRenderer.draw(mView, mAttachInfo, this);
```

```c++
    CanvasContext::draw() of RenderThread in libhwui.so
        native_window_set_frame_timeline_info()
            Surface::dispatchSetFrameTimelineInfo()
                BLASTBufferQueue.cpp --> BBQSurface --> setFrameTimelineInfo
    BLASTBufferQueue::acquireNextBufferLocked()
        t->setFrameTimelineInfo(mNextFrameTimelineInfoQueue.front()); // 设置到Transaction中
        t->setApplyToken(mApplyToken).apply(false, true); //设置到SurfaceFlinger
```

```c++
    SurfaceComposerClient.cpp --> SurfaceComposerClient::Transaction::apply()
        set mFrameTimelineInfo to sf
    SurfaceFlinger::commit()
        setTransactionState()
            // set the start time to SurfaceFrame in FrameTimeline
            void SurfaceFrame::setActualStartTime(nsecs_t actualStartTime) {
                std::scoped_lock lock(mMutex);
                mActuals.startTime = actualStartTime;
            }
```

endTime 是acquireFence 的SignalTime，表示GPU已经完成渲染。

```c++
Layer.cpp
1258 surfaceFrame->setAcquireFenceTime(acquireFenceTime); in addSurfaceFramePresentedForBuffer() // HWUI
1273 surfaceFrame->setAcquireFenceTime(postTime); in createSurfaceFrameForTransaction() // 软件绘制
```

## Expected Timeline

![](/images/Android/framework/FrameTimeline-trace-SurfaceFrame-prediction.png)

> 关于“该帧预期显示的VSync时间”，请翻前文

endTime = 该帧预期显示的VSync时间 - ready duration.  
startTime = 该帧预期显示的VSync时间 - work duration - ready duration.  

预测时间生成：  

![](/images/Android/framework/FrameTimeline-SurfaceFrame-prediction.png)

预测时间分发：

![](/images/Android/framework/FrameTimeline-SurfaceFrame-prediction-dispatch.png)

# FrameTimeline-SF侧

对于上图中的token=18961630来说，Actual Timeline = 27.3ms，Expected Timeline = 27.6ms。

## Actual Timeline

![](/images/Android/framework/FrameTimeline-trace-DisplayFrame-actual.png)

startTime = commit()，FrameTimeline::DisplayFrame::onSfWakeUp，表示sf被客户端唤醒的时间，及开始合成的时间；  
presentTime = presentFence 的signal时间；

## Expected Timeline

![](/images/Android/framework/FrameTimeline-trace-DisplayFrame-prediction.png)

跟踪代码：  

```java
831  void FrameTimeline::setSfWakeUp(int64_t token, nsecs_t wakeUpTime, Fps refreshRate) {
832      ATRACE_CALL();
833      std::scoped_lock lock(mMutex);
834      mCurrentDisplayFrame->onSfWakeUp(token, refreshRate,
835                                       mTokenManager.getPredictionsForToken(token), wakeUpTime);
836  }
```

![](/images/Android/framework/FrameTimeline-DisplayFrame-prediction.png)

{targetWakeupTime, readyTime, vsyncTime} 对应 {startTime, endTime, presentTime}

参考App侧的预测时间生成方式，由于sf侧readyDuration==0，所以：  
1. startTime = vsyncTime - workDuration
2. endTime = vsyncTime

# TimerDispatch

补充一下，这个对理解VSYNC-App/sf的生成会有很大的帮助：  

VSync-app发生时设置一个VSync-sf的alarm：

![](/images/Android/framework/FrameTimeline-TimerDisplatch-sf.png)

同理，VSync-sf发生时设置一个VSync-app的alarm：

![](/images/Android/framework/FrameTimeline-TimerDisplatch-app.png)

# 参考

[http://www.aospxref.com/android-13.0.0_r3/xref/frameworks/native/services/surfaceflinger/](http://www.aospxref.com/android-13.0.0_r3/xref/frameworks/native/services/surfaceflinger/)
