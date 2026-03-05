---
layout: post
title: "Android 开发：引用系统 libskia.so 进行硬件渲染"
categories: "Android"
tags: Android Skia libhwui OpenGL HardwareRendering AOSP
author: Jasper
---

在做轻量级硬件渲染引擎的 POC 时，我们希望使用 Skia 的 API 来完成渲染工作。系统中的 libhwui.so 包含了编译好的 Skia，但它是作为静态库链接进去的，API 被隐藏了。本文将介绍一种绕过方案：直接引用 AOSP 编译出的系统 libskia.so，实现硬件渲染。




## 背景与动机

Android 的 UI 渲染体系依赖于 Skia 图形库。在 AOSP 中，Skia 通常以静态库（libskia.a）的形式编译进 libhwui.so，供系统 UI 框架使用。

但如果我们想开发自己的渲染引擎，复用 Skia 的能力，就会遇到一个问题：**libhwui.so 隐藏了 Skia 的 public API**。我们无法直接调用那些被编译进 libhwui.so 中的 Skia 函数。

一个思路是：从 libhwui.so 导出 Skia 的符号。但这需要全面的评估工作，涉及符号冲突、API 稳定性等复杂问题，不在本文讨论范围。

另一个思路是：**直接使用 AOSP 编译出的 libskia.so**。这就是本文要介绍的方法。

## 方案概述

整体方案分为五个步骤：

1. 在 AOSP 中添加编译项，编译出 libskia.so
2. 在工程中引用 so，并拷贝 AOSP Skia 头文件
3. 设置允许三方应用链接系统 lib
4. 给 Skia 绑定 OpenGL 上下文
5. 编写渲染示例

## 第一步：在 AOSP 中编译 libskia.so

默认情况下，AOSP 编译的是 libskia.a（静态库）。我们需要修改编译配置，生成动态库。

### 修改 Android.mk

在 Skia 源码目录（`frameworks/native/libs/ui/Skia Olson` 或对应版本路径）找到 Android.mk，添加以下配置：

```makefile
# 生成 libskia.so
LOCAL_MODULE_TAGS := optional
LOCAL_VENDOR_MODULE := true
```

或者使用更简单的方式：在编译命令中指定：

```bash
mmma frameworks/native/libs/ui/Skia -M libskia.mk BUILD_SHARED_LIBRARY=true
```

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

## 第二步：集成到工程

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
- `include/config/ - 平台配置

### 配置 CMake 或 ndk-build

在 CMakeLists.txt 中：

```cmake
add_library(skia SHARED IMPORTED)
set_target_properties(skia PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/jni/libskia.so
)

include_directories(${CMAKE_SOURCE_DIR}/jni/include)
target_link_libraries(your_native_lib skia libGLESv2 libEGL)
```

## 第三步：允许三方应用链接系统 lib

默认情况下，非系统应用无法链接系统级的动态库。我们需要在系统中"开绿灯"。

### 修改 public.librdroid.txt

在 AOSP 源码中，找到 `system/core/rootdir/etc/public.librdroid.txt`（或对应版本路径），添加：

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

如果依赖的系统库不在 public.librdroid.txt 中，需要一并添加：

```
libEGL.so
libGLESv2.so
libutils.so
liblog.so
```

### 重新编译系统镜像

修改后需要重新编译系统镜像并刷机，这一步是必须的，因为系统镜像决定了哪些 so 对三方应用可见。

## 第四步：绑定 OpenGL 上下文

Skia 的硬件渲染需要 OpenGL（或 Vulkan）上下文。这一步是关键，需要参考 AOSP 中 libhwui 的实现。

### EglManager 参考

在 AOSP 源码中，libhwui 使用 EglManager 来管理 EGL 上下文。核心代码位于：

```
frameworks/native/libs/hwui/EglManager.cpp
```

### 简化实现

以下是一个简化的 EGL 上下文绑定示例：

```cpp
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>

class SkiaEGL {
private:
    EGLDisplay display;
    EGLSurface surface;
    EGLContext context;
    EGLConfig config;

public:
    bool init(ANativeWindow* window) {
        // 获取 EGL 显示
        display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
        if (display == EGL_NO_DISPLAY) return false;

        // 初始化 EGL
        EGLint major, minor;
        if (!eglInitialize(display, &major, &minor)) return false;

        // 配置 EGL
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

        // 创建表面
        surface = eglCreateWindowSurface(display, config, window, nullptr);
        if (surface == EGL_NO_SURFACE) return false;

        // 创建上下文
        EGLint contextAttribs[] = {
            EGL_CONTEXT_CLIENT_VERSION, 2,
            EGL_NONE
        };
        context = eglCreateContext(display, config, EGL_NO_CONTEXT, contextAttribs);
        if (context == EGL_NO_CONTEXT) return false;

        // 绑定上下文
        return eglMakeCurrent(display, surface, surface, context);
    }

    void swapBuffers() {
        eglSwapBuffers(display, surface);
    }

    ~SkiaEGL() {
        if (display != EGL_NO_DISPLAY) {
            eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
            eglDestroyContext(display, context);
            eglDestroySurface(display, surface);
            eglTerminate(display);
        }
    }
};
```

### 与 Skia GrContext 关联

有了 EGL 上下文后，需要创建 Skia 的 GrContext：

```cpp
#include <include/gpu/GrContextOptions.h>
#include <include/gpu/gl/GrGLInterface.h>
#include <include/gpu/gl/GrGLAssembleInterface.h>

GrContext* createSkiaGrContext(GrEGLInterface eglInterface) {
    // 使用 EGL 接口创建 Skia 的 GrContext
    sk_sp<GrContext> grContext = GrContext::MakeGL(std::move(eglInterface));
    return grContext.release();
}
```

AOSP 中的实现更为复杂，涉及 RenderThread、RenderProxy 等多个类的协作。建议直接参考 `frameworks/native/libs/hwui/` 下的源码。

## 第五步：渲染示例

完整的渲染流程如下：

```cpp
#include <include/core/SkCanvas.h>
#include <include/core/SkPaint.h>
#include <include/core/SkRect.h>

void renderFrame(GrContext* grContext, int width, int height) {
    // 创建 Skia 画布
    SkImageInfo info = SkImageInfo::MakeN32Premul(width, height);
    SkSurfaceProps props(0, kUnknown_SkPixelGeometry);
    sk_sp<SkSurface> surface = SkSurface::MakeRenderTarget(grContext, info, &props);
    SkCanvas* canvas = surface->getCanvas();

    // 清屏
    canvas->clear(SK_ColorWHITE);

    // 绘制矩形
    SkPaint paint;
    paint.setColor(SK_ColorBLUE);
    paint.setStyle(SkPaint::kFill_Style);
    canvas->drawRect(SkRect::MakeXYWH(100, 100, 200, 200), paint);

    // 绘制圆形
    paint.setColor(SK_ColorRED);
    canvas->drawCircle(300, 200, 80, paint);

    // 提交渲染
    surface->flush();
}
```

## 完整项目参考

上述方案的完整实现可以参考开源项目：

> **参考项目**：https://github.com/ngocdaothanh/SkiaOpenGLESAndroid

该项目展示了如何在 Android 上将 Skia 与 OpenGL ES 结合使用，基本思路与本文一致。

## 总结

本文介绍了一种在 Android Studio 中引用系统 libskia.so 进行硬件渲染的方案：

1. **编译 libskia.so** - 从 AOSP 编译出动态库
2. **集成到工程** - 拷贝头文件和 so，配置 ndk-build
3. **系统级授权** - 修改 public.librdroid.txt 暴露库
4. **绑定 OpenGL** - 参考 AOSP EglManager 实现
5. **渲染示例** - 使用 Skia API 绘制图形

这个方案适用于 POC 验证和轻量级渲染场景。如果项目需要长期维护，建议评估从 libhwui 导出 Skia 符号的方案，或者直接使用 Android 提供的官方图形 API（如 RenderNode、Canvas 等）。

---

**参考资料：**
- AOSP 源码：frameworks/native/libs/hwui/
- Skia 官方文档：https://skia.org/
- GitHub：https://github.com/ngocdaothanh/SkiaOpenGLESAndroid
