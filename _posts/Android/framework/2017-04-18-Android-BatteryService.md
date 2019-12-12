---
layout: post
title: Android BatteryService
categories: Android-Framework
tags: Android BatteryService
author: Jasper
---

* content
{:toc}

本文记录对BatteryService（Android7.0）的阅读理解。Android中，获得电池的方法是监听来自BatteryService（本文简称BS）发出的系统广播，App通过注册广播接收器获得电池的状态信息.




## 带着问题阅读

- 广播是如何发送出来的，什么情况下会发送广播？
- BS跟硬件电池有什么关系，它的电量信息是如何获取的？
- BS跟PowerManagerService的关系是什么？
- 为什么手机的电池曲线老是不正常，为什么不是线性的（假设长时间功耗相同）？
- 如何计算某一个进程的耗电量？

先盗一张网络图片，表明了BS、PMS和AMS之间在Battery上的关系：

![](http://oeraas0pz.bkt.clouddn.com/wp-content/uploads/2016/10/20161009_57f9c0d7cb226.jpg)

## 入口

frameworks/base/services/core/java/com/android/server/BatteryService.java

```java
20 import android.os.BatteryStats;                                                                                                             
24 import com.android.internal.app.IBatteryStats;
25 import com.android.server.am.BatteryStatsService;
```

或者我们dumpsys中获得有关电池的信息

dupsys -l | grep battery

```bash
$ dumpsys -l | grep battery
  battery
  batteryproperties
  batterystats
```

### BS/BSS的启动

BS的启动
`·SystemServer - startCoreServices - mSystemServiceManager.startService(BatteryService.class);`  

BSS在AMS中启动

```java
2616         mBatteryStatsService = new BatteryStatsService(systemDir, mHandler);                                                              
2617         mBatteryStatsService.getActiveStatistics().readLocked();
2618         mBatteryStatsService.scheduleWriteToDisk();
2619         mOnBattery = DEBUG_POWER ? true
2620                 : mBatteryStatsService.getActiveStatistics().getIsOnBattery();
2621         mBatteryStatsService.getActiveStatistics().setCallback(this);
```

## BS 构造函数

```java
150     public BatteryService(Context context) {
151         super(context);//SystemService构造函数
152
153         mContext = context;
154         mHandler = new Handler(true /*async*/);
            //获得LightManger
155         mLed = new Led(context, getLocalService(LightsManager.class));
            //获得BSS
156         mBatteryStats = BatteryStatsService.getService();
157
            //配置信息：警告电压
158         mCriticalBatteryLevel = mContext.getResources().getInteger(
159                 com.android.internal.R.integer.config_criticalBatteryWarningLevel);
            //低电提醒电压
160         mLowBatteryWarningLevel = mContext.getResources().getInteger(
161                 com.android.internal.R.integer.config_lowBatteryWarningLevel);
            //？
162         mLowBatteryCloseWarningLevel = mLowBatteryWarningLevel + mContext.getResources().getInteger(
163                 com.android.internal.R.integer.config_lowBatteryCloseWarningBump);
            //关机电池温度
164         mShutdownBatteryTemperature = mContext.getResources().getInteger(
165                 com.android.internal.R.integer.config_shutdownBatteryTemperature);
166
167         // watch for invalid charger messages if the invalid_charger switch exists
            //  利用UEventObserver监听是否有无效的充电设备
168         if (new File("/sys/devices/virtual/switch/invalid_charger/state").exists()) {
169             UEventObserver invalidChargerObserver = new UEventObserver() {
170                 @Override
171                 public void onUEvent(UEvent event) {                                                                                        
172                     final int invalidCharger = "1".equals(event.get("SWITCH_STATE")) ? 1 : 0;
173                     synchronized (mLock) {
174                         if (mInvalidCharger != invalidCharger) {
175                             mInvalidCharger = invalidCharger;
176                         }
177                     }
178                 }
179             };
                //开始监听
180             invalidChargerObserver.startObserving(
181                     "DEVPATH=/devices/virtual/switch/invalid_charger");
182         }
183     }
```

不妨去看看这些配置信息在AOSP中的设置  
frameworks/base/core/res/res/values/config.xml

```xml
896     <!-- Display low battery warning when battery level dips to this value.
897          Also, the battery stats are flushed to disk when we hit this level.  -->
898     <integer name="config_criticalBatteryWarningLevel">5</integer>                                                                         
899
900     <!-- Shutdown if the battery temperature exceeds (this value * 0.1) Celsius. -->
901     <integer name="config_shutdownBatteryTemperature">680</integer>
902
903     <!-- Display low battery warning when battery level dips to this value -->
904     <integer name="config_lowBatteryWarningLevel">15</integer>
905
906     <!-- Close low battery warning when battery level reaches the lowBatteryWarningLevel
907          plus this -->
908     <integer name="config_lowBatteryCloseWarningBump">5</integer>
```

所以：  

- 5% : Show Warning and Save the data to disk, and close the warning.
- 15% : Show Warning
- 68.0 摄氏度：Shotdown the device

### BS onStart onBootPhase

onStart

- ServiceManager.getService("batteryproperties")
- 创建一个BatteryListener并注册到BatteryPropertiesService中
  - 监听底层的变化，Listener会执行:
    - BatteryService.this.update(props);
    - updateBatteryWarningLevelLocked(false)
- 注册BS到ServiceManager和LocalServices

onBootPhase

- 监听Settings.Global.LOW_POWER_MODE_TRIGGER_LEVEL的变化
  - 一旦有变化执行updateBatteryWarningLevelLocked(true)
- updateBatteryWarningLevelLocked();
  - 更新 mLowBatteryWarningLevel mCriticalBatteryLevel mLowBatteryCloseWarningLevel
  - processValuesLocked(true)：根据update()函数获得的mBatteryProps更新电池信息，发送广播。
    - 设置mBatteryLevelCritical
    - 设置mPlugType（充电类型）
    - mBatteryStats.setBatteryState
    - 发送广播
    - 更新很多很多类变量

## batteryproperties服务

前面看到，BS在onStart的时候获得batteryproperties服务，并向其注册一个BatteryListener。一旦底层电池信息有变化，将通过这个Binder通知BS，BS随即更新自己的信息、也保存到BatteryStatsService中，并发送广播。

那么，这个batteryproperties服务是如何知道电池信息有变，又是如何获得这些信息的呢？

### batteryproperties服务的创建

system/core/healthd/healthd.cpp  
system/core/healthd/BatteryPropertiesRegistrar.cpp

init.rc中启动服务

```
619 service healthd /sbin/healthd                                                                                                               
620     class core
621     critical
622     seclabel u:r:healthd:s0
623     group root system wakelock
```

### batteryproperties的注册

healthd_mode_android_init:

```
60     gBatteryPropertiesRegistrar = new BatteryPropertiesRegistrar();
61     gBatteryPropertiesRegistrar->publish(gBatteryPropertiesRegistrar);
```

### batteryproperties的listener通知

```c
32 void healthd_mode_android_battery_update(
33     struct android::BatteryProperties *props) {
34     if (gBatteryPropertiesRegistrar != NULL)
35         gBatteryPropertiesRegistrar->notifyListeners(*props);
36
37     return;
38 }
```

### batteryproperties获得电量信息

BatteryMonitor::init中while读取`/sys/class/power_supply/*`中的内容。

```                                                                                                     
ls: sys/class/power_supply//ac: Permission denied
ls: sys/class/power_supply//usb: Permission denied
ls: sys/class/power_supply//wireless: Permission denied
ls: sys/class/power_supply//battery: Permission denied
```

供电类型ac/usb/wireless：读取子目录下的 online
供电类型/battery，获取里面的详细信息，例如：health/status/capacity等等

### batteryproperties小结

从这里可以看到，batteryproperties服务是在cpp中创建的，在init.rc中启动。它负责往listener中传递电池信息props（数据串行化）。  
batteryproperties需要与PMU驱动进行交互，交互方式就是读取设备文件/sys/class/power_supply/*。 

## 参考文献

[Android UEventObserver](http://blog.csdn.net/darkengine/article/details/7442359)    
[Android6.0 healthd深入分析](http://blog.csdn.net/u011311586/article/details/51082685)  
[Android PMU 驱动](http://blog.csdn.net/wantianpei/article/details/8850454)  
