---
layout: post
title: "Android DVM JNI动态注册"
categories: Android-Framework
tags: Android Binder
author: Jasper
---

* content
{:toc}

本文简要记录Android DVM启动的时候如何动态注册JNI函数。



## Android Runtime

frameworks/base/core/jni/AndroidRuntime.cpp

-AndroidRuntime::start()  
--startVm(*)  
--startReg(*)  
---register_jni_procs(gRegJNI, NELEM(gRegJNI), env)  
----array[i].mProc(env) //执行结构体中的函数指针指向的函数

```c
1235     #define REG_JNI(name)      { name }
1236     struct RegJNIRec {
1237         int (*mProc)(JNIEnv*);
1238     };

// REG_JNI宏的作用，将name传递给RegJNIRec结构体里的函数指针mProc。

static const RegJNIRec gRegJNI[] = { //RegJNIRec结构体数组，每一个数组元素都包含一个函数指针。
    REG_JNI(register_com_android_internal_os_RuntimeInit),
    REG_JNI(register_android_os_SystemClock),
    REG_JNI(register_android_util_EventLog),
    REG_JNI(register_android_util_Log),
    REG_JNI(register_android_util_MemoryIntArray),
    REG_JNI(register_android_util_PathParser),
    REG_JNI(register_android_app_admin_SecurityLog),
    REG_JNI(register_android_content_AssetManager),
    REG_JNI(register_android_content_StringBlock),
    REG_JNI(register_android_content_XmlBlock),
    REG_JNI(register_android_text_AndroidCharacter),
    REG_JNI(register_android_text_StaticLayout),
    REG_JNI(register_android_text_AndroidBidi),
    REG_JNI(register_android_view_InputDevice),
    REG_JNI(register_android_view_KeyCharacterMap),
    REG_JNI(register_android_os_Process), //关注
    REG_JNI(register_android_os_SystemProperties),
    REG_JNI(register_android_os_Binder),  //关注
    REG_JNI(register_android_os_Parcel),  //关注
    REG_JNI(register_android_nio_utils),
    REG_JNI(register_android_graphics_Canvas),
    REG_JNI(register_android_graphics_Graphics),
    REG_JNI(register_android_view_DisplayEventReceiver),
    REG_JNI(register_android_view_RenderNode),
    REG_JNI(register_android_view_RenderNodeAnimator),
    REG_JNI(register_android_view_GraphicBuffer),
    REG_JNI(register_android_view_DisplayListCanvas),
    REG_JNI(register_android_view_HardwareLayer),
    REG_JNI(register_android_view_ThreadedRenderer),
    REG_JNI(register_android_view_Surface),
    REG_JNI(register_android_view_SurfaceControl),
    REG_JNI(register_android_view_SurfaceSession),
    REG_JNI(register_android_view_TextureView),
    REG_JNI(register_com_android_internal_view_animation_NativeInterpolatorFactoryHelper),
    REG_JNI(register_com_google_android_gles_jni_EGLImpl),
    REG_JNI(register_com_google_android_gles_jni_GLImpl),
    REG_JNI(register_android_opengl_jni_EGL14),
    REG_JNI(register_android_opengl_jni_EGLExt),
    REG_JNI(register_android_opengl_jni_GLES10),
    REG_JNI(register_android_opengl_jni_GLES10Ext),
    REG_JNI(register_android_opengl_jni_GLES11),
    REG_JNI(register_android_opengl_jni_GLES11Ext),
    REG_JNI(register_android_opengl_jni_GLES20),
    REG_JNI(register_android_opengl_jni_GLES30),
    REG_JNI(register_android_opengl_jni_GLES31),
    REG_JNI(register_android_opengl_jni_GLES31Ext),
    REG_JNI(register_android_opengl_jni_GLES32),

    REG_JNI(register_android_graphics_Bitmap),
    REG_JNI(register_android_graphics_BitmapFactory),
    REG_JNI(register_android_graphics_BitmapRegionDecoder),
    REG_JNI(register_android_graphics_Camera),
    REG_JNI(register_android_graphics_CreateJavaOutputStreamAdaptor),
    REG_JNI(register_android_graphics_CanvasProperty),
    REG_JNI(register_android_graphics_ColorFilter),
    REG_JNI(register_android_graphics_DrawFilter),
    REG_JNI(register_android_graphics_FontFamily),
    REG_JNI(register_android_graphics_Interpolator),
    REG_JNI(register_android_graphics_LayerRasterizer),
    REG_JNI(register_android_graphics_MaskFilter),
    REG_JNI(register_android_graphics_Matrix),
    REG_JNI(register_android_graphics_Movie),
    REG_JNI(register_android_graphics_NinePatch),
    REG_JNI(register_android_graphics_Paint),
    REG_JNI(register_android_graphics_Path),
    REG_JNI(register_android_graphics_PathMeasure),
    REG_JNI(register_android_graphics_PathEffect),
    REG_JNI(register_android_graphics_Picture),
    REG_JNI(register_android_graphics_PorterDuff),
    REG_JNI(register_android_graphics_Rasterizer),
    REG_JNI(register_android_graphics_Region),
    REG_JNI(register_android_graphics_Shader),
    REG_JNI(register_android_graphics_SurfaceTexture),
    REG_JNI(register_android_graphics_Typeface),
    REG_JNI(register_android_graphics_Xfermode),
    REG_JNI(register_android_graphics_YuvImage),
    REG_JNI(register_android_graphics_drawable_AnimatedVectorDrawable),
    REG_JNI(register_android_graphics_drawable_VectorDrawable),
    REG_JNI(register_android_graphics_pdf_PdfDocument),
    REG_JNI(register_android_graphics_pdf_PdfEditor),
    REG_JNI(register_android_graphics_pdf_PdfRenderer),

    REG_JNI(register_android_database_CursorWindow),
    REG_JNI(register_android_database_SQLiteConnection),
    REG_JNI(register_android_database_SQLiteGlobal),
    REG_JNI(register_android_database_SQLiteDebug),
    REG_JNI(register_android_os_Debug),
    REG_JNI(register_android_os_FileObserver),
    REG_JNI(register_android_os_MessageQueue),
    REG_JNI(register_android_os_SELinux),
    REG_JNI(register_android_os_Trace),
    REG_JNI(register_android_os_UEventObserver),
    REG_JNI(register_android_net_LocalSocketImpl),
    REG_JNI(register_android_net_NetworkUtils),
    REG_JNI(register_android_net_TrafficStats),
    REG_JNI(register_android_os_MemoryFile),
    REG_JNI(register_com_android_internal_os_PathClassLoaderFactory),
    REG_JNI(register_com_android_internal_os_Zygote),
    REG_JNI(register_com_android_internal_util_VirtualRefBasePtr),
    REG_JNI(register_android_hardware_Camera),
    REG_JNI(register_android_hardware_camera2_CameraMetadata),
    REG_JNI(register_android_hardware_camera2_legacy_LegacyCameraDevice),
    REG_JNI(register_android_hardware_camera2_legacy_PerfMeasurement),
    REG_JNI(register_android_hardware_camera2_DngCreator),
    REG_JNI(register_android_hardware_Radio),
    REG_JNI(register_android_hardware_SensorManager),
    REG_JNI(register_android_hardware_SerialPort),
    REG_JNI(register_android_hardware_SoundTrigger),
    REG_JNI(register_android_hardware_UsbDevice),
    REG_JNI(register_android_hardware_UsbDeviceConnection),
    REG_JNI(register_android_hardware_UsbRequest),
    REG_JNI(register_android_hardware_location_ActivityRecognitionHardware),
    REG_JNI(register_android_hardware_location_ContextHubService),
    REG_JNI(register_android_media_AudioRecord),
    REG_JNI(register_android_media_AudioSystem),
    REG_JNI(register_android_media_AudioTrack),
    REG_JNI(register_android_media_JetPlayer),
    REG_JNI(register_android_media_RemoteDisplay),
    REG_JNI(register_android_media_ToneGenerator),

    REG_JNI(register_android_opengl_classes),
    REG_JNI(register_android_server_NetworkManagementSocketTagger),
    REG_JNI(register_android_ddm_DdmHandleNativeHeap),
    REG_JNI(register_android_backup_BackupDataInput),
    REG_JNI(register_android_backup_BackupDataOutput),
    REG_JNI(register_android_backup_FileBackupHelperBase),
    REG_JNI(register_android_backup_BackupHelperDispatcher),
    REG_JNI(register_android_app_backup_FullBackup),
    REG_JNI(register_android_app_Activity), //关注
    REG_JNI(register_android_app_ActivityThread), //关注
    REG_JNI(register_android_app_ApplicationLoaders),
    REG_JNI(register_android_app_NativeActivity),
    REG_JNI(register_android_util_jar_StrictJarFile),
    REG_JNI(register_android_view_InputChannel),
    REG_JNI(register_android_view_InputEventReceiver),
    REG_JNI(register_android_view_InputEventSender),
    REG_JNI(register_android_view_InputQueue),
    REG_JNI(register_android_view_KeyEvent),
    REG_JNI(register_android_view_MotionEvent),
    REG_JNI(register_android_view_PointerIcon),
    REG_JNI(register_android_view_VelocityTracker),

    REG_JNI(register_android_content_res_ObbScanner),
    REG_JNI(register_android_content_res_Configuration),

    REG_JNI(register_android_animation_PropertyValuesHolder),
    REG_JNI(register_com_android_internal_content_NativeLibraryHelper),
    REG_JNI(register_com_android_internal_net_NetworkStatsFactory),

};
```






