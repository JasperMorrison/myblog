---
layout: post
title: Android native app 框架
categories: Android
tags: Android native app
author: Jasper
---

* content
{:toc}

Android native app 的工作方式，主要包括Activity创建、Java与Native的关系等，Android native app的核心思想是通过JNI来管理Native对象，上下联动管理Activity生命周期事件并传递用户输入事件等。




![](/images/android/sdk/android_native_app_bigpiture.png)

# 1. 框架介绍

## 1.1 项目结构

![](/images/android/sdk/android_native_app_files.png)

```c++
cc_library_shared {
    name: "libgamecore_sample",
    srcs: [
        "src/**/*.cpp", # 源文件
    ],
    static_libs: ["android_native_app_glue"], # 依赖库，这个库帮做了很多事情
    ldflags: [
        "-uANativeActivity_onCreate", # 入口函数
    ],
}

android_app {
    name: "GameCoreSampleApp", # 应用名称
    jni_libs: [
        "libgamecore_sample", # 把上面的库打包到apk中
    ],
}
```

android_native_app_glue 静态库是NDK自动编译的，就像是一个粘合剂，将Java层的Activity与Native的android_app粘合起来。  
直接使用android_native_app_glue.cpp和android_native_app_glue.h文件来进行编译也是可以的。

同时，需要当前目录存放一个AndroidManifest.xml文件，核心内容如下：

```java
<activity android:name="android.app.NativeActivity"></activity>
    <!-- Tell NativeActivity the name of our .so -->
    <meta-data android:name="android.app.lib_name"
        android:value="gamecore_sample" />
```

1. 必须指定Activity为NativeActivity，否则无法创建
2. 加载前面定义的库

## 1.2 NativeActivity

NativeActivity继承自Activity，在onCreate()中调用了loadNativeCode方法，这个方法主要是创建一个NativeCode对象出来，并填充其createFunc和callbacks属性，并最终会调用到native_app_glue.cpp中的android_main()函数。

createFunc主要是为了创建android_app对象，callbacks是事件的回调。

NativeCode 继承自 ANativeActivity。  
callbacks 是 ANativeActivityCallbacks 结构体。

Java层的NativeActivity直接对应C++层的android_app，NativeCode负责管理Java与C++层的这种接口函数。由此可以，一个Native App其实只有一个Activity，只有一个android_app对象。

## 1.3 ANativeActivity

正如 native_activity.h 文件的定义，

```c++
typedef struct ANativeActivityCallbacks {
  void (*onStart)(ANativeActivity* activity);
  void (*onResume)(ANativeActivity* activity);
  void (*onPause)(ANativeActivity* activity);
  // ......
}
```

loadNativeCode() 将ANactivity的引用赋值给 mNativeHandle，上下联动也非常自然：

```c++
static void
onStart_native(JNIEnv* env, jobject clazz, jlong handle)
{
    if (kLogTrace) {
        ALOGD("onStart_native");
    }
    if (handle != 0) {
        NativeCode* code = (NativeCode*)handle;
        if (code->callbacks.onStart != NULL) {
            code->callbacks.onStart(code);
        }
    }
}
```

找到 NativeCode 对象，并传递生命周期事件。

# 2. 渲染

native app 的目的是进行native 渲染，得利用本地API完成Surface、EGL、OpenGL ES等渲染。

渲染需要两个东西：render、shader。

render：管理本地窗口、上下文和Surface，类比 RenderThread。  
shader：OpenGL shader，创建工程，加载OpenGL Shader等等。

render在完成渲染工作后，通过swapbuffer将Surface提交给SurfaceFlinger，完成渲染。

# 3. 参考

[sample_app](http://www.aospxref.com/android-14.0.0_r2/xref/tools/test/graphicsbenchmark/apps/sample_app/src/cpp/)  
[android_app_NativeActivity.cpp](http://www.aospxref.com/android-14.0.0_r2/xref/frameworks/base/core/jni/android_app_NativeActivity.cpp)  
[NativeActivity.java](http://www.aospxref.com/android-14.0.0_r2/xref/frameworks/base/core/java/android/app/NativeActivity.java)  
[native_activity.h](http://www.aospxref.com/android-14.0.0_r2/xref/frameworks/native/include/android/native_activity.h)
