---
layout: post
title: Android PowerMS
categories: Android-Framework
tags: Android PMS Framework
author: Jasper
---

* content
{:toc}

本文记录对PowerManagerService(PMS,Android7.0)的分析，熟悉PMS能给予对诸如休眠、功耗、Suspend测试等相关问题的分析和解决。  
从Linux电源管理开始，从原理到机制，来一个较全面的总结。



## 开篇先知

### Linux电源管理

以Ubuntu16.04为例，cat  /sys/power/state可以看到可用的状态。

freeze: 开启状态
mem：保存到mem，点击右上角设置，suspend执行的动作就是mem
disk：保存到硬盘，界面上不知道如何操作，但是可以echo "disk" > /sys/power/state体会一下

### Android电源管理

首先，Android是基于Linux实现的，如果Linux进入mem或者disk状态，那么，任何Android的唤醒动作都是徒劳。于是Android引入early_suspend和sleep。

Android auto-suspend:
- early_suspend(默认采用)
- autosleep(默认不使能)
- wakeup_count(如果early_suspend初始化失败，使用wakeup_count)

如果判定使用哪个驱动？  
adb shell ls /sys/power/，根据优先顺序初步判定。比较靠谱的是查看启动logcat，比如：libsuspend: Selected wakeup count表示使用了wakeup_count.

策略管理：wake_lock机制

### 带着问题去阅读代码？

- Power键的响应过程是怎样的？
- SystemClock中的时间获取函数各不相同，是什么影响时间差异？
- 为什么播放视频时屏幕不会熄灭？
- 休眠状态下，Android是如何被电话、短信、闹铃唤醒的？
- Doze跟PMS有什么关系？
- 自动休眠是驱动触发还是Android层面的线程触发？
- 屏幕关闭就是休眠吗？

下面尝试认识性地回答以上问题：

- Power键的响应过程是怎样的？

这里不跟踪驱动层面的东西，直接从PhoneWindowManager着手。响应KeyEvent.KEYCODE_POWER事件后：
```java
if (down) {
    //申请锁
    //处理Power相关逻辑，比如按下Power结束铃声或者通话
    //处理长按，多次按等逻辑，必要时发送广播，考虑屏幕此时是否亮屏
    interceptPowerKeyDown(event, interactive);
} else {
    //进入powerProcess
    //  判断按下的次数：
    //  1：根据com.android.internal.R.integer.config_shortPressOnPowerBehavior响应
    interceptPowerKeyUp(event, interactive, canceled);
}
```

- SystemClock中的时间获取函数各不相同，是什么影响时间差异？

这个是Linux系统调用得到的时间差，启动时间和唤醒时间由linux内核处理，如果/dev/alarm驱动存在，则唤醒时间由其提供。现实是，/dev/alarm必定是存在的，因为AlarmManagerService需要它。
`frameworks/base/core/jni/android_os_SystemClock.cpp`  
`system/core/libutils/SystemClock.cpp`
`system/core/libutils/Timers.cpp`

shell `man clock_gettime` 可以获得linux对各种时间类型的定义。

- 为什么播放视频时屏幕不会熄灭？

因为其申请了wake_lock

- 休眠状态下，Android是如何被电话、短信、闹铃唤醒的？

这里的触发，是由系统服务触发的，比如闹钟。闹钟分为两种，普通的闹钟和关机闹钟，关机闹钟需要Alarm驱动支持。闹钟服务线程在得到时间变化的通知后，做出响应。看看下面这个AOSP的闹钟线程做了什么：

```java
private class AlarmThread extends Thread
{
    public void run()
    {
        ArrayList<Alarm> triggerList = new ArrayList<Alarm>();

        while (true)
        {
            //获得驱动信息，下面开了一个jni线程跟驱动交互
            int result = waitForAlarm(mNativeData);
            //获得唤醒时间
            mLastWakeup = SystemClock.elapsedRealtime();
            //清空
            triggerList.clear();
            //当前时间
            final long nowRTC = System.currentTimeMillis();
            //唤醒时间
            final long nowELAPSED = SystemClock.elapsedRealtime();
            //处理时间改变
            if ((result & TIME_CHANGED_MASK) != 0) {
                // The kernel can give us spurious time change notifications due to
                // small adjustments it makes internally; we want to filter those out.
                final long lastTimeChangeClockTime;
                final long expectedClockTime;
                synchronized (mLock) {
                    lastTimeChangeClockTime = mLastTimeChangeClockTime;
                    expectedClockTime = lastTimeChangeClockTime
                            + (nowELAPSED - mLastTimeChangeRealtime);
                }
                if (lastTimeChangeClockTime == 0 || nowRTC < (expectedClockTime-500)
                        || nowRTC > (expectedClockTime+500)) {
                    // The change is by at least +/- 500 ms (or this is the first change),
                    // let's do it!
                    if (DEBUG_BATCH) {
                        Slog.v(TAG, "Time changed notification from kernel; rebatching");
                    }
                    removeImpl(mTimeTickSender);
                    rebatchAllAlarms();
                    mClockReceiver.scheduleTimeTickEvent();
                    synchronized (mLock) {
                        mNumTimeChanged++;
                        mLastTimeChangeClockTime = nowRTC;
                        mLastTimeChangeRealtime = nowELAPSED;
                    }
                    //DeskClock app就监听了这个Broadcast
                    Intent intent = new Intent(Intent.ACTION_TIME_CHANGED);
                    intent.addFlags(Intent.FLAG_RECEIVER_REPLACE_PENDING
                            | Intent.FLAG_RECEIVER_REGISTERED_ONLY_BEFORE_BOOT);
                    getContext().sendBroadcastAsUser(intent, UserHandle.ALL);

                    // The world has changed on us, so we need to re-evaluate alarms
                    // regardless of whether the kernel has told us one went off.
                    result |= IS_WAKEUP_MASK;
                }
            }
            ......
```

来电触发，应当了解TeleService相关内容。

- Doze跟PMS有什么关系？

PMS在处理进入休眠的时候，调用goToSleepNoUpdateLocked函数，这个函数先是让设备进入Dozing状态，然后进入休眠。
`setWakefulnessLocked(WAKEFULNESS_DOZING, reason);`  
但是，如果当调用PowerManager.goToSleep的时候，设置了flag指定忽略Doze，则直接进入休眠。

```java
// Skip dozing if requested.
if ((flags & PowerManager.GO_TO_SLEEP_FLAG_NO_DOZE) != 0) {
    reallyGoToSleepNoUpdateLocked(eventTime, uid);
}
```

- 自动休眠是驱动触发还是Android层面的线程触发？

首先了解自动休眠相关的基础知识，可以在Settings中设置无操作多长时间休眠，可以通过`adb shell dumpsys power`获得PMS有关信息。  

```java
// Default timeout in milliseconds.  This is only used until the settings
// provider populates the actual default value (R.integer.def_screen_off_timeout).
private static final int DEFAULT_SCREEN_OFF_TIMEOUT = 15 * 1000;
private static final int DEFAULT_SLEEP_TIMEOUT = -1;

// Screen brightness boost timeout.
// Hardcoded for now until we decide what the right policy should be.
// This should perhaps be a setting.
private static final int SCREEN_BRIGHTNESS_BOOST_TIMEOUT = 5 * 1000;
```

PMS updatePowerStateLocked的Phase 1中，便会采用一个for(;;)检测自动休眠。当无用户活动超时，发出MSG_USER_ACTIVITY_TIMEOUT消息，然后执行异步处理。以下是异步处理中的函数，方法是设置mDirty标志位，然后更新电源状态，最终决定进入屏保还休眠。

```java
private void handleUserActivityTimeout() { // runs on handler thread
    synchronized (mLock) {
        if (DEBUG_SPEW) {
            Slog.d(TAG, "handleUserActivityTimeout");
        }

        mDirty |= DIRTY_USER_ACTIVITY;
        updatePowerStateLocked();
    }
}
```

- 屏幕关闭就是休眠吗？

按照电源Power键的处理逻辑和自动休眠的逻辑，的确是会进入一定的休眠模式，但不一定是严格的休眠，常常需要考虑别的问题，比如，熄屏保持网络链接，熄屏保持运行。  
某些第三方，为了绕过某些自身创造的bug，修改休眠策略，比如在屏幕熄灭后一段时间在进入休眠。

下面是来自官网的锁类型：

Flag Value | 	CPU 	| Screen |  	Keyboard
|:-|:-|
PARTIAL_WAKE_LOCK	| On*	| Off	| Off
SCREEN_DIM_WAKE_LOCK	| On	| Dim	| Off
SCREEN_BRIGHT_WAKE_LOCK	| On	| Bright	| Off
FULL_WAKE_LOCK	| On	| Bright	| Bright

## 开关机、重启、升级

PowerManagerService.java

首先关闭有关的服务，然后执行以下代码。

```java
public static void lowLevelShutdown(String reason) {
    if (reason == null) {
        reason = "";
    }
    SystemProperties.set("sys.powerctl", "shutdown," + reason);
}

/**
 * Low-level function to reboot the device. On success, this
 * function doesn't return. If more than 20 seconds passes from
 * the time a reboot is requested, this method returns.
 *
 * @param reason code to pass to the kernel (e.g. "recovery"), or null.
 */
public static void lowLevelReboot(String reason) {
    if (reason == null) {
        reason = "";
    }
    //这里可以看到，无论是单纯的进入recovery还是进入recovery执行系统update，都是一样的动作。
    //recovery在启动的时候，会判断是不是要执行系统update，比如通过判断command中是否有内容。
    if (reason.equals(PowerManager.REBOOT_RECOVERY)
            || reason.equals(PowerManager.REBOOT_RECOVERY_UPDATE)) {
        SystemProperties.set("sys.powerctl", "reboot,recovery");
    } else {
        SystemProperties.set("sys.powerctl", "reboot," + reason);
    }
}
```

接下来就触发init进程对属性sys.powerctl的响应。

nougat/system/core

init.rc

```
593 on property:sys.powerctl=*
594     powerctl ${sys.powerctl}
```

builtin_functions是init注册的函数，`{"powerctl",                {1,     1,    do_powerctl}}`

最后执行Linux系统调用reboot函数完成reboot（可能是进入recovery）或者power off。

## 休眠和自动休眠

### 直观的认识

直观的认识一下Android的休眠相关sysfs:

```
generic_arm64:/ # ls sys/power
autosleep pm_async pm_freeze_timeout state wake_lock wake_unlock wakeup_count
```

- autosleep：弃用
- state：写入"on"初始化early_suspend，wakeup_count模式中，写入"mem"进入休眠
- wake_lock：写入字符串加锁
- wake_unlock：写入字符串解锁
- wakeup_count：线程定时读取，如果不为空，执行休眠动作进入休眠

直观的认识休眠（屏幕关闭就是休眠吗？）：  
- 机器播放视频时不熄灭屏幕
- 按下Power键屏幕熄灭
- Display设置15秒、30秒、1分钟等关闭

## early_suspend机制

从PMS的构造函数中可以看到，autosuspend默认采用early_suspend模式，循环读取/sys/power/wait_for_fb_sleep和/sys/power/wait_for_fb_wake.  
既然，单独的等待读取就能实现休眠和唤醒，那么，必定是驱动中实现了休眠功能，完成休眠或者唤醒返回驱动的read调用。

## wakeup_count机制

从PMS的构造函数部分内容可以看到，autosuspend不断读取wakeup_count驱动，如果不为空则回写并进如休眠。可以，休眠并不是wakeup_count驱动负责的，而是往/sys/power/state中写入内容。我们不关心为什么往/sys/power/state写入"mem"会进入休眠，而是关心wakeup_count机制。  
可以猜想得到，往wake_lock中写入内容必定导致读取wakeup_count为0，往wake_unlock中写入内容，可能导致wakeup_count有值，从而进入休眠。

## PMS的初始化

### 构造函数

```java
public PowerManagerService(Context context) {
    super(context);// SystemService的构造函数
    mContext = context;
    //初始化一个Handler
    mHandlerThread = new ServiceThread(TAG,
            Process.THREAD_PRIORITY_DISPLAY, false /*allowIo*/);
    mHandlerThread.start();
    mHandler = new PowerManagerHandler(mHandlerThread.getLooper());

    synchronized (mLock) {
      //创建两个SuspendBlocker对象，添加到 mSuspendBlockers 变量中
      //private final ArrayList<SuspendBlocker> mSuspendBlockers = new ArrayList<SuspendBlocker>();
        mWakeLockSuspendBlocker = createSuspendBlockerLocked("PowerManagerService.WakeLocks");
        mDisplaySuspendBlocker = createSuspendBlockerLocked("PowerManagerService.Display");
        //SuspendBlocker的acquire函数
        //进入JNI nativeAcquireSuspendBlocker
        //PARTIAL_WAKE_LOCK=1 (hardware/libhardware_legacy/include/hardware_legacy/power.h)
        //往/sys/power/wake_lock中写入字符串
        //可以理解为，申请CPU保持运行      
        //同样的，如果要release申请的lock，就是往/sys/power/wake_unlock中写入相同的字符串
        mDisplaySuspendBlocker.acquire();
        mHoldingDisplaySuspendBlocker = true;
        mHalAutoSuspendModeEnabled = false;
        mHalInteractiveModeEnabled = true;

        mWakefulness = WAKEFULNESS_AWAKE;

        // JNI nativeInit，按照AOSP，它什么事情都没干。
        nativeInit();

        ///system/core/libsuspend/autosuspend.c
        //autosuspend_enable/autosuspend_disable
        //autosuspend_init:
        //1. autosuspend_earlysuspend_init:
        //1.1 往/sys/power/state中写入"on"，如果写入失败跳转到2. wakeup_count
        //1.2 start_earlysuspend_thread - earlysuspend_thread_func
        //1.2.1 wait_for_fb_sleep - 读取/sys/power/wait_for_fb_sleep
        //1.2.2 wait_for_fb_wake - 读取/sys/power/wait_for_fb_wake
        //2. autosuspend_wakeup_count_init: 创建一个信号量suspend_lockout并创建一个线程
        //2.1 如果这个信号量不为0，表示wakeup_count已经enable
        //2.2 线程每100ms循环一次，不包括阻塞时间
        //2.3 线程等待信号量，并读取/sys/power/wakeup_count，如果为空或者读取错误continue
        //2.4 当从wakeup_count读取到值，把"mem"写入/sys/power/state，执行wakeup_func函数
        //2.5 wakeup_func当前是NULL
        nativeSetAutoSuspend(false);
        //小结：
        //初始化AutoSuspend优先选择early_suspend，其次选择wakeup_count，autosleep默认不使能。
        //autosuspend参考代码位置：
        //system.core.libsuspend(system/core/libsuspend)

        //AOSP中，它什么都没做
        nativeSetInteractive(true);

        //AOSP,底层居然没定义相关
        nativeSetFeature(POWER_FEATURE_DOUBLE_TAP_TO_WAKE, 0);
    }
}
```

PMS的构造函数：  

- 把"on"写入/sys/power/state，
- 初始化autosuspend(默认early_suspend模式)
- 把"PowerManagerService.Display"写入/sys/power/wake_lock.

### PMS onStart

```java
@Override
public void onStart() {
    publishBinderService(Context.POWER_SERVICE, new BinderService()); //添加到ServiceManager
    publishLocalService(PowerManagerInternal.class, new LocalService()); //添加到LocalServices

    Watchdog.getInstance().addMonitor(this); //添加到看门狗
    Watchdog.getInstance().addThread(mHandler);
}
```

### PMS systemReady

`SystemServer: mPowerManagerService.systemReady(mActivityManagerService.getAppOpsService());`  
传入/data/system/appops.xml操作接口的对象。

```java
public void systemReady(IAppOpsService appOps) {
    synchronized (mLock) {
        mSystemReady = true;
        mAppOps = appOps;
        //？
        mDreamManager = getLocalService(DreamManagerInternal.class);
        //显示管理
        mDisplayManagerInternal = getLocalService(DisplayManagerInternal.class);
        //窗口策略
        mPolicy = getLocalService(WindowManagerPolicy.class);
        //电池管理
        mBatteryManagerInternal = getLocalService(BatteryManagerInternal.class);

        //从PowerManager获得屏幕亮度信息
        PowerManager pm = (PowerManager) mContext.getSystemService(Context.POWER_SERVICE);
        mScreenBrightnessSettingMinimum = pm.getMinimumScreenBrightnessSetting();
        mScreenBrightnessSettingMaximum = pm.getMaximumScreenBrightnessSetting();
        mScreenBrightnessSettingDefault = pm.getDefaultScreenBrightnessSetting();

        //传感器
        SensorManager sensorManager = new SystemSensorManager(mContext, mHandler.getLooper());

        // The notifier runs on the system server's main looper so as not to interfere
        // with the animations and other critical functions of the power manager.
        mBatteryStats = BatteryStatsService.getService();
        mNotifier = new Notifier(Looper.getMainLooper(), mContext, mBatteryStats,
                mAppOps, createSuspendBlockerLocked("PowerManagerService.Broadcasts"),
                mPolicy);

        //无线充电
        mWirelessChargerDetector = new WirelessChargerDetector(sensorManager,
                createSuspendBlockerLocked("PowerManagerService.WirelessChargerDetector"),
                mHandler);
        mSettingsObserver = new SettingsObserver(mHandler);

        //光线管理
        mLightsManager = getLocalService(LightsManager.class);
        mAttentionLight = mLightsManager.getLight(LightsManager.LIGHT_ID_ATTENTION);

        // Initialize display power management.
        mDisplayManagerInternal.initPowerManagement(
                mDisplayPowerCallbacks, mHandler, sensorManager);

        // Register for broadcasts from other components of the system.
        IntentFilter filter = new IntentFilter();
        filter.addAction(Intent.ACTION_BATTERY_CHANGED);
        filter.setPriority(IntentFilter.SYSTEM_HIGH_PRIORITY);
        mContext.registerReceiver(new BatteryReceiver(), filter, null, mHandler);

        filter = new IntentFilter();
        filter.addAction(Intent.ACTION_DREAMING_STARTED);
        filter.addAction(Intent.ACTION_DREAMING_STOPPED);
        mContext.registerReceiver(new DreamReceiver(), filter, null, mHandler);

        filter = new IntentFilter();
        filter.addAction(Intent.ACTION_USER_SWITCHED);
        mContext.registerReceiver(new UserSwitchedReceiver(), filter, null, mHandler);

        filter = new IntentFilter();
        filter.addAction(Intent.ACTION_DOCK_EVENT);
        mContext.registerReceiver(new DockReceiver(), filter, null, mHandler);

        // Register for settings changes.
        final ContentResolver resolver = mContext.getContentResolver();
        resolver.registerContentObserver(Settings.Secure.getUriFor(
                Settings.Secure.SCREENSAVER_ENABLED),
                false, mSettingsObserver, UserHandle.USER_ALL);
        resolver.registerContentObserver(Settings.Secure.getUriFor(
                Settings.Secure.SCREENSAVER_ACTIVATE_ON_SLEEP),
                false, mSettingsObserver, UserHandle.USER_ALL);
        resolver.registerContentObserver(Settings.Secure.getUriFor(
                Settings.Secure.SCREENSAVER_ACTIVATE_ON_DOCK),
                false, mSettingsObserver, UserHandle.USER_ALL);
        resolver.registerContentObserver(Settings.System.getUriFor(
                Settings.System.SCREEN_OFF_TIMEOUT),
                false, mSettingsObserver, UserHandle.USER_ALL);
        resolver.registerContentObserver(Settings.Secure.getUriFor(
                Settings.Secure.SLEEP_TIMEOUT),
                false, mSettingsObserver, UserHandle.USER_ALL);
        resolver.registerContentObserver(Settings.Global.getUriFor(
                Settings.Global.STAY_ON_WHILE_PLUGGED_IN),
                false, mSettingsObserver, UserHandle.USER_ALL);
        resolver.registerContentObserver(Settings.System.getUriFor(
                Settings.System.SCREEN_BRIGHTNESS),
                false, mSettingsObserver, UserHandle.USER_ALL);
        resolver.registerContentObserver(Settings.System.getUriFor(
                Settings.System.SCREEN_BRIGHTNESS_MODE),
                false, mSettingsObserver, UserHandle.USER_ALL);
        resolver.registerContentObserver(Settings.System.getUriFor(
                Settings.System.SCREEN_AUTO_BRIGHTNESS_ADJ),
                false, mSettingsObserver, UserHandle.USER_ALL);
        resolver.registerContentObserver(Settings.Global.getUriFor(
                Settings.Global.LOW_POWER_MODE),
                false, mSettingsObserver, UserHandle.USER_ALL);
        resolver.registerContentObserver(Settings.Global.getUriFor(
                Settings.Global.LOW_POWER_MODE_TRIGGER_LEVEL),
                false, mSettingsObserver, UserHandle.USER_ALL);
        resolver.registerContentObserver(Settings.Global.getUriFor(
                Settings.Global.THEATER_MODE_ON),
                false, mSettingsObserver, UserHandle.USER_ALL);
        resolver.registerContentObserver(Settings.Secure.getUriFor(
                Settings.Secure.DOUBLE_TAP_TO_WAKE),
                false, mSettingsObserver, UserHandle.USER_ALL);
        resolver.registerContentObserver(Settings.Secure.getUriFor(
                Secure.BRIGHTNESS_USE_TWILIGHT),
                false, mSettingsObserver, UserHandle.USER_ALL);
        //VR相关
        IVrManager vrManager =
                (IVrManager) getBinderService(VrManagerService.VR_MANAGER_BINDER_SERVICE);
        try {
            vrManager.registerListener(mVrStateCallbacks);
        } catch (RemoteException e) {
            Slog.e(TAG, "Failed to register VR mode state listener: " + e);
        }
        // Go.
        // 获得一大批配置信息
        readConfigurationLocked();
        // 一大批设置信息
        updateSettingsLocked();
        mDirty |= DIRTY_BATTERY_STATE;
        // 显示和autosuspend相关重新设置
        // 更新电源状态相关信息
        updatePowerStateLocked();

        // 以上的信息可以通过adb shell dumpsys power打印出来
    }
}
```

systemReady中，获得app的权限信息服务、无限充电以及VR服务，传感器、窗口、电池、光线管理，监听一些类似用户切换、光线变化、Setting设置改变。  
获取一大批配置信息和Settings信息，如果是屏幕熄灭或者处于Doze模式则关闭auto-suspend.

## goToSleep

```java
@Override // Binder call
public void goToSleep(long eventTime, int reason, int flags) {
    mContext.enforceCallingOrSelfPermission(
            android.Manifest.permission.DEVICE_POWER, null);

    final int uid = Binder.getCallingUid();
    final long ident = Binder.clearCallingIdentity();
    try {
        goToSleepInternal(eventTime, reason, flags, uid);
    } finally {
        Binder.restoreCallingIdentity(ident);
    }
}
```

```java
private void goToSleepInternal(long eventTime, int reason, int flags, int uid) {
        synchronized (mLock) {
          //1. 判断休眠触发类型，比如设备管理策略触发、屏幕超时、Power按键、LID切换（合上盖子）、HDMI休眠，其它情况属于App触发。
          //2. 先进入Dozing状态
          //3. 如何设置忽略Dozing，则进入reallyGoToSleepNoUpdateLocked
          //    setWakefulnessLocked(WAKEFULNESS_ASLEEP, PowerManager.GO_TO_SLEEP_REASON_TIMEOUT);
          //不管怎样，这个函数都正常的返回true，进入if
            if (goToSleepNoUpdateLocked(eventTime, reason, flags, uid)) {
                //Power State转换的主函数，收集所有信息，完整的实现Power状态转换。
                updatePowerStateLocked();                
            }
        }
    }
```

## wakeup

```java
private boolean wakeUpNoUpdateLocked(long eventTime, String reason, int reasonUid,
        String opPackageName, int opUid) {
    try {
        switch (mWakefulness) {
            case WAKEFULNESS_ASLEEP:
                Slog.i(TAG, "Waking up from sleep (uid " + reasonUid +")...");
                break;
            case WAKEFULNESS_DREAMING:
                Slog.i(TAG, "Waking up from dream (uid " + reasonUid +")...");
                break;
            case WAKEFULNESS_DOZING:
                Slog.i(TAG, "Waking up from dozing (uid " + reasonUid +")...");
                break;
        }

        mLastWakeTime = eventTime;
        setWakefulnessLocked(WAKEFULNESS_AWAKE, 0);

        //通知唤醒，1.BatteryStatsService. 2.权限检查
        mNotifier.onWakeUp(reason, reasonUid, opPackageName, opUid);
        //更新一个userActivity到mDirty，这样，就可以使用updatePowerStateLocked来点亮屏幕
        userActivityNoUpdateLocked(
                eventTime, PowerManager.USER_ACTIVITY_EVENT_OTHER, 0, reasonUid);
    } finally {
        Trace.traceEnd(Trace.TRACE_TAG_POWER);
    }
    return true;
}
```

## PMS核心函数updatePowerStateLocked

参考[PMS核心函数updatePowerStateLocked](http://blog.csdn.net/gaugamela/article/details/52838654)，写得非常详细。

它所给出的大致流程是这样的：

![](http://img.blog.csdn.net/20161022170516383)

## userActivity

```java
@Override // Binder call
public void userActivity(long eventTime, int event, int flags) {
    final int uid = Binder.getCallingUid();
    final long ident = Binder.clearCallingIdentity();
    try {
        userActivityInternal(eventTime, event, flags, uid);
    } finally {
        Binder.restoreCallingIdentity(ident);
    }
}
```

```java
private boolean userActivityNoUpdateLocked(long eventTime, int event, int flags, int uid) {
        mNotifier.onUserActivity(event, uid);
                mDirty |= DIRTY_USER_ACTIVITY;
                return true;
}
```

## 参考文献

[Linux子系统的初始化_subsys_initcall()：那些入口函数 ](http://blog.csdn.net/yimiyangguang1314/article/details/7312209)  
[Android7.0 Power键如何点亮屏幕？](http://blog.csdn.net/fu_kevin0606/article/details/54408094)  
[Android6.0 PowerManager深入分析](http://blog.csdn.net/u011311586/article/details/51034313)  
[Android ContentResolver](http://blog.csdn.net/qinjuning/article/details/7047607)  
[PMS核心函数updatePowerStateLocked](http://blog.csdn.net/gaugamela/article/details/52838654)  
