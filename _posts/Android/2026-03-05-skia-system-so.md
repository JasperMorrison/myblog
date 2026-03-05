---
layout: post
title: "Android 开发：引用系统 libskia.so 进行硬件渲染"
categories: "Android"
tags: Android Skia libhwui OpenGL HardwareRendering AOSP
author: Jasper
---

* content
{:toc}

## 1. 背景与动机

有没有想过直接构建一个使用系统 Skia 进行 GPU 渲染的 APK 来快速验证项目？

在做轻量级硬件渲染引擎的 POC 时，我们希望使用 Skia 的 API 来完成渲染工作。AOSP 中自带了 Skia 源码，通常以静态库形式存在。我们可以直接从 AOSP 编译出 libskia.so，跳过单独编译 Skia 仓库的繁琐过程，快速验证项目可行性。


## 2. POC 原理概述

在深入具体步骤之前，先理解整个方案的原理：

```
┌─────────────────────────────────────────────────────────────────┐
│                        应用进程                                  │
├─────────────────────────────────────────────────────────────────┤
│  Java/Kotlin 代码                                               │
│       ↓                                                         │
│  JNI 调用原生渲染引擎                                            │
│       ↓                                                         │
│  libskia.so (我们引用的系统库)                                   │
│       ↓  GPU 渲染命令                                           │
│  libGLESv2.so ←→ libEGL.so                                     │
│       ↓              ↓                                          │
│  GPU 驱动        与 SurfaceFlinger 通信                          │
│                         ↓                                       │
│                  SurfaceFlinger 合成                            │
│                         ↓                                       │
│                  屏幕显示 (CRTC)                                 │
└─────────────────────────────────────────────────────────────────┘
```

核心原理：
1. **libskia.so** 提供 Skia 图形 API，负责生成 GPU 渲染指令
2. **libEGL.so** 负责 EGL 上下文管理和与 SurfaceFlinger 的 Buffer 交互
3. **libGLESv2.so** 是 GPU 驱动接口，执行实际渲染命令
4. **swapbuffers** 时，libEGL.so 会将渲染好的 Buffer 提交给 SurfaceFlinger

## 3. 方案步骤

整体方案分为五个步骤：

1. 在 AOSP 中添加编译项，编译出 libskia.so
2. 在工程中引用 so，并拷贝 AOSP Skia 头文件
3. 设置允许三方应用链接系统 lib
4. 给 Skia 绑定 OpenGL 上下文
5. 编写渲染示例

## 4. 第一步：在 AOSP 中编译 libskia.so

默认情况下，AOSP 编译的是 libskia.a（静态库）。我们需要修改编译配置，生成动态库。

### 编译命令

```bash
source build/envsetup.sh
lunch <target>
make libskia -j8
```

编译完成后，在 `out/target/product/<device>/system/lib/` 目录下找到 `libskia.so`。

### 注意事项

- 确保选择正确的 Android 版本分支，不同版本的 Skia API 可能有差异
- 编译出的 so 需要与目标设备的 ABI 匹配（armeabi-v7a, arm64-v8a, x86, x86_64）

## 5. 第二步：集成到工程

### 拷贝头文件

从 AOSP 源码中拷贝 Skia 头文件到工程：

```
your_project/
├── jni/
│   ├── libskia.so
│   └── include/
│       ├── core/
│       ├── gpu/
│       ├── config/
│       └── ...
└── app/src/main/cpp/
```

关键头文件目录：
- `include/core/` - 核心 API
- `include/gpu/` - GPU 渲染 API
- `include/config/` - 平台配置

### 配置 CMake

在 CMakeLists.txt 中：

```cmake
add_library(skia SHARED IMPORTED)
set_target_properties(skia PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/jni/libskia.so
)

include_directories(${CMAKE_SOURCE_DIR}/jni/include)
target_link_libraries(your_native_lib skia libGLESv2 libEGL)
```

## 6. 第三步：允许三方应用链接系统 lib

默认情况下，非系统应用无法链接系统级的动态库。我们需要在系统中"开绿灯"。

### 修改 public.libraries.txt

正确路径是 `/system/etc/public.libraries.txt`（注意不是 public.librdroid.txt）：

```
libskia.so
```

### 添加依赖的系统 SO

libskia.so 可能依赖其他系统库，需要确保这些依赖也被暴露。检查依赖：

```bash
readelf -d libskia.so | grep NEEDED
```

常见的依赖包括：
- libGLESv2.so
- libEGL.so
- libutils.so
- liblog.so
- libicuuc.so

如果依赖的系统库不在 public.libraries.txt 中，需要一并添加。

### 重新编译系统镜像

修改后需要重新编译系统镜像并刷机，这一步是必须的。

## 7. 第四步：初始化 EGL/OpenGL 上下文

这是整个方案的核心。我们需要将 Skia 绑定到 OpenGL 上下文，让 Skia 的 GPU 后端能够正常工作。

### EGL 初始化的核心流程

```cpp
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>

class SkiaRenderer {
private:
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLSurface surface = EGL_NO_SURFACE;
    EGLContext context = EGL_NO_CONTEXT;
    EGLConfig config;

public:
    bool init(ANativeWindow* window) {
        // 1. 获取 EGL 显示
        display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
        if (display == EGL_NO_DISPLAY) {
            return false;
        }

        // 2. 初始化 EGL
        EGLint major, minor;
        if (!eglInitialize(display, &major, &minor)) {
            return false;
        }

        // 3. 选择配置
        EGLint configAttribs[] = {
            EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
            EGL_BLUE_SIZE, 8,
            EGL_GREEN_SIZE, 8,
            EGL_RED_SIZE, 8,
            EGL_ALPHA_SIZE, 8,
            EGL_DEPTH_SIZE, 16,
            EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
            EGL_NONE
        };

        EGLint numConfigs;
        if (!eglChooseConfig(display, configAttribs, &config, 1, &numConfigs)) {
            return false;
        }

        // 4. 创建窗口表面
        surface = eglCreateWindowSurface(display, config, window, nullptr);
        if (surface == EGL_NO_SURFACE) {
            return false;
        }

        // 5. 创建 OpenGL ES 2.0 上下文
        EGLint contextAttribs[] = {
            EGL_CONTEXT_CLIENT_VERSION, 2,
            EGL_NONE
        };
        context = eglCreateContext(display, config, EGL_NO_CONTEXT, contextAttribs);
        if (context == EGL_NO_CONTEXT) {
            return false;
        }

        // 6. 绑定上下文到当前线程
        if (!eglMakeCurrent(display, surface, surface, context)) {
            return false;
        }

        return true;
    }
};
```

### 创建 Skia GrContext

有了 EGL 上下文后，需要创建 Skia 的 GPU 渲染上下文：

```cpp
#include <include/gpu/GrContext.h>
#include <include/gpu/gl/GrGLInterface.h>

class SkiaRenderer {
    // ... 前面的成员变量
    GrContext* grContext = nullptr;

public:
    bool initGrContext() {
        // 获取当前的 EGL 函数指针
        const GrGLInterface* interface = GrGLInterfaceCreateEglANativeWindow();
        if (!interface) {
            return false;
        }

        // 创建 Skia 的 GrContext
        grContext = GrContext::MakeGL(interface).release();
        if (!grContext) {
            return false;
        }

        return true;
    }
};
```

### 完整的初始化流程

```cpp
bool initialize(ANativeWindow* window, int width, int height) {
    // 1. 初始化 EGL 和 OpenGL 上下文
    if (!init(window)) {
        return false;
    }

    // 2. 创建 Skia GrContext
    if (!initGrContext()) {
        return false;
    }

    // 3. 创建 Skia Surface（用于绑定的 GPU 渲染目标）
    SkImageInfo info = SkImageInfo::MakeN32Premul(width, height);
    SkSurfaceProps props(0, kUnknown_SkPixelGeometry);
    surface = SkSurface::MakeRenderTarget(grContext, info, &props);
    canvas = surface->getCanvas();

    return true;
}
```

### 核心原理：EGL 在其中扮演的角色

理解 EGL 在整个渲染管线中的作用至关重要：

```
┌────────────────────────────────────────────────────────────────┐
│                         EGL 的双重角色                          │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  角色一：OpenGL ES 容器                                         │
│  ┌──────────────────────────────────┐                          │
│  │ eglCreateContext()               │                          │
│  │ eglMakeCurrent()                 │ ──→ GPU 渲染命令执行     │
│  │                                  │      (libGLESv2.so)       │
│  └──────────────────────────────────┘                          │
│                                                                 │
│  角色二：与 SurfaceFlinger 通信                                  │
│  ┌──────────────────────────────────┐                          │
│  │ eglCreateWindowSurface()        │                          │
│  │    ↓                            │                          │
│  │ 创建 NativeWindow (BufferQueue)  │                          │
│  │    ↓                            │                          │
│  │ dequeueBuffer / queueBuffer     │                          │
│  │    ↓                            │                          │
│  │ SurfaceFlinger 合成              │                          │
│  └──────────────────────────────────┘                          │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
```

## 8. 第五步：渲染与 Buffer 提交

### 渲染流程

```cpp
void render() {
    if (!canvas || !surface) return;

    // 1. 清屏
    canvas->clear(SK_ColorWHITE);

    // 2. 使用 Skia API 绘制
    SkPaint paint;
    paint.setColor(SK_ColorBLUE);
    paint.setStyle(SkPaint::kFill_Style);
    canvas->drawRect(SkRect::MakeXYWH(100, 100, 200, 200), paint);

    // 3. 提交渲染到 GPU
    surface->flush();
}
```

### swapBuffers 提交到 SurfaceFlinger

这是最关键的一步：**swapBuffers 不仅交换前后缓冲区，还会将渲染好的 Buffer 提交给 SurfaceFlinger 进行合成**。

```cpp
void present() {
    // surface->flush() 只是将渲染命令提交到 GPU
    // 真正的"上屏"是通过 eglSwapBuffers 完成的
    eglSwapBuffers(display, surface);
}
```

**eglSwapBuffers 的内部流程：**

```
eglSwapBuffers()
    │
    ├── 1. eglSwapBuffers 是 libEGL.so 的函数
    │
    ├── 2. 获取当前 surface 关联的 BufferQueue
    │       (这是 eglCreateWindowSurface 时创建的)
    │
    ├── 3. queueBuffer()
    │       将渲染好的 Buffer 入队
    │       告诉 SurfaceFlinger："这一帧准备好了"
    │
    ├── 4. SurfaceFlinger 收到通知后
    │       ├── 从 BufferQueue 取帧
    │       ├── 与其他层合成
    │       └── 提交给 CRTC 显示
    │
    └── 5. 函数返回，应用可以开始渲染下一帧
```

整个过程对应用是透明的：我们只需要调用 `eglSwapBuffers()`，剩下的由 libEGL.so 内部处理。

### 完整的渲染循环

```cpp
void renderLoop() {
    while (running) {
        // 1. 等待 VSYNC 信号（或按需渲染）
        // ...

        // 2. 使用 Skia 绘制
        render();

        // 3. 提交到 SurfaceFlinger（真正上屏）
        eglSwapBuffers(display, surface);
    }
}
```

## 9. 完整项目参考

上述方案的完整实现可以参考开源项目：

> **参考项目**：https://github.com/ngocdaothanh/SkiaOpenGLESAndroid

该项目展示了如何在 Android 上将 Skia 与 OpenGL ES 结合使用，基本思路与本文一致。

## 10. 总结

本文介绍了一种在 Android Studio 中引用系统 libskia.so 进行硬件渲染的 POC 方案：

1. **编译 libskia.so** - 从 AOSP 编译出动态库
2. **集成到工程** - 拷贝头文件和 so，配置 ndk-build
3. **系统级授权** - 修改 `/system/etc/public.libraries.txt` 暴露库
4. **初始化 EGL/OpenGL** - 创建 EGL 上下文，创建 Skia GrContext
5. **渲染与提交** - 使用 Skia API 绘制，eglSwapBuffers 提交到 SurfaceFlinger

核心原理：
- **libskia.so** 提供图形 API，生成 GPU 渲染命令
- **libEGL.so** 管理 EGL 上下文，并通过 BufferQueue 与 SurfaceFlinger 通信
- **eglSwapBuffers** 是将帧提交上屏的关键，内部自动完成 Buffer 提交

这个方案适用于 POC 验证和轻量级渲染场景。如果项目需要长期维护，建议评估从 libhwui 导出 Skia 符号的方案。

---

**参考资料：**
- AOSP 源码：frameworks/native/libs/hwui/
- Skia 官方文档：https://skia.org/
- GitHub：https://github.com/ngocdaothanh/SkiaOpenGLESAndroid
