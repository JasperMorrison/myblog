---
layout: post
title: Binder方案设计与实现
categories: Android
tags: Android binder
author: Jasper
---

* content
{:toc}

本文从顶层设计的思路入手，全面领悟Android Binder方案的设计与实现。将自己假想成一名为Google的程序员，如果要为Android实现一个类似Binder这样的IPC机制，怎么做。如果结合Binder的源码一起阅读，本文帮进行系统性总结的同时，还会给你一种豁然开朗的感觉。（本文基于Android13）



# 需求描述

假设穿越到过去，那时还没有Android，要你实现一个当今的Android Binder。

# 需求分析

1. 提供统一的IBinder接口；
2. 跨进程传递对象；

# 任务拆解

1. 使用IBinder表示对象，并完成对象的转换；
2. 设计IBinder统一接口；
3. ServiceManager设计；
4. 对象的跨进程传输；
5. 对象生命周期管理；
6. 多线程支持；

# 方案描述

1. Binder方案中，IBinder是统一的接口，代表着对象，我们可以通过IBinder来引用跨进程对象，同时调用跨进程对象的方法。
2. 使用ServiceManager（SM）对IBinder进行统一管理，其它进程可以通过SM获得系统中开发出来的IBinder（实名Binder）。
3. 借助驱动来做桥梁，把必要的功能通过系统调用陷入到内核，主要功能包括：进程管理、数据传递、进程间同步、鉴权。

# IBinder对象设计

![](/images/Android/binder/binder_object.png)

图解：  
1. 分为Server和Client端，各为一个进程，共享Kernel内存空间；
2. 定义一个MyBinder对象，包括C++和Java端，对象被一分为二，Stub在服务端创建，而Proxy在Client端创建；
3. 通过IBinder表示这个对象，使得Client端可以引用到这个对象，反之亦然；
4. 进程在Kernel中使用binder_proc表示，进程每打开一次binder节点，都会创建一个binder_proc；（/dev/binder /dev/hwbinder /dev/vndbinder）
5. IBinder（Server）对象使用binder_node来表示，这是唯一的；
6. Client端使用desc来代表一个binder_node，desc属于Client进程的一个唯一binder_node编码，desc对进程是独立的；
7. desc又被表示为handle，除了kernel，其它地方都用handle代替desc；
8. 每个进程维护一套自己的handle，其中，handle=0是全局唯一的，表示IServiceManager对象在内核中的binder_node；
9. BinderProxy是在native层通过JNI创建的；（重点）
10. 注意：数据结构并非严格一致，有的层次已经被我简化了；

# IBinder接口设计

IBinder接口的目的就是，将利用上述的IBinder对象进行跨进程数据传递;

```c++
virtual status_t transact(uint32_t code, const Parcel& data, Parcel* reply, uint32_t flags = 0) = 0;
```

```java
public boolean transact(int code, @NonNull Parcel data, @Nullable Parcel reply, int flags) throws RemoteException;
```

java和c++的接口设计成一样的，用code表示一个函数编号，将已经序列化的data传导给另一个进程，同时，返回序列化的结果到reply中。

Parcel是序列化的对象，Binder对象本身支持序列化，所以，Binder对象可以通过Parcel承载。Parcel传递Binder发生在：  
1. 实名Binder：进程与ServiceManager交互Binder对象，ServiceManager保存binder_ref；
2. 匿名Binder：通过IBinder接口与Client交互Binder对象，Client可以通过IBinder接口来执行IPC；

# ServiceManager（SM）设计

__SM作为一个独立进程，让所有进程都可以找到它__

SM是一个进程，它是[IBinder对象设计]一小节中的Server端，将其记录在binder driver中，让所有的进程都可以找到。

将自身作为一个IBinder对象加入到driver中，driver保存了一个binder_node，ptr和cookie是默认值0（重点）：

```c++
在open driver的时候，将miscdev的context设置到binder_proc的context中：
proc->context = &binder_dev->context; // 通过context来设置和保存SM的binder_node
```

```c++
SM::main()
ProcessState::becomeContextManager()
ioctl cmd=BINDER_SET_CONTEXT_MGR_EXT
in driver :
    static int binder_ioctl_set_ctx_mgr(
        binder_new_node()
        proc->context->binder_context_mgr_node = new_node
```

当其它进程寻找SM时，只需通过handle==0即可找到：  

```c++
IServiceManager::defaultServiceManager()
ProcessState::self()->getContextObject(nullptr)
sp<IBinder> context = getStrongProxyForHandle(0); （重点：获得SM的IBinder）
sp<BpBinder> b = BpBinder::PrivateAccessor::create(handle);
```

上述流程将handle==0的BpBinder返回，使得所有进程都可以获得SM的IBinder。

（重点）这里有一个脱节的点，此时代表SM的IBinder只是一个封装了handle==0的BpBinder。它是如何调用到SM的BBinder的呢？ 
答案在IPCThreadState中保存了一个全局变量the_context_object。首先，找到driver中的binder_node，然后区别对待：

```c++
// in status_t IPCThreadState::executeCommand(int32_t cmd)
if (tr.target.ptr) { // handle == 0 与 ptr == nullptr 等效，都是binder_node中的默认值
    // 非SM
} else {
    // SM
    error = the_context_object->transact(tr.code, buffer, &reply, tr.flags);
}
```

__SM管理IBinder__

在SM中将IBinder使用一个name:IBinder的map保存起来。

![](/images/Android/binder/sm_binder_ref.png)

# 对象的跨进程传输

__通信线程__

IPC必须依赖进程本身，在Binder中，单独开辟了一个Binder线程，专门提供给IBinder接口。

Server（包括SM）在进程启动时，在driver层执行read操作，当有消息时被唤醒。进入读取等待状态，SM进程与其它进程稍有不同.

SM:

```c++
int main(int argc, char** argv)
    ClientCallbackCallback::setupTo(looper, manager);
    IPCThreadState::setupPolling(int* fd)
        mOut.writeInt32(BC_ENTER_LOOPER);
    while(true) {
        // binder有事件后，执行getAndExecuteCommand()
        // 最终写入BC_ENTER_LOOPER并在 binder_thread_read 中等待被唤醒
        looper->pollAll(-1); 
    }
```

其它进程：

```c++
void ProcessState::startThreadPool()
void ProcessState::spawnPooledThread(bool isMain)::run()
    virtual bool threadLoop()
        IPCThreadState::self()->joinThreadPool(mIsMain);
            mOut.writeInt32(isMain ? BC_ENTER_LOOPER : BC_REGISTER_LOOPER);
            // 写入BC_ENTER_LOOPER并在 binder_thread_read 中等待被唤醒
            result = getAndExecuteCommand(); 
```

__IBinder的查询__

如果我们希望通过IBinder（Proxy）来进行对象的跨进程传输，必须先找到IBinder（Stub）：

user space :

```c++
IPCThreadState::transact
    writeTransactionData(BC_TRANSACTION, flags, handle, code, data, nullptr)
        // 填充一个struct binder_transaction_data tr
            tr.target.ptr = 0;
            tr.target.handle = handle;
            tr.code = code;
        mOut.writeInt32(cmd);
        mOut.write(&tr, sizeof(tr));
    waitForResponse(reply);
        talkWithDriver()
            //填充一个struct binder_write_read bwr
                bwr.write_buffer = (uintptr_t)mOut.data();
            ioctl(mProcess->mDriverFD, BINDER_WRITE_READ, &bwr)
                // 驱动内等待有数据可读
```

kernel space （代码已被精简）:

```c++
// in static void binder_transaction(...)
if (tr->target.handle) {
    // 非SM
    struct binder_ref *ref;
    // 先获得binder_node的binder_ref
    ref = binder_get_ref_olocked(proc, tr->target.handle,
                     true);
    if (ref) {
        // 提取Server的binder_node
        // 追加本地引用计数，这个可以忽略，与跨进程无关
        target_node = binder_get_node_refs_for_txn(
                ref->node, &target_proc,
                &return_error);
    }
} else {
    // SM， handle == 0
    // 直接使用，无需binder_ref，因为它是全局变量，不用释放
    target_node = context->binder_context_mgr_node;
}
```

对于非SM的IBinder，与SM不同，它们先找到binder_ref。SM的binder_ref在增加引用计数的地方创建，而其它的binder_ref在往Parcel中写入Binder时创建。

SM的binder_ref创建：

```c++
case BC_INCREFS:
case BC_ACQUIRE:
case BC_RELEASE:
case BC_DECREFS: {
    uint32_t target; // handle
    const char *debug_string;
    bool strong = cmd == BC_ACQUIRE || cmd == BC_RELEASE;
    bool increment = cmd == BC_INCREFS || cmd == BC_ACQUIRE;
    struct binder_ref_data rdata;
    
    if (get_user(target, (uint32_t __user *)ptr))
        return -EFAULT;
    
    ptr += sizeof(uint32_t);
    ret = -1;
    if (increment && !target) { // target == 0 means handle == 0
        struct binder_node *ctx_mgr_node;
    
        mutex_lock(&context->context_mgr_node_lock);
        ctx_mgr_node = context->binder_context_mgr_node;
        if (ctx_mgr_node) {
            if (ctx_mgr_node->proc == proc) {
                binder_user_error("%d:%d context manager tried to acquire desc 0\n",
                        proc->pid, thread->pid);
                mutex_unlock(&context->context_mgr_node_lock);
                return -EINVAL;
            }
            // 创建SM的 binder_ref 并增加对binder_node的引用计数，proc指当前进程，即client进程
            ret = binder_inc_ref_for_node(
                    proc, ctx_mgr_node,
                    strong, NULL, &rdata);
        }
        mutex_unlock(&context->context_mgr_node_lock);
    }
    if (ret)
        // 增加binder_ref的引用计数，proc指当前进程，即client进程
        ret = binder_update_ref_for_handle(
                proc, target, increment, strong,
                &rdata);
```

其它IBinder（Server）的binder_ref的创建：

```c++
// in driver
binder_transaction()
    case BINDER_TYPE_BINDER: 
        // 传递一个BBinder
        // 如：注册Service，需要将某个Service的BBinder注册到SM中，实际上是将binder_ref（转换为BpBinder）注册到SM
        ret = binder_translate_binder(fp, t, thread); // 在此创建binder_node，在目标进程的binder_proc中创建binder_ref
    case BINDER_TYPE_HANDLE: 
        // 传递一个BpBinder
        // 如：getService的时候，需要将某个Service返回被客户端，只需要返回handle即可
        // 1. 先通过handle找到binder_node
        // 2. 在目标进程创建binder_ref，并指定一个新的handle（handle是不能跨进程的）
        ret = binder_translate_handle(fp, t, thread); // 如果是跨进程的，会在Client进程中创建新的binder_ref

binder_translate_binder()
    node = binder_new_node(proc, fp) // 创建binder_node
    ret = binder_inc_ref_for_node()
        struct binder_ref *new_ref = NULL;
        new_ref = kzalloc(sizeof(*ref), GFP_KERNEL); // 创建binder_ref
        ref = binder_get_ref_for_node_olocked(proc, node, new_ref); // 加入proc->refs_by_desc
        ret = binder_inc_ref_olocked(ref, strong, target_list); // 增加强引用计数

binder_translate_handle()
    if (node->proc == target_proc) {}
    else {
        ret = binder_inc_ref_for_node(target_proc, node, ...) // target_proc指目标进程，即client进程
            new_ref = kzalloc(sizeof(*ref), GFP_KERNEL); // 创建新的binder_ref，提供新的handle
            ref = binder_get_ref_for_node_olocked(proc, node, NULL); // 加入proc->refs_by_desc
            ret = binder_inc_ref_olocked(ref, strong, target_list); // 增加强引用计数
    }
```

Any way，我们找到了IBinder（Server）的binder_node，得到了其变量cookie.

user space：

回到 `IPCThreadState::executeCommand()` 函数，它读取到binder_node的cookie：

```c++
// 已简化
if (tr.target.ptr) {
    error = reinterpret_cast<BBinder*>(tr.cookie)->transact(tr.code, buffer,
                &reply, tr.flags);
} else {
    error = the_context_object->transact(tr.code, buffer, &reply, tr.flags);
}
```

可以看到，将cookie直接强制转换为BBinder。至此，我们找到了IBinder（Server）。

__IBinder对象的跨进程传输__

正如 [IBinder的查询] 中提到的一样，IBinder的跨进程传输就是在目标进程中创建binder_node的binder_ref，并分配一个非0的handle。

handle在目标进程中被包装为BpBinder，然后向上提供为BinderProxy（java），native层直接通过interface_cast转换为MyBinder::Proxy。

IBinder传输时主要分为两种类型：
1. BINDER_TYPE_BINDER：传递BBinder，在目标进程中创建binder_ref，并构建BpBinder
2. BINDER_TYPE_HANDLE：传递BpBinder，在驱动中先找到binder_node，然后在目标进程中创建binder_ref，并构建BpBinder

# IBinder的生命周期

我们这里仅讨论跨进程的IBinder的生命周期，假如一个IBinder被另一个进程引用后，是什么时候被引用和销毁的。

引用有两种：
1. 弱引用，不影响对象的销毁，仅仅用于感知对象的存活。需要时检查，如果存活，则转化为强引用来使用。
2. 强引用，影响着对象的销毁。

思路：
1. 先定义对象的销毁机制；
2. 然后确定何时影响销毁机制；

IBinder销毁：
1. Java对象销毁
2. BBinder销毁
3. binder_node销毁

binder_node销毁：
```c++
static void binder_free_node(struct binder_node *node)
{
    kfree(node);
    binder_stats_deleted(BINDER_STAT_NODE);
}
```

定义IBinder销毁机制(重点) ：
1. 强引用计数为0，摧毁binder_node
2. 强引用和弱引用计数都为0，摧毁binder_ref

```c++
static bool binder_dec_node_nilocked()
    if (hlist_empty(&node->refs) && !node->local_strong_refs && !node->local_weak_refs && !node->tmp_refs) {
        // 满足销毁条件
    }

static void binder_dec_node(struct binder_node *node, int strong, int internal)
{
    bool free_node;

    binder_node_inner_lock(node);
    free_node = binder_dec_node_nilocked(node, strong, internal);
    binder_node_inner_unlock(node);
    if (free_node)
        binder_free_node(node);
}

static bool binder_dec_ref_olocked(struct binder_ref *ref, int strong)
{
    if (strong) {
        if (ref->data.strong == 0) {
            binder_user_error("%d invalid dec strong, ref %d desc %d s %d w %d\n",
                      ref->proc->pid, ref->data.debug_id,
                      ref->data.desc, ref->data.strong,
                      ref->data.weak);
            return false;
        }
        ref->data.strong--;
        if (ref->data.strong == 0) // (重点) 强引用计数为0，摧毁binder_node
            binder_dec_node(ref->node, strong, 1);
    } else {
        if (ref->data.weak == 0) {
            binder_user_error("%d invalid dec weak, ref %d desc %d s %d w %d\n",
                      ref->proc->pid, ref->data.debug_id,
                      ref->data.desc, ref->data.strong,
                      ref->data.weak);
            return false;
        }
        ref->data.weak--;
    }
    if (ref->data.strong == 0 && ref->data.weak == 0) { // (重点) 强引用和弱引用计数都为0，摧毁binder_ref
        binder_cleanup_ref_olocked(ref);
        return true;
    }
    return false;
}
```

影响IBinder（Client）的销毁机制：
1. 对于一个BpBinder(handle)，可以往驱动发送BC_INCREFS（弱引用）、BC_ACQUIRE（强引用）、BC_RELEASE（强引用）、BC_DECREFS（弱引用）；
2. 当transaction结束后，对IBinder的参数进行引用释放，binder_transaction_buffer_release()

当IBinder（Client）的强引用计数为0时，会触发IBinder（Server）的销毁。

__从BpBinder和BBinder的角度看，它是如何管理引用__

BBinder的引用计数增加：

BBinder对象会被driver中的binder_node的cookie引用，只要binder_node没有被释放，BBinder不会被释放。

BpBinder的引用计数增加：

BpBinder 构造函数中创建weak引用，正如下面的强引用类似：

```c++
void BpBinder::onFirstRef()
{
    ALOGV("onFirstRef BpBinder %p handle %d\n", this, binderHandle());
    if (CC_UNLIKELY(isRpcBinder())) return;
    IPCThreadState* ipc = IPCThreadState::self();
    // 往驱动写入BC_ACQUIRE，附带handle，内核增加对binder_ref的强引用计数
    if (ipc) ipc->incStrongHandle(binderHandle(), this); 
}
```

# 多线程支持

线程的增加： 

binder线程添加接口：`void IPCThreadState::joinThreadPool(bool isMain)`，仅此而已。（重点）

`mOut.writeInt32(isMain ? BC_ENTER_LOOPER : BC_REGISTER_LOOPER);` 通过与驱动交互不同的命令，将当前线程加入为binder主线程或者普通binder线程。

在内核中分别对应线程状态：
1. `thread->looper |= BINDER_LOOPER_STATE_ENTERED`
2. `thread->looper |= BINDER_LOOPER_STATE_REGISTERED;`

这两种线程状态并没有本质上的区别，仅仅是用来限制binder线程池的大小。（重点）

binder主线程：在App进程起来时，ProcessState会启动一个新的Thread作为binder主进程，自动调用joinThreadPool()；
普通线程：在binder_thread_read()的尾部，会往user space返回BR_SPAWN_LOOPER命令，动态创建普通线程，上限可以设置，不设置默认不支持多线程；

对于其它非App进程，一般会主动调用joinThreadPool()加入为binder线程。

对于所有进程来说，主动调用joinThreadPool()创建的线程，都不会统计在binder线程的数量上，也就是这个binder线程池的线程计数不会因此而增加。

线程的选择：

binder驱动在read过程中，会查找目标线程是否有空闲线程，如有，唤醒其执行消息接收。

# 参考

[源码：Android Binder 驱动 - kernel-android13-5.15-lts](http://www.aospxref.com/kernel-android13-5.15-lts/xref/drivers/android/)  
[源码：Android Framework libbinder](http://www.aospxref.com/android-13.0.0_r3/xref/frameworks/native/libs/binder/)  
[源码：Android Framework jni](http://www.aospxref.com/android-13.0.0_r3/xref/frameworks/base/core/jni/)  
[源码：Android Binder java](http://www.aospxref.com/android-13.0.0_r3/xref/frameworks/base/core/java/android/os/Binder.java)  
[源码：Android Binder c++](http://www.aospxref.com/android-13.0.0_r3/xref/frameworks/native/libs/binder/Binder.cpp)  
[源码：Android ServiceManager c++](http://www.aospxref.com/android-13.0.0_r3/xref/frameworks/native/cmds/servicemanager/)  

