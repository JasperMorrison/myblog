---
layout: post
title: Android图形栈-使用Skia Debugger分析图层合成
categories: Android
tags: Android Skia Composition
author: Jasper
---

* content
{:toc}

本文使用Skia Debugger来分析图层合成的方法，可以评估App或者系统的图层参数设置是否正确，是否存在多余的图层。特别是在座舱、屏幕比较多、自定义UI和图层比较多的场景下，用途是非常大的。（它也是可以用于分析App绘制的Skia过程哦。）




# 1. 背景

在座舱系统中，往往存在多个屏幕，而且自定义图层也是非常多，往往需要显示导航、音乐、视频、导航栏等，而且座舱系统的桌面效果效果普遍比较炫酷，往往还附带动态壁纸，追求立体感会附带大量的模糊。大量的图层给系统合成任务造成了很大负担，调试和优化合成任务是非常有必要的。

# 2. Skia Debugger

可以通过[https://debugger.skia.org](https://debugger.skia.org)来访问工具，上传mskp文件，即可分析合成过程。如果是单帧，则是.skp文件。

![](/images/Android/framework/Android-Skia-debugger.png)

主要内容有：

1. 回放
2. 合成的详细过程及其命令展示
3. 图层的参数

# 3. 抓取mskp文件

```
adb root
adb remount
frameworks/native/libs/renderengine/skia/debug/record.sh rootandsetup
frameworks/native/libs/renderengine/skia/debug/record.sh 2000 # 录制2000毫秒
adb pull /data/user/re_skiacapture_*.mskp
```

在Skia Debugger Tool打开re_skiacapture_*.mskp文件即可。

# 4. 分析方法

点击页面左侧的command列表，可以在右侧看到当前command的结果，同时，可以查看Skia接收到的Layer，以及layer的具体参数。

打开command某一项，可以查看到Skia SKSL。

结合屏幕实际的截图，再分析此合成过程是否有一些多余的动作或者图层。

本人就发现过这样的一个Bug：被覆盖的底层图层意外参与了合成。

1. 有两个叠加的图层，两个图层都开启了模糊，性能消耗比较大；
2. 上层覆盖了底层，底层并没有显示出来，用户是无感的，但却参与了合成；
3. 分析两个图层的参数发现，底层的圆角要比上层的圆角小；

结果：SurfaceFlinger在合成前，分析Layer发现，底层Layer有可见的区域，于是判定为需要合成。

由于底层也开启了模糊，面积也不小，增加了5%~10%的合成负载。

# 10. 参考

[Skia](https://cs.android.com/android/platform/superproject/main/+/main:external/skia)  
[Skia Debugger](https://skia.org/docs/dev/tools/debugger/)  
