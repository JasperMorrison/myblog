---
layout: post
title: Android BatteryStatsService
categories: Android-Framework
tags: Android Battery
author: Jasper
---

* content
{:toc}

从[Android BatteryService](/2017/04/18/Android-BatteryService/#bsbss的启动)中可以知道，BatteryStatusService（同样的，后面简称BSS）是在AMS中启动的，并读取一个保存电池信息的文件，设置Handler。这里分析BSS与AMS的密切关系，分析进程耗电统计。



## 深入BSS的启动

### AMS启动BSS

```java
        // TODO: Move creation of battery stats service outside of activity manager service.
        File dataDir = Environment.getDataDirectory();
        File systemDir = new File(dataDir, "system");
	// /data/system
        systemDir.mkdirs();
	//AMS创建一个线程给到BSS，BSS可以往线程中发送消息
	//mHandler = new MainHandler(mHandlerThread.getLooper());
	//见到下一小节对BSS构造函数的说明
        mBatteryStatsService = new BatteryStatsService(systemDir, mHandler);
	//利用刚创建的BatteryStatsImpl，调用其readLocked()
	//1 解析batterystats-daily.xml，记录第三方apk的信息，还不知道这些信息有什么用
	//  把信息保存到一个mDailyItems，这是一个DailyItems的数组
	//2 解析batterystats.bin
	//  得到一大波，系统时间、电池信息、屏幕点亮时间、网络使用时间等等
        mBatteryStatsService.getActiveStatistics().readLocked();
	//更新信息到磁盘
	//具体做法是：发送msg(BatteryStatsHandler.MSG_WRITE_TO_DISK)给BSS：
	// BSS - updateExternalStatsSync 更新外部设备耗电信息，如CPU/RADIO/WIFI/BT
	//	远程调用，利用Parcel对象返回信息，异步获取，可能会超时
	// BSI - writeAsyncLocked 写入磁盘
        mBatteryStatsService.scheduleWriteToDisk();
	//是不是应该打开debug功能
        mOnBattery = DEBUG_POWER ? true
                : mBatteryStatsService.getActiveStatistics().getIsOnBattery();
	//设置AMS为BSS的回调对象
        mBatteryStatsService.getActiveStatistics().setCallback(this);
```

### BSS的构造函数

```java
    BatteryStatsService(File systemDir, Handler handler) {
        // Our handler here will be accessing the disk, use a different thread than
        // what the ActivityManagerService gave us (no I/O on that one!).
	// BSS也创建一个工作线程，并把Looper给到BatteryStatsHandler
	// 如果使用Handler的post方式，执行一个runable对象，msg.target被设置为callback
        final ServiceThread thread = new ServiceThread("batterystats-sync",
                Process.THREAD_PRIORITY_DEFAULT, true);
        thread.start();//执行HandlerThread的run(): Looper.prepare()/Looper.loop()
	//Handler，给定新的Looper，否则使用当前线程的Looper.
        mHandler = new BatteryStatsHandler(thread.getLooper());
	//上面的内容告诉我们：
	//mHandler.post中的Runable是在一个ServiceThread执行的，而不是当前线程。
	//这样的逻辑就是：创建一个工作，当有需要的时候，让它在别的线程中执行。

        // BatteryStatsImpl expects the ActivityManagerService handler, so pass that one through.
	//创建一个BatteryStatsImpl(BSI)，它可以往AMS和BSS发送消息
        mStats = new BatteryStatsImpl(systemDir, handler, mHandler, this);
    }
```

### BSI的构造函数

```java
    public BatteryStatsImpl(File systemDir, Handler handler, ExternalStatsSync externalSync,
                            PlatformIdleStateCallback cb) {
        this(new SystemClocks(), systemDir, handler, externalSync, cb);
    }

    public BatteryStatsImpl(Clocks clocks, File systemDir, Handler handler,
            ExternalStatsSync externalSync, PlatformIdleStateCallback cb) {
	//与移动网络和wifi网络相关
        init(clocks);

	//创建/data/system/batterystats.bin
        if (systemDir != null) {
            mFile = new JournaledFile(new File(systemDir, "batterystats.bin"),
                    new File(systemDir, "batterystats.bin.tmp"));
        } else {
            mFile = null;
        }
	//创建batterystats-checkin.bin batterystats-daily.xml
        mCheckinFile = new AtomicFile(new File(systemDir, "batterystats-checkin.bin"));
        mDailyFile = new AtomicFile(new File(systemDir, "batterystats-daily.xml"));
	//BSS的Handler
        mExternalSync = externalSync;
	//BSI的Handler
        mHandler = new MyHandler(handler.getLooper());
        mStartCount++;
        //一大批的StopwatchTimer和LongSamplingCounter，略。。。

        //初始化两个变量
        mOnBattery = mOnBatteryInternal = false;
	//记录系统时间
        long uptime = mClocks.uptimeMillis() * 1000;
        long realtime = mClocks.elapsedRealtime() * 1000;
        initTimes(uptime, realtime);

	//ro.build.id属性
        mStartPlatformVersion = mEndPlatformVersion = Build.ID;

        //各种时间、Trace等初始化

	//BSS对象
        mPlatformIdleStateCallback = cb;
    }
```

## BSS setBatteryState

从另一篇文章[Android-BatteryService](/2017/04/18/Android-BatteryService/#bs-onstart-onbootphase)中可以看到，当底层电池信息发生改变时，会回调BS中设定的listerner，然后BS会通知BSS，通知方法就是通过setBatteryState.

BS的onStart方法设置listerner - updateBatteryWarningLevelLocked(false)
BS的onBootPhase - 监听Settings.Global.LOW_POWER_MODE_TRIGGER_LEVEL的变化 - 一旦有变化执行updateBatteryWarningLevelLocked(true)

```java
    @Override
    public void setBatteryState(final int status, final int health, final int plugType,
            final int level, final int temp, final int volt, final int chargeUAh) {
        //非阻塞处理电池状态
        mHandler.post(new Runnable() {
            @Override
            public void run() {
                synchronized (mStats) {
                    //充电状态没有发生切换
                        mStats.setBatteryStateLocked(status, health, plugType, level, temp, volt,
                                chargeUAh);
                        return;
                    }
                }

                //先同步一下外部耗电设备，WIFI/BT/MODEM（MODEM：电话、短信、移动网络）		
                updateExternalStatsSync("battery-state", BatteryStatsImpl.ExternalStatsSync.UPDATE_ALL);

		//充电状态已经切换
                synchronized (mStats) {
                    mStats.setBatteryStateLocked(status, health, plugType, level, temp, volt,
                            chargeUAh);
                }
            }
        });
    }
```

### setBatteryStateLocked

```java
    public void setBatteryStateLocked(int status, int health, int plugType, int level,
            int temp, int volt, int chargeUAh) {
        final boolean onBattery = plugType == BATTERY_PLUGGED_NONE;
        final long uptime = mClocks.uptimeMillis();//非休眠时长
        final long elapsedRealtime = mClocks.elapsedRealtime();//启动时长
        if (!mHaveBatteryLevel) {
		//mHaveBatteryLevel默认为false，表示首次得到电池信息
            mHaveBatteryLevel = true;
            // We start out assuming that the device is plugged in (not
            // on battery).  If our first report is now that we are indeed
            // plugged in, then twiddle our state to correctly reflect that
            // since we won't be going through the full setOnBattery().
            if (onBattery == mOnBattery) {//充电状态没有切换
                if (onBattery) {//电池供电
                    mHistoryCur.states &= ~HistoryItem.STATE_BATTERY_PLUGGED_FLAG;
                } else {//充电中
                    mHistoryCur.states |= HistoryItem.STATE_BATTERY_PLUGGED_FLAG;
                }
            }
            // Always start out assuming charging, that will be updated later.
            mHistoryCur.states2 |= HistoryItem.STATE2_CHARGING_FLAG;
            mHistoryCur.batteryStatus = (byte)status;
            mHistoryCur.batteryLevel = (byte)level;
            mHistoryCur.batteryChargeUAh = chargeUAh;
            mMaxChargeStepLevel = mMinDischargeStepLevel =
                    mLastChargeStepLevel = mLastDischargeStepLevel = level;
            mLastChargingStateLevel = level;
        } else if (mCurrentBatteryLevel != level || mOnBattery != onBattery) {
		//电量发生变化或者充电状态切换
		//记录日常电池信息
            recordDailyStatsIfNeededLocked(level >= 100 && onBattery);
        }
        int oldStatus = mHistoryCur.batteryStatus;

	//下面记录一条历史信息
        if (onBattery) {
            mDischargeCurrentLevel = level;
            if (!mRecordingHistory) {
                mRecordingHistory = true;
                startRecordingHistory(elapsedRealtime, uptime, true);
            }
        } else if (level < 96) {
            if (!mRecordingHistory) {
                mRecordingHistory = true;
                startRecordingHistory(elapsedRealtime, uptime, true);
            }
        }


        mCurrentBatteryLevel = level;
        if (mDischargePlugLevel < 0) {
            mDischargePlugLevel = level;
        }

        if (onBattery != mOnBattery) {//如果状态切换
            mHistoryCur.batteryLevel = (byte)level;
            mHistoryCur.batteryStatus = (byte)status;
            mHistoryCur.batteryHealth = (byte)health;
            mHistoryCur.batteryPlugType = (byte)plugType;
            mHistoryCur.batteryTemperature = (short)temp;
            mHistoryCur.batteryVoltage = (char)volt;
		//电池的实时电量，当变小时，说明电池在放电
		//这里就是统计放电
            if (chargeUAh < mHistoryCur.batteryChargeUAh) {
                // Only record discharges
                final long chargeDiff = mHistoryCur.batteryChargeUAh - chargeUAh;
                mDischargeCounter.addCountLocked(chargeDiff);
                mDischargeScreenOffCounter.addCountLocked(chargeDiff);
            }
		//更新电量
            mHistoryCur.batteryChargeUAh = chargeUAh;
		//设置电池信息
            setOnBatteryLocked(elapsedRealtime, uptime, onBattery, oldStatus, level, chargeUAh);
        } else {//状态切换
		//记录变化信息
            boolean changed = false;		

           	//略

            if (changed) {
		//添加记录
		//如果在电量统计的间隔中，休眠时间超过20mS，则记录一个tmp信息
		//记录一个实时信息
		//暂时还不知道tmp信息有什么用，至少知道它标志为非CPU活动，没有wakelock。
                addHistoryRecordLocked(elapsedRealtime, uptime);
            }
        }
    }
```

先熟悉到这里吧，具体到AMS/PMS中再回来分析各种相关函数。

## 参考文献

[Android7.0 BatteryStatsService](http://blog.csdn.net/gaugamela/article/details/52931949)  
