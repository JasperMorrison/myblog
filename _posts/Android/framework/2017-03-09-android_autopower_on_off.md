---
layout: post
title: "Android MTK auto power on & off And DeskClock app"
categories: Android-Framework
tags: Android Framework AutoPowerOn&Off DeskClock
author: Jasper
---

* content
{:toc}

本文记录了MTK 中，对FrameWork是如何实现自动开关机和关机闹钟的分析过程。



## Setting

### MTK

Settings App -> "Scheduled power on & off" -> set time you want

### AOSP

I do not find any setting about schedule power on & off. I think this feature is based on the hardware CPU, so it is the thing in vender.

## Code 

Code is based on MTK Android6.0

### res xml

Settings/res/xml/dashboard_categories.xml

```xml
241         <!--Scheduled power on&off-->
242         <dashboard-tile
243                 android:id="@+id/power_settings"
244                 android:icon="@drawable/ic_settings_schpwronoff"
245                 android:title="@string/schedule_power_on_off_settings_title">
246             <intent android:action="com.android.settings.SCHEDULE_POWER_ON_OFF_SETTING" />
247         </dashboard-tile>
```

Normally, in dashboard-tile, there is a fragment, but this not. Now we should lookfor it in the source code.  

### Settings

SettingsActiviry->buildDashboardCategories->updateTilesList->

```java
1364                 } else if (id == R.id.power_settings) { /// M: { @ Schedule power on/off
			// This intent string was defined within the same dashboard-tile in dashboard_categories.xml 
1365                     Intent intent = new Intent(
1366                         "com.android.settings.SCHEDULE_POWER_ON_OFF_SETTING");
1367                     List<ResolveInfo> apps = getPackageManager()
1368                             .queryIntentActivities(intent, 0);
1369                     if (apps != null && apps.size() != 0) {
1370                         Log.d(LOG_TAG, "apps.size()=" + apps.size());
				// Check for the user
1371                         if (UserHandle.myUserId() != UserHandle.USER_OWNER) {
1372                             category.removeTile(n);
1373                         }
1374                     } else {
1375                         Log.d(LOG_TAG, "apps is null or app size is 0, remove SchedulePowerOnOff");
1376                         category.removeTile(n);
1377                     } /// M: @}
```

From above, we only know about when and where to add the category items in Settings view. But do not know any about the onclick listener. New step, find the onclick listener. But a faster way to find the class of this intent is using cmd pm in the adb shell, as below:

```
1|shell@ac60pl:/ $ dumpsys window | grep Focus
    mFocusedWindow=Window{d826028 u0 com.mediatek.schpwronoff/com.mediatek.schpwronoff.AlarmClock}
    mFocusedApp=Token{dba7fba ActivityRecord{3b5c8e5 u0 com.mediatek.schpwronoff/.AlarmClock t25}}
  mCurrentFocus=Window{d826028 u0 com.mediatek.schpwronoff/com.mediatek.schpwronoff.AlarmClock}
  mFocusedApp=AppWindowToken{fd4c12 token=Token{dba7fba ActivityRecord{3b5c8e5 u0 com.mediatek.schpwronoff/.AlarmClock t25}}}
```

Use the package to find the apk: 

```
shell@ac60pl:/ $ pm list packages -f | grep com.mediatek.schpwronoff
package:/system/app/SchedulePowerOnOff/SchedulePowerOnOff.apk=com.mediatek.schpwronoff
```

### SchedulePowerOnOff app

Where is the apk?  
vendor/mediatek/proprietary/packages/apps/SchedulePowerOnOff

We find the Activity according the intent.

```
 14         <activity android:name="com.mediatek.schpwronoff.AlarmClock"
 15                 android:label="@string/schedule_power_on_off_settings_title"
 16                 android:configChanges="orientation|keyboardHidden|keyboard|navigation">
 17             <intent-filter>
 18                 <action android:name="android.intent.action.MAIN" />
 19                 <action android:name="com.android.settings.SCHEDULE_POWER_ON_OFF_SETTING" />
 20                 <category android:name="android.intent.category.DEFAULT" />
 21             </intent-filter>
 22         </activity>
```

com.mediatek.schpwronoff.AlarmClock is the Activity we first found. But what is our purpose? Find the time setting to auto power on & off!

As the code shows, the main view of AlarmClock Activity is a list. It's listener function:  

```java
184     @Override
185     public void onCreate(Bundle icicle) {
186         super.onCreate(icicle);
187         String[] ampm = new DateFormatSymbols().getAmPmStrings();
188         mAm = ampm[0];
189         mPm = ampm[1];
190         mFactory = LayoutInflater.from(this);
191         mCursor = Alarms.getAlarmsCursor(this.getContentResolver());
192         Log.d("@M_" + TAG, "mCursor.getCount() " + mCursor.getCount());
193 
194         //add which is in onCreateView()
195         View v = mFactory.inflate(R.layout.schpwr_alarm_clock, null);
196         setContentView(v);
197         mAlarmsList = (ListView) v.findViewById(android.R.id.list);
198         if (mAlarmsList != null) {
		// Here is the ListView Adapter
199             mAlarmsList.setAdapter(new AlarmTimeAdapter(this, mCursor)); 
200             mAlarmsList.setVerticalScrollBarEnabled(true);
201             mAlarmsList.setOnItemClickListener(this);
202             mAlarmsList.setOnCreateContextMenuListener(this);
203         }
204         registerForContextMenu(mAlarmsList);
205     }
```

Goto this Adapter.

```java
 94     private class AlarmTimeAdapter extends CursorAdapter {
 95         public AlarmTimeAdapter(Context context, Cursor cursor) {
 96             super(context, cursor);
 97         }
113         @Override
114         public void bindView(View view, Context context, Cursor cursor) {
115             Log.d("@M_" + TAG, "bindView");
116             final Alarm alarm = new Alarm(cursor);
117             final Context cont = context;
118             Switch onButton = (Switch) view.findViewById(R.id.alarmButton);
119             if (onButton != null) {
120                 mUserCheckedFlag = false;
121                 onButton.setChecked(alarm.mEnabled);
122                 mUserCheckedFlag = true;
			// Switch listener, our main function.
123                 onButton.setOnCheckedChangeListener(new OnCheckedChangeListener() {
124                     @Override
125                     public void onCheckedChanged(CompoundButton buttonView, boolean isChecked) {
				// Enable/Disable Alarm
131                         Alarms.enableAlarm(cont, alarm.mId, isChecked);
132                         if (isChecked) {
				// Show the time in Toast to the user.
133                             SetAlarm.popAlarmSetToast(cont, alarm.mHour, alarm.mMinutes, alarm.mDaysOfWeek, alarm.mId);
134                         }
135                     }
136                 });
137             }
```

#### How to set time

Main function as `Alarms.enableAlarm(cont, alarm.mId, isChecked);`

Firstly think about the Auto power off, it is easy, using AOSP AlarmManager RTC_WAKEUP can do it.  
Secondly think about the Auto power on, it is based on the CPU, here is MTK's CPU. So, we should care about the funciton.

```java
383     /**
384      * Sets alert in AlarmManger and StatusBar. This is what will actually launch the alert when the alarm triggers.
385      *
386      * @param alarm
387      *            Alarm.
388      * @param atTimeInMillis
389      *            milliseconds since epoch
390      */
391     private static void enableAlertPowerOn(Context context, final Alarm alarm,
392             final long atTimeInMillis) {
393         Log.d("@M_" + TAG, "** setAlert id " + alarm.mId + " atTime " + atTimeInMillis);
394         AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
395         Intent intent = new Intent(context, com.mediatek.schpwronoff.SchPwrOnReceiver.class);
396         Parcel out = Parcel.obtain();
397         alarm.writeToParcel(out, 0);
398         out.setDataPosition(0);
399         intent.putExtra(ALARM_RAW_DATA, out.marshall());
400         PendingIntent sender = PendingIntent.getBroadcast(context, 0, intent,
401                 PendingIntent.FLAG_CANCEL_CURRENT);
		// Look here, it is not the RTC_WAKEUP, but number 7, MTK add it? 
		// RTC_WAKEUP(number 0) function look like :
		// am.setExact(AlarmManager.RTC_WAKEUP, atTimeInMillis, sender); 
402         am.setExact(7, atTimeInMillis, sender);
403         Calendar c = Calendar.getInstance();
404         c.setTime(new java.util.Date(atTimeInMillis));
405         Log.d("@M_" + TAG, "Alarms.enableAlertPowerOn(): setAlert id " + alarm.mId + " atTime "
406                 + c.getTime());
407     }
```

### AlarmManger MTK doing

According to `import android.app.AlarmManager`, found the java file of AlarmManager, `frameworks/base/core/java/android/app/AlarmManager.java`

```java
406     public void setExact(int type, long triggerAtMillis, PendingIntent operation) {
407         setImpl(type, triggerAtMillis, WINDOW_EXACT, 0, 0, operation, null, null);
408     }
```

```java
455     private void setImpl(int type, long triggerAtMillis, long windowMillis, long intervalMillis,
456             int flags, PendingIntent operation, WorkSource workSource, AlarmClockInfo alarmClock) {
457         if (triggerAtMillis < 0) {
458             /* NOTYET
459             if (mAlwaysExact) {
460                 // Fatal error for KLP+ apps to use negative trigger times
461                 throw new IllegalArgumentException("Invalid alarm trigger time "
462                         + triggerAtMillis);
463             }
464             */
465             triggerAtMillis = 0;
466         }
467 
468         try {
		// We come into the associate service
469             mService.set(type, triggerAtMillis, windowMillis, intervalMillis, flags, operation,
470                     workSource, alarmClock);
471         } catch (RemoteException ex) {
472         }
473     }
```

From the Android boot process, in SystemServer.java we can find the Alarm Service.  
Now go into the service stub, look for the set() function.

```java
1318     private final IBinder mService = new IAlarmManager.Stub() {
1319         @Override
1320         public void set(int type, long triggerAtTime, long windowLength, long interval, int flags,
1321                 PendingIntent operation, WorkSource workSource,
1322                 AlarmManager.AlarmClockInfo alarmClock) {
1323             final int callingUid = Binder.getCallingUid();
		// we just care about it, type == 7 
1360             setImpl(type, triggerAtTime, windowLength, interval, operation,
1361                     flags, workSource, alarmClock, callingUid);
1362         }
```

```java
1081     void setImpl(int type, long triggerAtTime, long windowLength, long interval,
1082             PendingIntent operation, int flags, WorkSource workSource,
1083             AlarmManager.AlarmClockInfo alarmClock, int callingUid) {
1125         // /M:add for PowerOffAlarm feature type 7 for seetings,type 8 for
1126         // deskcolck ,@{
1127         if (type == 7 || type == 8) {
1128             if (mNativeData == -1) {
1129                 Slog.w(TAG, "alarm driver not open ,return!");
1130                 return;
1131             }
1132 
1133             Slog.d(TAG, "alarm set type 7 8, package name " + operation.getTargetPackage());
1134             String packageName = operation.getTargetPackage();
1135 
1136             String setPackageName = null;
1137             long nowTime = System.currentTimeMillis();
1138             if (triggerAtTime < nowTime) {
1139                 Slog.w(TAG, "power off alarm set time is wrong! nowTime = " + nowTime + " ; triggerAtTime = " + triggerAtTime);
1140                 return;
1141             }
		// set 
1143             synchronized (mPowerOffAlarmLock) {
1144                 removePoweroffAlarmLocked(operation.getTargetPackage());
1145                 final int poweroffAlarmUserId = UserHandle.getCallingUserId();
1146                 Alarm alarm = new Alarm(type, triggerAtTime, 0, 0, 0,
1147                         interval,operation, workSource, 0, alarmClock,
1148                         poweroffAlarmUserId, true);
1149                 addPoweroffAlarmLocked(alarm);
1150                 if (mPoweroffAlarms.size() > 0) {
1151                     resetPoweroffAlarm(mPoweroffAlarms.get(0));
1152                 }
1153             }
1154             type = RTC_WAKEUP;
1155 
1156         }
```

### Conclusion

I do not care about how the C/C++ level how to do it, now we know number 7 for auto power on, number 8 for deskcolck in Power off status.

And in packages/app/DeskClock we must can find the function setExact adn number 8.

```
➜  DeskClock grep -Rn setExact src
src/com/android/deskclock/alarms/AlarmStateManager.java:1059:                am.setExact(AlarmManager.RTC_WAKEUP, timeInMillis, pendingIntent);
src/com/android/deskclock/alarms/AlarmStateManager.java:1145:                am.setExact(POWER_OFF_WAKE_UP, timeInMillis, pendingIntent);
src/com/android/deskclock/timer/TimerReceiver.java:269:                mngr.setExact(AlarmManager.ELAPSED_REALTIME_WAKEUP, nextTimesup, p);
src/com/android/deskclock/timer/TimerReceiver.java:369:            alarmManager.setExact(AlarmManager.ELAPSED_REALTIME, nextBroadcastTime, pendingNextBroadcast);
src/com/android/deskclock/DeskClockBackupAgent.java:111:        alarmManager.setExact(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAtMillis, restoreIntent);
src/com/android/alarmclock/DigitalAppWidgetProvider.java:256:                alarmManager.setExact(AlarmManager.RTC, onQuarterHour, quarterlyIntent);

➜  DeskClock grep -Rn POWER_OFF_WAKE_UP src 
src/com/android/deskclock/alarms/AlarmStateManager.java:142:    public static final int POWER_OFF_WAKE_UP = 8;
src/com/android/deskclock/alarms/AlarmStateManager.java:1145:                am.setExact(POWER_OFF_WAKE_UP, timeInMillis, pendingIntent);
src/com/android/deskclock/alarms/AlarmStateManager.java:1147:                am.set(POWER_OFF_WAKE_UP, timeInMillis, pendingIntent);
```



