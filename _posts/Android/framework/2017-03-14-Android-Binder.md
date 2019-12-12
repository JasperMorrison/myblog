---
layout: post
title: "Android Binder"
categories: "Android-Framework"
tags: Android Binder
author: Jasper
---

* content
{:toc}

本文熟悉Binder在Android层面的工作原理和调用过程，并自己尝试使用Binder进行进程间通信。



## Binder interface & class

先来两张网络图大概理解一下Binder类及Binder通信的相互关系。

![](http://image4.it168.com/2009/3/31/d0cb7475-69bf-41b2-9c40-49ccd452271e.jpg)  
![](http://image4.it168.com/2009/3/31/cee9d5f9-6e9c-421c-8cab-00ac192c33ac.jpg)

frameworks/base/core/java/android/os/IBinder.java  
frameworks/base/core/java/android/os/Binder.java

From the source code of Binder and Google website in Reference, we should know the work way of a Binder between two processes.

Three interfaces of IBinder we should know:

- transact(): Binder通用操作， 参数 code 代表了需要执行的动作，在Binder驱动中知道，这个code是传递给service_manager的。  
	参数 data 代表了一个需要传递给另一个进程的Parcel对象。参数reply代表返回的Parcel对象。
- pingBinder(): ping一下对方还活着吗。
- linkToDeath(): 如果对方death的话，系统会告诉你，人家挂了，你死心吧。

### Binder.java

Binder是实现IBinder接口的标准类，多数开发者不会直接使用Binder，而是使用AIDL来实现进程间通信。当然，我们也可以implement Binder或者直接创建一个Binder的对象来实现进程间通信。Binder只是一个基本的IPC原型，不包含在app的生命周期中，只会在创建它的app在运行的时候有效。Binder只需依托以特定的组件上下文才能操作，比如Activity、Service或者ContentProvider。

```java
254     public Binder() {
	//private native final void init();
255         init(); 
265     }
```

frameworks/base/core/jni/android_util_Binder.cpp

```c
 808 static void android_os_Binder_init(JNIEnv* env, jobject obj)
 809 {
	// 只是new一个Holder对象，并没有创建JavaBBinder对象。
	// 直到调用JavaBBinderHolder 的 get()函数
	// class JavaBBinder : public BBinder
 810     JavaBBinderHolder* jbh = new JavaBBinderHolder();
 818 }
```

```java
    final class BinderProxy implements IBinder { 
612     public boolean transact(int code, Parcel data, Parcel reply, int flags) throws RemoteException {
615         return transactNative(code, data, reply, flags);
616     }
617 

670     BinderProxy() {
671         mSelf = new WeakReference(this);
672     }
    }
```

transactNative()

```c
1093 static jboolean android_os_BinderProxy_transact(JNIEnv* env, jobject obj,
1094         jint code, jobject dataObj, jobject replyObj, jint flags) // throws RemoteException
1095 {
1101     Parcel* data = parcelForJavaObject(env, dataObj);

1105     Parcel* reply = parcelForJavaObject(env, replyObj);

	// 从这里可以看出，对于一个proxy，target(stub)是保存在mObject中。
1110     IBinder* target = (IBinder*) 
1111         env->GetLongField(obj, gBinderProxyOffsets.mObject);

1133     //printf("Transact from Java code to %p sending: ", target); data->print();
1134     status_t err = target->transact(code, *data, reply, flags);
```

```c
  95 static struct binderproxy_offsets_t
  96 {
  97     // Class state.
  98     jclass mClass;
  99     jmethodID mConstructor;
 100     jmethodID mSendDeathNotice;
 101 
 102     // Object state.
 103     jfieldID mObject;
 104     jfieldID mSelf;
 105     jfieldID mOrgue;
 106 
 107 } gBinderProxyOffsets;
```

### Binder相关方法的注册过程

frameworks/base/core/jni/AndroidRuntime.cpp

```c
54 extern int register_android_os_Binder(JNIEnv* env);
1280 REG_JNI(register_android_os_Binder),
```

以上内容的解释参考[Android DVM JNI Reg](/2017/03/12/Android-DVM-JNI-Reg)

回到android_util_Binder.cpp

下面的类似int_regitster_android_os_*(env)的函数，都会调用到RegisterMethodsOrDie()，间接的调用到env->RegisterNatives(clazz, gMethods, numMethods)。  
正如参考文献中提到，这是JNI的动态注册过程。

```c
1297int register_android_os_Binder(JNIEnv* env)
1298{
1299    if (int_register_android_os_Binder(env) < 0)
1300        return -1;
1301    if (int_register_android_os_BinderInternal(env) < 0)
1302        return -1;
1303    if (int_register_android_os_BinderProxy(env) < 0)
1304        return -1;
1305
1306    jclass clazz = FindClassOrDie(env, "android/util/Log");
1307    gLogOffsets.mClass = MakeGlobalRefOrDie(env, clazz);
1308    gLogOffsets.mLogE = GetStaticMethodIDOrDie(env, clazz, "e",
1309            "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)I");
1310
1311    clazz = FindClassOrDie(env, "android/os/ParcelFileDescriptor");
1312    gParcelFileDescriptorOffsets.mClass = MakeGlobalRefOrDie(env, clazz);
1313    gParcelFileDescriptorOffsets.mConstructor = GetMethodIDOrDie(env, clazz, "<init>",
1314                                                                 "(Ljava/io/FileDescriptor;)V");
1315
1316    clazz = FindClassOrDie(env, "android/os/StrictMode");
1317    gStrictModeCallbackOffsets.mClass = MakeGlobalRefOrDie(env, clazz);
1318    gStrictModeCallbackOffsets.mCallback = GetStaticMethodIDOrDie(env, clazz,
1319            "onBinderStrictModePolicyChange", "(I)V");
1320
1321    return 0;
1322}
```

Binder类方法是怎么注册的？

```c
860const char* const kBinderPathName = "android/os/Binder";
861
862static int int_register_android_os_Binder(JNIEnv* env)
863{
864    jclass clazz = FindClassOrDie(env, kBinderPathName);
865
866    gBinderOffsets.mClass = MakeGlobalRefOrDie(env, clazz);
867    gBinderOffsets.mExecTransact = GetMethodIDOrDie(env, clazz, "execTransact", "(IJJI)Z");
868    gBinderOffsets.mObject = GetFieldIDOrDie(env, clazz, "mObject", "J");
869
870    return RegisterMethodsOrDie(
871        env, kBinderPathName,
872        gBinderMethods, NELEM(gBinderMethods));
873}
```

BinderProxy类方法是怎么注册的？

```c
1267const char* const kBinderProxyPathName = "android/os/BinderProxy";
1268
1269static int int_register_android_os_BinderProxy(JNIEnv* env)
1270{
1271    jclass clazz = FindClassOrDie(env, "java/lang/Error");
1272    gErrorOffsets.mClass = MakeGlobalRefOrDie(env, clazz);
1273
1274    clazz = FindClassOrDie(env, kBinderProxyPathName);
1275    gBinderProxyOffsets.mClass = MakeGlobalRefOrDie(env, clazz);
1276    gBinderProxyOffsets.mConstructor = GetMethodIDOrDie(env, clazz, "<init>", "()V");
1277    gBinderProxyOffsets.mSendDeathNotice = GetStaticMethodIDOrDie(env, clazz, "sendDeathNotice",
1278            "(Landroid/os/IBinder$DeathRecipient;)V");
1279
1280    gBinderProxyOffsets.mObject = GetFieldIDOrDie(env, clazz, "mObject", "J");
1281    gBinderProxyOffsets.mSelf = GetFieldIDOrDie(env, clazz, "mSelf",
1282                                                "Ljava/lang/ref/WeakReference;");
1283    gBinderProxyOffsets.mOrgue = GetFieldIDOrDie(env, clazz, "mOrgue", "J");
1284
1285    clazz = FindClassOrDie(env, "java/lang/Class");
1286    gClassOffsets.mGetName = GetMethodIDOrDie(env, clazz, "getName", "()Ljava/lang/String;");
1287
1288    return RegisterMethodsOrDie(
1289        env, kBinderProxyPathName,
1290        gBinderProxyMethods, NELEM(gBinderProxyMethods));
1291}
```

BinderInternal类方法是怎么注册的？

```c
943const char* const kBinderInternalPathName = "com/android/internal/os/BinderInternal";
944
945static int int_register_android_os_BinderInternal(JNIEnv* env)
946{
947    jclass clazz = FindClassOrDie(env, kBinderInternalPathName);
948
949    gBinderInternalOffsets.mClass = MakeGlobalRefOrDie(env, clazz);
950    gBinderInternalOffsets.mForceGc = GetStaticMethodIDOrDie(env, clazz, "forceBinderGc", "()V");
951
952    return RegisterMethodsOrDie(
953        env, kBinderInternalPathName,
954        gBinderInternalMethods, NELEM(gBinderInternalMethods));
955}
```

从上面的几个JNI方法的过程可以发现，Android DVM在启动的时候，动态注册了Binder相关类的相关JNI方法，动态注册的优点是可以对JNI方法的直接引用，而不是在调用的时候按照JNI规则重新检索。

### Binder 对象是何时创建的？

这里列举三种情况。

第一种情况：SM

对于service_manager，它很特殊，并不需要一个Binder对象，在binder驱动被第一次打开的时候，已经设置binder的mgr，第一个binder节点号0.凡是打算与SM通信来getService/addService，都是通过0号binder节点获得的。

第二种情况：service

对于service的情况，system_server进程在系统启动过程中创建了很多service，这些service就是继承了Binder类的Binder实体。在ServiceManager.addService()调用过程中添加到SM中。

第三种情况：app process

对于这种情况，应当了解AMS是如何创建一个app的。

- AMS - onTransact() - super.onTransact()
- AMN - onTransact() - case START_ACTIVITY_TRANSACTION - startActivity
- AMS - startActivity(@Overide) - startActivityAsUser - mActivityStarter.startActivityMayWait 
- ActivityStarter - startActivityMayWait - startActivityLocked(new ActivityRecord) ...
- AMS - startProcessLocked - Process.start(entryPoint,app.processName, uid, uid, gids, ...); (entryPoint = "android.app.ActivityThread";)
- Process - Zygote - 创建VM，执行android.app.ActivityThread的main()

着重记录一下ActivityThread的main()

```java
6083    public static void main(String[] args) {
6092        Environment.initForCurrentUser();
6093
6101        Process.setArgV0("<pre-initialized>");
6102
6103        Looper.prepareMainLooper();  // 主线程还是需要用这个函数
6104
6105        ActivityThread thread = new ActivityThread();

		// 非系统用false，这里创建BBinder，后面会给出过程。
6106        thread.attach(false);
6107
6108        if (sMainThreadHandler == null) {
		//Handler,只设置一次.(class H extends Handler)
6109            sMainThreadHandler = thread.getHandler(); 
6110        }
6119        Looper.loop(); //进入消息循环
6122    }
```

### Proxy 对象是何时创建的？

这里列举三种情况。

第一种情况：SM  
在IServiceManager的实现类ServiceManager类中，也就是系统初创的时候，会调用下面这个函数来获得，其实是创建system Context对象。  
getIServiceManager() -> asInterface(BinderInternal.getContextObject()) -> new ServiceManagerProxy(obj); -> 最终将一个属于servicemanager进程的BinderProxy设置为mRemote。  
到此，便可以往service_manager进程中添加service或者取得service的句柄。具体参考[Android service_manager](/2017/03/01/android-binder-driver/#service_manager)

第二种情况：AMS  
ActivityManagerNative.getDefault(); 返回AMS的BinderProxy.  
其实这里打算理解getService是如何运作的，因为AMS近期需要分析，就那它来举例。

第三种情况：APP

![](http://gityuan.com/images/process/app_process_ipc.jpg)

这里期望弄明白app process的Binder的创建和交互方法。因为后面的Binder例子会利用到app processes之间的通信。

对于系统Service，可以通过Context的getSystemService获得，可以认为是调用了ServiceManager类的getService方法。  
但是，对于一个app，没有类似getAppBinderProxy这样的方法。或者，可以通过AMS的BinderProxy来间接与App的BBinder通信呢，是否可以从AMS的onTransact()入手呢？

对于 __第一种情况__ ，native层如何获得SM的BinderProxy呢？

```c
 902 static jobject android_os_BinderInternal_getContextObject(JNIEnv* env, jobject clazz)
 903 {
	// new 一个 BpBinder
 904     sp<IBinder> b = ProcessState::self()->getContextObject(NULL);  
	//从下面贴出来的函数详情可知，此函数创建一个BpBinder的Proxy，然后相互包含
 905     return javaObjectForIBinder(env, b); 
 906 }
```

```c
85sp<IBinder> ProcessState::getContextObject(const sp<IBinder>& /*caller*/)
86{
87    return getStrongProxyForHandle(0);
88}

	getStrongProxyForHandle(0)
220            b = new BpBinder(handle);
221            e->binder = b;
222            if (b) e->refs = b->getWeakRefs();
223            result = b;
```

```c
	javaObjectForIBinder(env, b)
	
	//通过JavaBBinder的get()方法获得一个BBinder，BBinder对象由带参get()方法创建
 551     if (val->checkSubclass(&gBinderOffsets)) {
 552         // One of our own!
 553         jobject object = static_cast<JavaBBinder*>(val.get())->object();
 554         LOGDEATH("objectForBinder %p: it's our own %p!\n", val.get(), object);
 555         return object;
 556     }

	//new 一个BinderProxy对象
 576     object = env->NewObject(gBinderProxyOffsets.mClass, gBinderProxyOffsets.mConstructor); 
 577     if (object != NULL) {
 578         LOGDEATH("objectForBinder %p: created new proxy %p !\n", val.get(), object);
 579         // The proxy holds a reference to the native object.
		//设置mObject变量为ProcessState创建的BpBinder
 580         env->SetLongField(object, gBinderProxyOffsets.mObject, (jlong)val.get());
 581         val->incStrong((void*)javaObjectForIBinder); //增加一个引用计数
 582 
 583         // The native object needs to hold a weak reference back to the
 584         // proxy, so we can retrieve the same proxy if it is still active.
		//BpBinder需要获得proxy对象
 585         jobject refObject = env->NewGlobalRef(
 586                 env->GetObjectField(object, gBinderProxyOffsets.mSelf));
 587         val->attachObject(&gBinderProxyOffsets, refObject,
 588                 jnienv_to_javavm(env), proxy_cleanup);
 589 
 590         // Also remember the death recipients registered on this proxy
 591         sp<DeathRecipientList> drl = new DeathRecipientList;
 592         drl->incStrong((void*)javaObjectForIBinder);
 593         env->SetLongField(object, gBinderProxyOffsets.mOrgue, reinterpret_cast<jlong>(drl.get()));
 594 
 595         // Note that a new object reference has been created.
 596         android_atomic_inc(&gNumProxyRefs);
 597         incRefsCreated(env);
 598     }
```

__对于第二种情况__

ActivityManagerNative.getDefault();  
-gDefault.get()  
--IBinder b = ServiceManager.getService("activity");//返回AMS的BinderProxy
--IActivityManager am = asInterface(b); // 返回new ActivityManagerProxy(am)

getService是如何返回BinderProxy的？

frameworks/base/core/java/android/os/ServiceManagerNative.java

```java
118    public IBinder getService(String name) throws RemoteException {
119        Parcel data = Parcel.obtain();
120        Parcel reply = Parcel.obtain();
121        data.writeInterfaceToken(IServiceManager.descriptor);
122        data.writeString(name);
	// 远程调用
123        mRemote.transact(GET_SERVICE_TRANSACTION, data, reply, 0);
124        IBinder binder = reply.readStrongBinder();
125        reply.recycle();
126        data.recycle();
127        return binder;
128    }
```

在onTransact()函数中将IBinder写入reply，返回给Proxy。//这里是没用的方法

```java
52    public boolean onTransact(int code, Parcel data, Parcel reply, int flags)
53    {
54        try {
55            switch (code) {
56            case IServiceManager.GET_SERVICE_TRANSACTION: {
57                data.enforceInterface(IServiceManager.descriptor);
58                String name = data.readString();
		//这里的getService(name)函数实体在哪？		
59                IBinder service = getService(name);
60                reply.writeStrongBinder(service);
61                return true;
62            }
```

先看类定义：  
public abstract class ServiceManagerNative extends Binder implements IServiceManager

一个抽象类里面的onTransact方法怎么可能被执行呢？况且，这个抽象类没有一个子类。所以，这个家伙唯一的用处就是获得ServiceManagerProxy。

那么问题还是存在，这个BBinder子类的onTransact()方法在哪呢？

我也不知道，但是有一种解释是行得通的：  
system_server和AMS中频繁调用ServiceManager.addService(name, binder)这样的函数往service_manager进程添加服务，服务就体现了一个字符串和一个IBinder子类对象的map。当我们getService，当然也是去service_manager中取得这个IBinder子类对象，并将与它所对应的BpBinder返回，最终调用者获得一个包含BpBinder的BinderProxy对象。而现在，service_manager是采用binder_loop轮询binder驱动，哪里还需要什么onTransact函数，svcmgr_handler里面就可以处理addService、getService。所以，上面的onTransact()函数形同虚设。

__对于第三种情况__

正如前面猜想的一样，从AMS的onTransact()入手。

```java
2763    @Override
2764    public boolean onTransact(int code, Parcel data, Parcel reply, int flags)
2765            throws RemoteException {
2766        if (code == SYSPROPS_TRANSACTION) {
2767            // We need to tell all apps about the system property change.
2768            ArrayList<IBinder> procs = new ArrayList<IBinder>();
2769            synchronized(this) {
2770                final int NP = mProcessNames.getMap().size();
2771                for (int ip=0; ip<NP; ip++) {
2772                    SparseArray<ProcessRecord> apps = mProcessNames.getMap().valueAt(ip);
2773                    final int NA = apps.size();
2774                    for (int ia=0; ia<NA; ia++) {
2775                        ProcessRecord app = apps.valueAt(ia);
2776                        if (app.thread != null) {
2777                            procs.add(app.thread.asBinder());
2778                        }
2779                    }
2780                }
2781            }
		//前面内容将所有的app.thread.asBinder() -> BinderProxy(保存在ApplicationThreadProxy)保存到procs中
2782
2783            int N = procs.size();
2784            for (int i=0; i<N; i++) {
2785                Parcel data2 = Parcel.obtain();
2786                try {
			//远程调用
2787                    procs.get(i).transact(IBinder.SYSPROPS_TRANSACTION, data2, null, 0);
2788                } catch (RemoteException e) {
2789                }
2790                data2.recycle();
2791            }
2792        }
2793        try {
2794            return super.onTransact(code, data, reply, flags);
2795        } catch (RuntimeException e) {
2802        }
2803    }
```

看来猜想是错了，除了系统属性发生改变，如语言、屏幕方向等等，才会调用App的BpBinder，严格来说是ApplicationThreadProxy中的BinderProxy对象。

既然没有直接的方法，也不能依赖AMS，有没有其它方法呢？参考这里[Android 进程间通信的几种方式](http://blog.csdn.net/zhuangyalei/article/details/50515039)

__BBinder是何时实例化的？__

上面我们发现，BBinder并没有人去实例化，Binder init()只是创建了一个BBinder的Holder。

其实，在frameworks/base/core/java/android/app/ActivityThread.java中，有一个attach()函数。

```java
5930    private void attach(boolean system) {
5931        sCurrentActivityThread = this;
5932        mSystemThread = system;
5933        if (!system) {  //非系统线程
5934            ViewRootImpl.addFirstDrawHandler(new Runnable() {
5935                @Override
5936                public void run() {
5937                    ensureJitEnabled();
5938                }
5939            });
5940            android.ddm.DdmHandleAppName.setAppName("<pre-initialized>",
5941                                                    UserHandle.myUserId());
5942            RuntimeInit.setApplicationObject(mAppThread.asBinder());
```

frameworks/base/core/jni/android_util_Process.cpp

```c
1041void android_os_Process_setApplicationObject(JNIEnv* env, jobject clazz,
1042                                             jobject binderObject)
1043{
1044    if (binderObject == NULL) {
1045        jniThrowNullPointerException(env, NULL);
1046        return;
1047    }
1048	//这个不正是上面的创建BBinder，获得BinderProxy的函数吗。
	//因为ApplicationThread的asBinder()返回一个this的IBinder引用。
	//又 ApplicationThreadNative继承了Binder类，这里的函数会创建一个BBinder给到binder变量。
1049    sp<IBinder> binder = ibinderForJavaObject(env, binderObject);  
1050}
```

```c
	//这个函数有两个作用，1. 创建BBinder的实例；2.获得BinderProxy的实例。
 603 sp<IBinder> ibinderForJavaObject(JNIEnv* env, jobject obj)
 604 {
 605     if (obj == NULL) return NULL;
 606 
 607     if (env->IsInstanceOf(obj, gBinderOffsets.mClass)) {
 608         JavaBBinderHolder* jbh = (JavaBBinderHolder*)
 609             env->GetLongField(obj, gBinderOffsets.mObject);
 610         return jbh != NULL ? jbh->get(env, obj) : NULL;
 611     }
 612 
 613     if (env->IsInstanceOf(obj, gBinderProxyOffsets.mClass)) {
 614         return (IBinder*)
 615             env->GetLongField(obj, gBinderProxyOffsets.mObject);
 616     }
 617 
 618     ALOGW("ibinderForJavaObject: %p is not a Binder object", obj);
 619     return NULL;
 620 }
```

## App startService

区别于对SystemService的startService.

Context(ContextImpl) - startService - AMS.startService - ActiveServices.startServiceLocked - startServiceInnerLocked - ... -  app.thread.scheduleCreateService - ActivityThread.sendMessage(H.CREATE_SERVICE, s); - handleCreateService

```java
3163    private void handleCreateService(CreateServiceData data) {
3168        LoadedApk packageInfo = getPackageInfoNoCheck(
3169                data.info.applicationInfo, data.compatInfo);
3170        Service service = null;
3171        try {
3172            java.lang.ClassLoader cl = packageInfo.getClassLoader();
3173            service = (Service) cl.loadClass(data.info.name).newInstance();
3174        }
3181
3182        try {
3185            ContextImpl context = ContextImpl.createAppContext(this, packageInfo);
3186            context.setOuterContext(service);
3187		
		// LoadedApk.makeApplication
3188            Application app = packageInfo.makeApplication(false, mInstrumentation);
3189            service.attach(context, this, data.info.name, data.token, app,
3190                    ActivityManagerNative.getDefault()); //保存上下文等相关信息到新建的service
3191            service.onCreate(); // 调用onCreate()
3192            mServices.put(data.token, service);  // 保存当前管理的services，(IBinder,Service)
3199        }
3206    }
```

## bindService

参考老罗的文章[bindService](http://blog.csdn.net/luoshengyang/article/details/6745181)，里面的过程太清晰了。如果没有思考过Binder的设计，还真没耐心浏览下去。

把老罗的话补充一下：

  1. Step 1 -  Step 14，MainActivity调用bindService函数通知ActivityManagerService，它要启动CounterService这个服务，ActivityManagerService于是在MainActivity所在的进程内部把CounterService启动起来，并且调用它的onCreate函数；

  2. Step 15 - Step 21，ActivityManagerService把CounterService启动起来后，继续调用CounterService的onBind函数，要求CounterService返回一个Binder对象给它；（我的补充-Service作为独立进程：这个Binder在C++层被转化为BBinder，AMS通过BBinder获得BpBinder，再将这个BpBinder返回给第3步描述的步骤。）

  3. Step 22 - Step 29，ActivityManagerService从CounterService处得到这个Binder对象后，就把它传给MainActivity，即把这个Binder对象（我的补充-Service作为独立进程：BpBinder）作为参数传递给MainActivity内部定义的ServiceConnection对象的onServiceConnected函数；

  4. Step 30，MainActivity内部定义的ServiceConnection对象的onServiceConnected函数在得到这个Binder对象后，就通过它的getService成同函数获得CounterService接口。（我的补充：asInterface根据返回的是BBinder还是BpBinder决定返回(Interface *)Stub还是new 一个 Proxy）

检索过程类似startService，bindService过程，先创建service，再publish，publish就是利用binder，然后调用ConnectRecord 的 connect方法。  
从字面理解就是，通过binder与service建立实时的联系。

## unbindService

类似startService的检索过程，找到 handleUnbindService(ActivityThread)。

```java
3240    private void handleUnbindService(BindServiceData data) {
3241        Service s = mServices.get(data.token); //获得BinderProxy
3242        if (s != null) {
3243            try {
3244                data.intent.setExtrasClassLoader(s.getClassLoader());
3245                data.intent.prepareToEnterProcess();
3246                boolean doRebind = s.onUnbind(data.intent); //先调用onUnbind
3247                try {
3248                    if (doRebind) {
				//AMS 
				//ActiveService
3249                        ActivityManagerNative.getDefault().unbindFinished(
3250                                data.token, data.intent, doRebind);
3251                    } else {
3252                        ActivityManagerNative.getDefault().serviceDoneExecuting(
3253                                data.token, SERVICE_DONE_EXECUTING_ANON, 0, 0);
3254                    }
3255                } 
3258            } 
3265        }
3266    }
```

## MyOwn Binder Project

下面，我们编写一个App，在App中将不同的两个component设置在不同的进程的运行，然后使用进程间通信接口Binder来实现交互。首先，要实现不同组件在独立进程中运行，需要在AndroidManifest.xml对应的组件中设置android:process属性。	

__android:process__

The name of a process where all components of the application should run. Each component can override this default by setting its own process attribute.  
进程的名称，所有的components都会运行在这个进程中。每一个进程也可以设置自己的进程名称。  
By default, Android creates a process for an application when the first of its components needs to run. All components then run in that process. The name of the default process matches the package name set by the \<manifest\> element.  
默认的，Android系统在app的第一个component需要运行的时候创建一个进程，随后的components对运行在这个进程中，默认进程的名称于manifest元素中的package属性的值相同。  
By setting this attribute to a process name that's shared with another application, you can arrange for components of both applications to run in the same process — but only if the two applications also share a user ID and be signed with the same certificate.  
为不同的app的components的android:process属性设置相同的值可以让它们运行在同一个进程中，前提条件是app的android:sharedUserId属性值一样，并且是使用同样的key进行签名的。  
If the name assigned to this attribute begins with a colon (':'), a new process, private to the application, is created when it's needed. If the process name begins with a lowercase character, a global process of that name is created. A global process can be shared with other applications, reducing resource usage.  
如果这个属性值使用一个':'开头，在需要的时候系统将会创建一个属于当前app的私有进程。如果这个属性值以一个小写字母开头，一个global process将会被在需要的时候被创建。Global process能被其它应用共享，减少资源消耗。

开整思路：  
通过前文分析可知，Activity如果是单个进程，在创建的时候会内置一个Binder对象，可以认为是私有的，开发者拿不到。为了让Activity获得一个公开的Binder，方法是创建一个Service，然后通过binderService获得一个公开的Binder对象。如果把方才的Activity和对应的Service设置成一个进程，就模拟了一个进程和Binder的实例。再来一个这样的进程和Binder实例，然后让它们两进行通信。为了简单，这里只将Activity和Service设置成两个不同的进程，然后Activity通过binderService获得Service的BinderProxy。按理，其它的Activity甚至其它App的Activity也能通过binderService获得这个Service的BinderProxy对象。

借助AIDL：

1. 借助AIDL生成一个IInterface
2. 在Service中，继承虚拟类stub，并实现里面自定义的方法，可以采用匿名内部类的形式实现
3. 在onBind()中返回Binder server的obj，就是第2步的实例
4. 实现interface ServiceConnection，可以采用匿名内部类的形式实现
5. 在onServiceConnected方法中获得BinderProxy
6. 执行bindService()后就可以与Binder Server通信了，通信方法就是第1步自定义的方法

自己写：

然而，不想写太多多余的东西，按照Binder机制：一个Server类，一个Proxy类，Server中实现onTransact()和Binder对象的返回，Client中获取Proxy。另外，Server的onTransact()根据命令执行对应的函数，将执行结果写回reply(Parcel)。这样，可以简化这个过程。将AIDL方式生成的接口文件改一改，适合我们的直观理解，实际它们是一样的。

方法很简单：将Interface，Stub和Proxy单独写成文件；如果将Interface写在一个文件，Stub和Proxy写在一个文件，就与AMS的结构一模一样了。说到底，还是分离AIDL Interface接口类为几个类，功能等效。

adb shell中看看多进程是否见效：  

```
➜  MyApplication2 adb shell ps | grep myapp
u0_a77    11024 229   1515580 60016 ffffffff 00000000 S com.archos.myapplication
u0_a77    11058 229   1315268 35240 ffffffff 00000000 S com.archos.myapplication.myService
```

## Reference

[IBinder](https://developer.android.com/reference/android/os/IBinder.html)  
[Binder](https://developer.android.com/reference/android/os/IBinder.html)  
[Android manifest application-element](https://developer.android.com/guide/topics/manifest/application-element.html)  
[浅谈JNI](http://blog.csdn.net/zzobin/article/details/7089794)  
[Android Framework 本地方法注册过程](http://blog.csdn.net/droidpioneer/article/details/6787571)  
[Android Jni 的静态注册与动态注册](http://blog.csdn.net/droidpioneer/article/details/6787571)  
[Android Binder机制的各个部分](http://blog.chinaunix.net/uid-9185047-id-3281772.html)  
[Binder native & framework & app各层的实现例子及相互调用  - 力荐](www.cloudchou.com/android/post-332.html)  
[Android StrictMode](http://tech.it168.com/a2011/0908/1243/000001243936_all.shtml)  
[Android AIDL](https://developer.android.com/guide/components/aidl.html)  
