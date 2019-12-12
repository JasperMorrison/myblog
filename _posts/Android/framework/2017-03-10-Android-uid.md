---
layout: post
title: Android uid
categories: Android
tags: Android uid UserHandle
author: Jasper
---

* content
{:toc}

本文记录了对Android user id的分析，以弄明白Android uid与Linux uid等相关id的关系。



### Linux id

Linux id 包括 uid pid ppid，root用户的uid==0，第一个用户uid == 1000，随后添加的用户uid从1001开始。

查看id信息 id / id -u \<user\>

```
➜  ~ id
uid=1000(jaren) gid=1000(jaren) groups=1000(jaren),4(adm),24(cdrom),27(sudo),30(dip),46(plugdev),113(lpadmin),128(sambashare),129(vboxusers),999(docker),1001(share)
➜  ~ id -u root
0
➜  ~ id -u jaren
1000
➜  ~ id jaren
uid=1000(jaren) gid=1000(jaren) groups=1000(jaren),4(adm),24(cdrom),27(sudo),30(dip),46(plugdev),113(lpadmin),128(sambashare),129(vboxusers),999(docker),1001(share)
➜  ~ id root
uid=0(root) gid=0(root) groups=0(root),1001(share)
```

查看进程信息ps -elf

```
➜  ~ ps -ela
F S   UID   PID  PPID  C PRI  NI ADDR SZ WCHAN  TTY          TIME CMD
4 S     0     1     0  0  80   0 - 29985 -      ?        00:00:02 systemd
1 S     0     2     0  0  80   0 -     0 -      ?        00:00:00 kthreadd
1 S     0     3     2  0  80   0 -     0 -      ?        00:00:00 ksoftirqd/0
1 S     0     5     2  0  60 -20 -     0 -      ?        00:00:00 kworker/0:0H
1 S     0     7     2  0  80   0 -     0 -      ?        00:01:08 rcu_sched
```

这里pid == 0没显示出来，pid 0属于Linux启动的第一个进程，idle进程。

PID — 进程id  
USER — 进程所有者  
PR — 进程优先级  
NI — nice值。负值表示高优先级，正值表示低优先级  
VIRT — 进程使用的虚拟内存总量，单位kb。VIRT=SWAP+RES  
RES — 进程使用的、未被换出的物理内存大小，单位kb。RES=CODE+DATA  
SHR — 共享内存大小，单位kb  
S — 进程状态。D=不可中断的睡眠状态 R=运行 S=睡眠 T=跟踪/停止 Z=僵尸进程  
%CPU — 上次更新到现在的CPU时间占用百分比  
%MEM — 进程使用的物理内存百分比  
TIME+ — 进程使用的CPU时间总计，单位1/100秒  
COMMAND — 进程名称（命令名/命令行）  

### Android id check

Android system_server进程在启动的时候，被设置了uid和pid为1000.详情如下：  
[system_server启动](/2017/03/10/android-ams/#system_server)的时候，被Zygote设置了对应的uid = 1000和pid = 1000，以及system_server所属的groups。也许我应该关心一下，这些groups的用途是什么。到adb shell中查看一下具体情况：  

```
root      1     0     24000  2200  SyS_epoll_ 00000000 S /init

root      253   1     1014176 66036 poll_sched 00000000 S zygote

system    813   253   1180648 111444 SyS_epoll_ 00000000 S system_server

uid=1000(system) gid=1000(system) groups=1000(system), context=u:r:shell:s0
```

得到system_server的有关信息：  
- 进程 system_server
- pid 813
- ppid 253 zygote forked from /init
- user system
- group system
- groups system

问：其它的groups去哪了，Zygote没有设置成功吗？？？

关注以下其它apk的id信息，发现：  

```
u0_a14    1671  253   1052000 78700 SyS_epoll_ 00000000 S com.google.android.gms
u0_a55    1926  253   841460 42896 SyS_epoll_ 00000000 S com.google.android.apps.messaging:rcs
u0_a44    2044  253   855784 46616 SyS_epoll_ 00000000 S com.google.android.gm
```

- apk's user looks liek u0_a*
- apk's ppid is zygote's pid, here is 253
- apk's pid is based on the Linux's schedule

We check user u0_a0 and u0_a55 : 

```
➜  nougat adb shell id u0_a0
uid=10000(u0_a0) gid=10000(u0_a0) groups=10000(u0_a0), context=u:r:shell:s0

➜  nougat adb shell id u0_a55
uid=10055(u0_a55) gid=10055(u0_a55) groups=10055(u0_a55), context=u:r:shell:s0
```

Now as it showed, apk's Linux uid is from 10000 to larger.

### Android id purpose

1. shareuid

在开发系统app的时候，如settings app，在AndroidManifest.xml文件中可以看到`android:sharedUserId="android.uid.system"`. 这是将当前app的Linux用户设置成于system同一个用户。在shell中验证一下是不是同一个用户：

```
system    3594  253   931164 68176 SyS_epoll_ 00000000 S com.android.settings
system    3619  253   825112 31852 SyS_epoll_ 00000000 S com.mediatek.schpwronoff // mtk的自动关开机app
```

2. User managerment

frameworks/base/core/java/android/os/UserHandle.java

这个文件在一些用户权限管理方面经常看到相关的函数，记录一下还是值得的。注意uid表示Linux 用户id经过处理后的id，user id是Android系统经过简化处理的从0开始的用户id，两者之间是有函数转换的，函数就在这个文件中。更清楚明了的说明是，在Android系统中，user id表示用户的id，id == 0表示第0个用户，id == 1表示第1个用户；Android uid类似于Linux uid，对于每一个Linux uid，它可能属于多个用户的，为了达到区分的目的，将Linux uid和user id绑定，方法是 user id x 100000 + Linux uid = Android uid. Android uid在UserHandle.java中简称uid。

```java
 26 /**
 27  * Representation of a user on the device. 代表着一个设备的用户
 28  */
 29 public final class UserHandle implements Parcelable {
 30     /**
 31      * @hide Range of uids allocated for a user. uids的范围，不超过10万
 32      */
 33     public static final int PER_USER_RANGE = 100000; 
 34 
 35     /** @hide A user id to indicate all users on the device 代表所有的用户*/ 
 36     public static final @UserIdInt int USER_ALL = -1;
 37 
 38     /** @hide A user handle to indicate all users on the device 代表所有的用户的UserHandle对象*/
 39     public static final UserHandle ALL = new UserHandle(USER_ALL);
 40 
 41     /** @hide A user id to indicate the currently active user 当前用户id */
 42     public static final @UserIdInt int USER_CURRENT = -2;
 43 
 44     /** @hide A user handle to indicate the current user of the device 当前用户的UserHandle对象*/
 45     public static final UserHandle CURRENT = new UserHandle(USER_CURRENT);
 46 
 47     /** @hide A user id to indicate that we would like to send to the current
 48      *  user, but if this is calling from a user process then we will send it
 49      *  to the caller's user instead of failing with a security exception */
 50     public static final @UserIdInt int USER_CURRENT_OR_SELF = -3;
 51 
 52     /** @hide A user handle to indicate that we would like to send to the current
 53      *  user, but if this is calling from a user process then we will send it
 54      *  to the caller's user instead of failing with a security exception */
 55     public static final UserHandle CURRENT_OR_SELF = new UserHandle(USER_CURRENT_OR_SELF);
 56 
 57     /** @hide An undefined user id 未定义的user id */
 58     public static final @UserIdInt int USER_NULL = -10000;
 59 
 60     /**
 61      * @hide A user id constant to indicate the "owner" user of the device
 62      * @deprecated Consider using either {@link UserHandle#USER_SYSTEM} constant or
 63      * check the target user's flag {@link android.content.pm.UserInfo#isAdmin}.
 64      */ //设备管理员，这个用户id已经过时了，请采用下面的USER_SYSTEM
 65     public static final @UserIdInt int USER_OWNER = 0;
 66 
 67     /**
 68      * @hide A user handle to indicate the primary/owner user of the device
 69      * @deprecated Consider using either {@link UserHandle#SYSTEM} constant or
 70      * check the target user's flag {@link android.content.pm.UserInfo#isAdmin}.
 71      */
 72     public static final UserHandle OWNER = new UserHandle(USER_OWNER);
 73 
 74     /** @hide A user id constant to indicate the "system" user of the device 系统用户*/
 75     public static final @UserIdInt int USER_SYSTEM = 0;
 76 
 77     /** @hide A user serial constant to indicate the "system" user of the device */
 78     public static final int USER_SERIAL_SYSTEM = 0;
 79 
 80     /** @hide A user handle to indicate the "system" user of the device 系统用户对象 */
 81     public static final UserHandle SYSTEM = new UserHandle(USER_SYSTEM);
 82 
 83     /**
 84      * @hide Enable multi-user related side effects. Set this to false if
 85      * there are problems with single user use-cases.
 86      */ // 使能多用户模式
 87     public static final boolean MU_ENABLED = true;
 88 
 89     final int mHandle;
 90 
112     /** @hide */
113     public static boolean isIsolated(int uid) {
114         if (uid > 0) {
115             final int appId = getAppId(uid);
116             return appId >= Process.FIRST_ISOLATED_UID && appId <= Process.LAST_ISOLATED_UID;
117         } else {
118             return false;
119         }
120     }

141     /**
142      * Returns the user id for a given uid.
143      * @hide
144      */ // 从Android uid中提取 user id
145     public static @UserIdInt int getUserId(int uid) {
146         if (MU_ENABLED) {
147             return uid / PER_USER_RANGE; //多用户是10万的倍数
148         } else {
149             return UserHandle.USER_SYSTEM; //单用户只有0
150         }
151     }
152 
153     /** @hide */ // 获得调用者的user id
154     public static @UserIdInt int getCallingUserId() {
155         return getUserId(Binder.getCallingUid());
156     }

158     /** @hide */
159     @SystemApi
160     public static UserHandle of(@UserIdInt int userId) {
161         return userId == USER_SYSTEM ? SYSTEM : new UserHandle(userId);
162     }
163 
164     /**
165      * Returns the uid that is composed from the userId and the appId.
166      * @hide
167      */
168     public static int getUid(@UserIdInt int userId, @AppIdInt int appId) {
169         if (MU_ENABLED) {
		// 这里的AppId 是Linux uid
		// 如果是多用户，第几个用户 + app id，也就是，所有用户都拥有这个uid的所有权。
		// 第0个用户，000000 + app id
		// 第1个用户，100000 + app id
		// 只要Linux uid( app id )的值不超过10万，都是合理的。
170             return userId * PER_USER_RANGE + (appId % PER_USER_RANGE); 
171         } else {
172             return appId; //如果是单用户系统，uid必定只有一个，即第0个用户
173         }
174     }

176     /**
177      * Returns the app id (or base uid) for a given uid, stripping out the user id from it.
178      * @hide
179      */ // 注意是TestApi， 从Android uid中分离出 Linux uid
180     @TestApi
181     public static @AppIdInt int getAppId(int uid) {
182         return uid % PER_USER_RANGE;
183     }
184 
185     /**
186      * Returns the gid shared between all apps with this userId.
187      * @hide
188      */ // 不明白？？？
189     public static int getUserGid(@UserIdInt int userId) {
190         return getUid(userId, Process.SHARED_USER_GID); //SHARED_USER_GID = 9997
191     }
192 
193     /**
194      * Returns the shared app gid for a given uid or appId.
195      * @hide
196      */ // 不明白？？？
197     public static int getSharedAppGid(int id) {
198         return Process.FIRST_SHARED_APPLICATION_GID + (id % PER_USER_RANGE)
199                 - Process.FIRST_APPLICATION_UID;
200     }
201 
202     /**
203      * Returns the app id for a given shared app gid. Returns -1 if the ID is invalid.
204      * @hide
205      */ //不明白？？？
206     public static @AppIdInt int getAppIdFromSharedAppGid(int gid) {
207         final int appId = getAppId(gid) + Process.FIRST_APPLICATION_UID
208                 - Process.FIRST_SHARED_APPLICATION_GID;
209         if (appId < 0 || appId >= Process.FIRST_SHARED_APPLICATION_GID) {
210             return -1;
211         }
212         return appId;
213     }
303     /**
304      * Returns true if this UserHandle refers to the owner user; false otherwise.
305      * @return true if this UserHandle refers to the owner user; false otherwise.
306      * @hide
307      * @deprecated please use {@link #isSystem()} or check for
308      * {@link android.content.pm.UserInfo#isPrimary()}
309      * {@link android.content.pm.UserInfo#isAdmin()} based on your particular use case.
310      */
311     @SystemApi
312     public boolean isOwner() {//deprecated instead of isSystem()
313         return this.equals(OWNER);
314     }
315 
316     /**
317      * @return true if this UserHandle refers to the system user; false otherwise.
318      * @hide
319      */
320     @SystemApi
321     public boolean isSystem() { // 判断用户对象是否相同
322         return this.equals(SYSTEM);
323     }
```

