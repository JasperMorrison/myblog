---
layout: post
title: Android图形栈-合成概述
categories: Android
tags: Android Composition
author: Jasper
---

* content
{:toc}

本文从大的视图给出一个Android图层合成的技术描述，从App端开始，直到在屏幕上显示。本文侧重于SurfaceFlinger端，包括了HWC合成与GPU合成，大致涵盖了各个模块的作用和关联。由于是技术栈的概述性文章，目的是一览技术栈，明白Android图形是怎么显示的，会省略很多基础性的内容，以及详细的描述。




# 1. 框图

![](/images/Android/framework/SurfaceFlinger-graphic-stack-composition.png)

# 2. Surface

Surface会包含一个BufferQueue，用来存放多个Buffer，每次更新内容，相当于是刷新GraphicBuffer的存储空间，Surface需要将这个GraphicBuffer送显。

在创建Surface，会创建一个Layer与之对应，具体的流程大致是:  
    1. SurfaceControl::getSurface()  
    2. SurfaceControl::generateSurfaceLocked()  
    3. SurfaceComposerClient::createSurface()  
    4. Client::createSurface()  
    5. SurfaceFlnger::createLayer()  

# 3. Layer

Layer是图层的意思，很多地方都有用的，有下面这些相关的概念，它们之间有着密切联系。

1. LayerFE ：FE代表FrontEnd，也就是前端，在CompositionEngine会直接使用。  
2. Layer ：继承LayerFE，在SurfaceFlinger的commit过程中，会处理来自App端的合成请求，填充DrawState。  
3. OutputLayer : Output是对应于CompositionEngine的输出，也就是最终的显示结果。OutputLayer表示最终结果使用的一个图层，一个Layer对应一个OutputLayer。  
4. HWC2::Layer : 是DisplayHardware的Layer，在HWC2中，一个Display对应多个Layer。这里的Layer表示HWC的一个图层，这个图层就不一定对应App侧的Layer了。也可能是合成之后的Layer  
5. HWCLayer :  对应一个HWC2::Layer，用于在Composer中管理图层。  
6. Plane：Plane是HWC中的一个概念，表示一个硬件层面的图像缓冲区。在HWC中，每个Layer都会对应一个或多个Plane。Plane与Framebuffer完成了图层缓存区及描述信息的表述。  

# 4. VSYNC

VSYNC-sf用于驱动SurfaceFlinger合成，VSYNC-app用于驱动App渲染，它们都有一个很大的特征：**按需产生**。

SWVSYNC是VSYNC的一种表述，表示软件VSYNC，它一般由HWVSYNC经过最小二乘法模拟出来的直线而来。SWVSYNC如果得不到HWVSYNC的校准，会使用一个简单模型，这个简单模型存在**零点偏移问题**。我也修复过这个问题，所以对VSYNC有比一般人更深刻的认识。

总的来说，SurfaceFlinger的合成工作起源自VSYNC-sf信号。

# 5. SurfaceFlinger

SurfaceFlinger除了主业务逻辑，还有CompositionEngine和DisplayHardware模块，同时调用RenderEngine来调用GPU来完成HWC无法合成的Layer。

主要包含两个业务过程：
1. commit
2. composite

commit：处理应用侧的送显请求，将Layer的状态存储起来；  
composite：利用CompositionEngine和DisplayHardware来完成最终的合成。  

# 6. CompositionEngine

CompositionEngine是SurfaceFlinger的核心，它负责将多个Layer合成到一个或者多个屏幕上，管理着Display和Output对象。

对于CompositionEngine来说，一个Display就是一个合成的Output，所以Display继承了Output。

它利用两个工具，1. GPU 2. HWC，GPU用于Client合成，HWC用于Device合成。

在CompositionEngine中，存在这样一些概念。

1. Output ： 合成的输出，也就是最终的显示结果的一个表示对象。  
2. Display ： 一个Display对应一个Output，也是最终的显示结果。  
3. LayerFE ： 前端Layer，也就是应用侧的Layer，前面有提到Layer继承了LayerFE，说的就是这里的LayerFE。CompositionEngine就是BackEnd。  
4. OutputLayer : 是对LayerFE、HWCLayer、Ouput的二次封装，代表了如何将LayerFE合成到Output上。  
5. RenderSurface ：用户GPU合成的Surface，之所以使用Surface，是为了更好的使用GraphicBuffer，是Buffer生产端。CompositionEngine会将LayerFE合成到RenderSurface上。    
6. DisplaySurface ： Buffer的消费端，RenderSurface最终是要显示的，DisplaySurface就是用来显示的。它的实现类是DisplayHardware模块中的FramebufferSurface。  


比如OutputLayer有以下接口：  
```c++
    // Sets the HWC2::Layer associated with this layer
    virtual void setHwcLayer(std::shared_ptr<HWC2::Layer>) = 0;

    // Gets the output which owns this output layer
    virtual const Output& getOutput() const = 0;

    // Gets the front-end layer interface this output layer represents
    virtual LayerFE& getLayerFE() const = 0;

    // Allows mutable access to the raw composition state data for the layer.
    // This is meant to be used by the various functions that are part of the
    // composition process.
    // TODO(lpique): Make this protected once it is only internally called.
    virtual CompositionState& editState() = 0;
```

# 7. RenderEngine

RenderEngine是一个专供SurfaceFlinger使用的lib，负责使用GPU合成Layer到RenderSurface上。之所以独立出来，我想，是为了解耦Skia-Vulkan/OpenGL-GPU那套东西。

Skia使用Skia-API和SKSL来完成对Vulkan和OpenGL的调用，封装了图形库的上下文操作。Skia的核心也包含ganesh和graphite，graphite是最新的实现。

希望有一天可以详细地展开RenderEngine和Skia。

# 8. DisplayHardware

DisplayHardware是一个抽象类，它提供了与硬件相关的接口，是对HWComposer的封装。最新采用AIDL的方法与Composer进程通信，通过HWCLayer关联图层。

## 8.1. FramebufferSurface

FramebufferSurface，通过 mHwc.setClientTarget() 接口将RenderSurface的合成结果推送给HWC中的FRAMEBUFFER_TARGET类型的HWCLayer。

FRAMEBUFFER_TARGET类型的buffer也简称为 “FB target buffer”。

## 8.2. VirtualDisplaySurface

VirtualDisplaySurface，是针对虚拟屏的。它首先是DisplaySurface，可以像FramebufferSurface操作HWC。

为此，它引入了一个新的概念，sink。

sink就是VirtualDisplaySurface的消费者，它代表了任意一个VirtualDisplaySurface最终该显示的内容（buffer）的消费者，比如一个创建虚拟屏幕的App，暂且不管这些消费者如何使用这个buffer。

看看sink的定义：

```c++
const sp<IGraphicBufferProducer>& sink;
```

**sink既然是一个消费者，为何定义为IGraphicBufferProducer？**

因为sink的消费者是一个独立的进程，VirtualDisplaySurface提供IGraphicBufferProducer，sink进程抓住IGraphicBufferConsumer，这样，buffer不就传递过去了嘛。

VirtualDisplaySurface的行为分为三种情况：  
1. 纯GPU合成 ： 直接将GPU合成结果推送给HWC的FRAMEBUFFER_TARGET类型的Layer，直到合成流程完成，才将Buffer queue到sink端。  
2. 纯HWC合成 ： 从sink dequeue 一个Buffer，同时设置为 HWC 的 FB target buffer 和 output buffer。此时HWC不会读取FB target buffer，而是直接将合成写入output buffer。  
3. MIX合成 ： 内部使用一个独立的BufferQueue供GPU合成使用，GPU合成完成后，将合成结果设置为FB target buffer。并将sink相关的buffer设置为output buffer。合成完成后，output buffer，就是sink消费者需要的最终显示结果。  

## 8.3. HWC合成

操作DRM，完成最终的合成工作，关键的知识在于Framebuffer和Plane。可以简单的理解为，Framebuffer代表GraphicBuffer，Plane代表Layer，Layer控制了HWC如何使用Framebuffer，并合成为最终的output buffer。

我们应该关心HWC合成需要具备什么条件，如果不想关心，我们可以直接将所有Layer的CompositionType设置为DEVICE类型，供HWC自己决策。

据我目前了解，以下几种情况，会被判定为GPU合成：  
1. 圆角  
2. 背景模糊-Blur  
3. 设置开发者选项设定为GPU合成  

## 8.4 HwcAsyncWorker

这是一个异步线程，专供与HWC交互用的。目前，它被用在合成方式的预测上。相当于，异步获取图层的CompositionType，下次合成任务执行时，无需阻塞等待CompositionType查询结果
的返回，从而加速SurfaceFlinger的合成过程。

# 9. 总结

借助本文对合成框架的总结，和关键概念的分享，深入Android合成图形栈是完全没有问题的，不足之处还请海涵和指正，同时，祝愿看到此文的有缘人，前程似锦！

# 10. 参考

[SurfaceFlinger](https://cs.android.com/android/platform/superproject/main/+/main:frameworks/native/services/surfaceflinger)

[Skia](https://cs.android.com/android/platform/superproject/main/+/main:external/skia)

[RenderEngine](https://cs.android.com/android/platform/superproject/main/+/main:frameworks/native/libs/renderengine/)