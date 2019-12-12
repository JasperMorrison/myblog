---
layout: post
title: "Android Binder 驱动"
categories: Android-Framework
tags: Android Binder Driver
author: Jasper
---

* content
{:toc}

本文熟悉Android Binder驱动设计，熟悉其本质，并了解Android Binder在Android系统中的引用。
贴上来的程序段只是精简代码。



## Binder驱动

linux源码 drivers/staging/android

### Binder驱动部分结构体

```c++
 334 struct binder_thread { // 在binder_ioctl中获得（找不到则创建）
 335         struct binder_proc *proc;
 336         struct rb_node rb_node; // 维护一个红黑树，红黑树的节点是binder_thread结构体，每一个节点代表一个调用进程
 337         int pid;
 338         int looper;
 339         struct binder_transaction *transaction_stack;
 340         struct list_head todo;
 341         uint32_t return_error; /* Write failed, return error code in read buf */
 342         uint32_t return_error2; /* Write failed, return error code in read */
 343                 /* buffer. Used when sending a reply to a dead process that */
 344                 /* we are also waiting on */
 345         wait_queue_head_t wait;
 346         struct binder_stats stats;
 347 };
```

```c
 349 struct binder_transaction {
 350         int debug_id;
 351         struct binder_work work;
 352         struct binder_thread *from;
 353         struct binder_transaction *from_parent;
 354         struct binder_proc *to_proc;
 355         struct binder_thread *to_thread;
 356         struct binder_transaction *to_parent;
 357         unsigned need_reply:1;
 358         /* unsigned is_dead:1; */       /* not used at the moment */
 359 
 360         struct binder_buffer *buffer;
 361         unsigned int    code;
 362         unsigned int    flags;
 363         long    priority;
 364         long    saved_priority;
 365         kuid_t  sender_euid;
 366 };
```

```c
129 struct binder_transaction_data {
130         /* The first two are only used for bcTRANSACTION and brTRANSACTION,
131          * identifying the target and contents of the transaction.
132          */
133         union {
134                 __u32   handle; /* target descriptor of command transaction */
135                 binder_uintptr_t ptr;   /* target descriptor of return transaction */
136         } target;
137         binder_uintptr_t        cookie; /* target object cookie */
138         __u32           code;           /* transaction command */
139 
140         /* General information about the transaction. */
141         __u32           flags;
142         pid_t           sender_pid;
143         uid_t           sender_euid;
144         binder_size_t   data_size;      /* number of bytes of data */
145         binder_size_t   offsets_size;   /* number of bytes of offsets */
146 
147         /* If this transaction is inline, the data immediately
148          * follows here; otherwise, it ends with a pointer to
149          * the data buffer.
150          */
151         union {
152                 struct {
153                         /* transaction data */
154                         binder_uintptr_t        buffer;
155                         /* offsets from buffer to flat_binder_object structs */
156                         binder_uintptr_t        offsets;
157                 } ptr;
158                 __u8    buf[8];
159         } data;
160 };
```

```c
	//在驱动中常常被简写为bwr
 72 /*
 73  * On 64-bit platforms where user code may run in 32-bits the driver must
 74  * translate the buffer (and local binder) addresses appropriately.
 75  */
 76 
 77 struct binder_write_read {
 78         binder_size_t           write_size;     /* bytes to write */
 79         binder_size_t           write_consumed; /* bytes consumed by driver */
 80         binder_uintptr_t        write_buffer;
 81         binder_size_t           read_size;      /* bytes to read */
 82         binder_size_t           read_consumed;  /* bytes consumed by driver */
 83         binder_uintptr_t        read_buffer;
 84 };
```

### Binder ioctl与cmd

drivers/staging/android/binder.h定义了binder驱动中与ioctl函数相关的结构体和commands。
ioctl相关内容见参考文献，区别一个cmd可以需要type和nr两个参数，对于一个打开的驱动设备fd，我们可以用自定义的type对命令进行分类，再用自定义的nr对同类的命令进行编号。比如`BC_TRANSACTION = _IOW('c', 0, struct binder_transaction_data)`命令，指定type='c'，nr=0，属于IOW（写）命令，写入的大小正好是struct binder_transaction_data的大小，_IOW内部自动调用sizeof获得struct的实际大小。

linux source 中 include/uapi/asm-generic/ioctl.h包含了对ioctl cmd的宏定义。

### __init

1. 建立工作队列
2. 创建如下Linux Debugfs:  
```
binder  
└── proc  
    ├── failed_transaction_log  
    ├── state  
    ├── stats  
    ├── transaction_log  
    └── transactions  
```  
在创建文件的时候，附带指定了在文件上的操作接口，如&binder_state_fops，是由宏BINDER_DEBUG_ENTRY(state);得到的，其它类似。

3. 注册操作ret = misc_register(&binder_miscdev);  
static struct miscdevice 的 .name 创建在/dev，类似普通字符设备一样，ls /dev可以看到binder字符设备。

见参考文献，整个过程就是简单的MISC设备初始化过程。

操作函数：

```c++
3540 static const struct file_operations binder_fops = {
3541         .owner = THIS_MODULE,
3542         .poll = binder_poll,
3543         .unlocked_ioctl = binder_ioctl,
3544         .compat_ioctl = binder_ioctl,
3545         .mmap = binder_mmap,
3546         .open = binder_open,
3547         .flush = binder_flush,
3548         .release = binder_release,
3549 };
```

### binder_open

初始化一个struct binder_proc，并加到Debugfs 'binder/proc'中，文件名称是proc->pid，也就是current->group_leader->pid。


### binder_ioctl

binder_ioctl是Binder操作函数中指定的.ioctl，通过特定组合的cmds区分命令，并对其做出处理，与用户进行数据交换。

```c++
2587 static long binder_ioctl(struct file *filp, unsigned int cmd, unsigned long arg)
2588 {
2589         int ret;
2590         struct binder_proc *proc = filp->private_data; //从filp中获得proc，前面已经设置过了，数据保存在debugfs中的proc文件夹下面
2591         struct binder_thread *thread;
2592         unsigned int size = _IOC_SIZE(cmd); // cmd的大小
2593         void __user *ubuf = (void __user *)arg;
2594 
2595         /*pr_info("binder_ioctl: %d:%d %x %lx\n", proc->pid, current->pid, cmd, arg);*/
2596 
2597         trace_binder_ioctl(cmd, arg); // tracepoint 追踪点，见binder_trace.h和参考文献
2598 
2599         ret = wait_event_interruptible(binder_user_error_wait, binder_stop_on_user_error < 2); 
2602 
2603         binder_lock(__func__); //加锁
	     // proc->threads.rb_node，可见proc结构体维护着一个名为threads的红黑数
	     // 从threads红黑树中获得（找不到就插入一个新的）thread，current->pid可以标志一个节点	     
	     // 谁调用驱动，current->pid就是谁的pid，把设备当文件处理就能理解这一点了
2604         thread = binder_get_thread(proc); 
2609 
2610         switch (cmd) {
2611         case BINDER_WRITE_READ: { //读写binder
2659         case BINDER_SET_MAX_THREADS: //设置最大节点数
2665         case BINDER_SET_CONTEXT_MGR: //设置serviceManager
2694         case BINDER_THREAD_EXIT: //调用进程退出
2700         case BINDER_VERSION: // 调用进程读取Binder版本
2658         }
```

新建一个thread

```
2497                 thread = kzalloc(sizeof(*thread), GFP_KERNEL);
2498                 if (thread == NULL)
2499                         return NULL;
2500                 binder_stats_created(BINDER_STAT_THREAD); //binder_stats 计数 +1
2501                 thread->proc = proc;
2502                 thread->pid = current->pid;
2503                 init_waitqueue_head(&thread->wait); // 初始化等待队列，等待队列在数据通信中用到
```

__关注两个cmd：BINDER_WRITE_READ和BINDER_SET_CONTEXT_MGR__

__BINDER_WRITE_READ__

```c++
case BINDER_WRITE_READ: {
	//read data from user space to struct binder_write_read
	if (bwr.write_size > 0) {
		//call binder_thread_write function
		ret = binder_thread_write(proc, thread, bwr.write_buffer, bwr.write_size, &bwr.write_consumed);
	}
	if (bwr.read_size > 0) {
		//call binder_thread_read function
		ret = binder_thread_read(proc, thread, bwr.read_buffer, bwr.read_size, &bwr.read_consumed, filp->f_flags & O_NONBLOCK);
	}
}
```

#### binder_thread_write

```c++
	//get cmd from binder_thread->binder_buffer
	//classify the cmds according to the binder_command_control in binder.h
	//I only care about the transation cmd as below
1910                 case BC_TRANSACTION:
1911                 case BC_REPLY: {
1912                         struct binder_transaction_data tr;
1913 
1914                         if (copy_from_user(&tr, ptr, sizeof(tr))) // copy data
1915                                 return -EFAULT;
1916                         ptr += sizeof(tr);
			     // deal with data
1917                         binder_transaction(proc, thread, &tr, cmd == BC_REPLY); 
1918                         break;
1919                 }
```

__binder_transaction__

传入参数：  
- proc 进程信息
- thread 线程信息
- &tr 接收到的binder_transaction_data结构体指针
- 是BC_REPLY吗？

```c
		/*BC_REPLY*/
1327         if (reply) {
		//先不考虑
1365         } else {
		/*BC_TRANSACTION*/
1366                 if (tr->target.handle) { // __u32 传输数据目标
1367                         struct binder_ref *ref;
				//根据target从proc的refs_by_desc(rb_root)中获得binder_ref
1368                         ref = binder_get_ref(proc, tr->target.handle); 
1375                         target_node = ref->node; // 获得struct binder_node结构体
1376                 } 
			// 重新设置target_proc，我认为它跟传入的参数proc是一样的
1384                 target_proc = target_node->proc; 
1393                 if (!(tr->flags & TF_ONE_WAY) && thread->transaction_stack) { 
			//如果不是单向传输
				//用from端的信息结构体binder_transaction 设置target_thread
					352         struct binder_thread *from;
					353         struct binder_transaction *from_parent;
1394                         struct binder_transaction *tmp; 
1395                         tmp = thread->transaction_stack; 
1405                         while (tmp) {
1406                                 if (tmp->from && tmp->from->proc == target_proc)
						// 利用from_parent设置target_thread
						// from_parent是干嘛的？
1407                                         target_thread = tmp->from; 
1408                                 tmp = tmp->from_parent;
1409                         }
1410                 }
		// 设置任务队列
		// thread存在与不存在的区别？？？
1412         if (target_thread) {
1413                 e->to_thread = target_thread->pid;
1414                 target_list = &target_thread->todo;
1415                 target_wait = &target_thread->wait;
1416         } else {
1417                 target_list = &target_proc->todo;
1418                 target_wait = &target_proc->wait;
1419         }
		// 为函数开始处定义的两个结构体申请空间
1306         struct binder_transaction *t;
1307         struct binder_work *tcomplete;
		// 填充结构体及内部的struct binder_buffer空间
		// 代码略
1487         if (copy_from_user(t->buffer->data, (const void __user *)(uintptr_t)
		//获得data中的buffer到buffer中
1488                            tr->data.ptr.buffer, tr->data_size)) {
1493         }
		// 设置offp，/* offsets from buffer to flat_binder_object structs */
1494         if (copy_from_user(offp, (const void __user *)(uintptr_t)
1495                            tr->data.ptr.offsets, tr->offsets_size)) {
1500         }
			// 处理struct flat_binder_object， 并设置一个新的。
1523                 fp = (struct flat_binder_object *)(t->buffer->data + *offp);
1525                 switch (fp->type) {
			// binder
1526                 case BINDER_TYPE_BINDER:
1527                 case BINDER_TYPE_WEAK_BINDER: {
1559                         fp->handle = ref->desc;
			// handle
1569                 case BINDER_TYPE_HANDLE:
1570                 case BINDER_TYPE_WEAK_HANDLE: {
1583                         if (ref->node->proc == target_proc) {
1588                                 fp->binder = ref->node->ptr;
1589                                 fp->cookie = ref->node->cookie;
1596                         } else {
1597                                 struct binder_ref *new_ref;
1598                                 new_ref = binder_get_ref_for_node(target_proc, ref->node);
1603                                 fp->handle = new_ref->desc;
			// fd
1614                 case BINDER_TYPE_FD: {
1655                         fp->handle = target_fd;
		//最后的处理
1665         if (reply) { // reply吗？
1667                 binder_pop_transaction(target_thread, in_reply_to);
1668         } else if (!(t->flags & TF_ONE_WAY)) { // 不是单向传输
1670                 t->need_reply = 1; //需要回复
1671                 t->from_parent = thread->transaction_stack;
1672                 thread->transaction_stack = t;
1673         } else { //单向传输
1676                 if (target_node->has_async_transaction) {
				//前面已经设置过了，binder_thread_readd函数中并没有处理async_todo的情况
1677                         target_list = &target_node->async_todo;  
1678                         target_wait = NULL;  // 既然是单向，就不用等待回复了
1679                 } else
1680                         target_node->has_async_transaction = 1;
1681         }
		// 设置t在工作队列中的工作类型
1682         t->work.type = BINDER_WORK_TRANSACTION;  
		// 把t->work加入到target_list中
1683         list_add_tail(&t->work.entry, target_list); 
		// 在binder read函数中会用到这个type，记住t->work和tcomplete属于struct binder_work
1684         tcomplete->type = BINDER_WORK_TRANSACTION_COMPLETE; 
		// tcomplete加入到&thread->todo中
1685         list_add_tail(&tcomplete->entry, &thread->todo);  
1686         if (target_wait)
		//唤醒等待队列,target_wait在本函数前面已经设置了
		//谁被唤醒了？调用binder驱动传输数据的进程或者线程，到这里，数据传输完成，可以继续往下执行了，所以需要唤醒。
1687                 wake_up_interruptible(target_wait);  
1688         return;

```

#### binder_thread_read

```c
2115 static int binder_thread_read(struct binder_proc *proc,
2116                               struct binder_thread *thread,
2117                               binder_uintptr_t binder_buffer, size_t size,
2118                               binder_size_t *consumed, int non_block)
2119 {
2120         void __user *buffer = (void __user *)(uintptr_t)binder_buffer;
		// 这里的consumed的意思是：
		// buffer中，有*consumed个binder_size_t是给binder驱动用的，其它空间为__user。
2121         void __user *ptr = buffer + *consumed; 
2122         void __user *end = buffer + size;
		// binder_has_thread_work(thread) 直到这个函数为真，等待队列出错返回
		//进入读取循环
2196         while (1) {
2197                 uint32_t cmd;
2198                 struct binder_transaction_data tr;
2199                 struct binder_work *w;
2200                 struct binder_transaction *t = NULL;
2201 
2202                 if (!list_empty(&thread->todo)) 
2203                         w = list_first_entry(&thread->todo, struct binder_work, entry); // 从thread队列读
2204                 else if (!list_empty(&proc->todo) && wait_for_proc_work) 
2205                         w = list_first_entry(&proc->todo, struct binder_work, entry); // 从proc队列读
2206                 else { // 重试
2207                         if (ptr - buffer == 4 && !(thread->looper & BINDER_LOOPER_STATE_NEED_RETURN)) /* no data added */
2208                                 goto retry;
2209                         break;
2210                 }
2215                 switch (w->type) {
2216                 case BINDER_WORK_TRANSACTION: {
			// 接收数据，通过 w 获得其父结构体 struct binder_transaction的指针
			// 也就是binder_thread_write中的 t
2217                         t = container_of(w, struct binder_transaction, work);
2218                 } break;
			// 说明接收到一个执行binder_thread_write的成功消息
2219                 case BINDER_WORK_TRANSACTION_COMPLETE: {
			// 暂时不理会其它命令
2234                 case BINDER_WORK_NODE: {
2298                 case BINDER_WORK_DEAD_BINDER:
2299                 case BINDER_WORK_DEAD_BINDER_AND_CLEAR:
2300                 case BINDER_WORK_CLEAR_DEATH_NOTIFICATION: {

			// 处理刚刚获得struct binder_transaction *t
2340                 if (t->buffer->target_node) { //双向
2341                         struct binder_node *target_node = t->buffer->target_node;
2342                         tr.target.ptr = target_node->ptr;
2343                         tr.cookie =  target_node->cookie;
2344                         t->saved_priority = task_nice(current);
2345                         if (t->priority < target_node->min_priority &&
2346                             !(t->flags & TF_ONE_WAY))
2347                                 binder_set_nice(t->priority);
2348                         else if (!(t->flags & TF_ONE_WAY) ||
2349                                  t->saved_priority > target_node->min_priority)
2350                                 binder_set_nice(target_node->min_priority);
2351                         cmd = BR_TRANSACTION; //数据传输
2352                 } else { //单向
2353                         tr.target.ptr = 0;
2354                         tr.cookie = 0;
2355                         cmd = BR_REPLY; // 回复 由此可见，回复是单向的
2356                 }
2357                 tr.code = t->code;
2358                 tr.flags = t->flags;
2359                 tr.sender_euid = from_kuid(current_user_ns(), t->sender_euid); // sender uid

2361                 if (t->from) { // sender pid
2362                         struct task_struct *sender = t->from->proc->tsk;
2363                         tr.sender_pid = task_tgid_nr_ns(sender,
2364                                                         task_active_pid_ns(current));
2365                 } else {
2366                         tr.sender_pid = 0;
2367                 }
2368 
2369                 tr.data_size = t->buffer->data_size;
2370                 tr.offsets_size = t->buffer->offsets_size;
2371                 tr.data.ptr.buffer = (binder_uintptr_t)(
2372                                         (uintptr_t)t->buffer->data +
2373                                         proc->user_buffer_offset);
2374                 tr.data.ptr.offsets = tr.data.ptr.buffer +
2375                                         ALIGN(t->buffer->data_size,
2376                                             sizeof(void *));
			//把命令写给user空间
2378                 if (put_user(cmd, (uint32_t __user *)ptr))  
2379                         return -EFAULT;
2380                 ptr += sizeof(uint32_t);
			// 把struct binder_transaction_data tr写给user空间，完整进程间数据copy
2381                 if (copy_to_user(ptr, &tr, sizeof(tr))) 
2382                         return -EFAULT;
2383                 ptr += sizeof(tr);

2427         return 0;
2428 }
```

__BINDER_SET_CONTEXT_MGR__

```c
2665         case BINDER_SET_CONTEXT_MGR: // mgr uid一旦设置不会改变
			//检查是否有设置mgr的selinux权限
2671                 ret = security_binder_set_context_mgr(proc->tsk); 
2672                 if (ret < 0)
2673                         goto err;
			// 将mgr的动态uid(euid)设置为mgr_uid
2683                 binder_context_mgr_uid = current->cred->euid; 
			// 根节点
2684                 binder_context_mgr_node = binder_new_node(proc, 0, 0); 
```

## service_manager

frameworks/native/cmds/servicemanager/Android.mk

``` 
 22 LOCAL_SRC_FILES := service_manager.c binder.c  #这里的binder.c不是驱动中的binder.c，它的作用是操作/dev/binder
 24 LOCAL_MODULE := servicemanager
 25 LOCAL_INIT_RC := servicemanager.rc
 26 include $(BUILD_EXECUTABLE)
```

frameworks/native/cmds/servicemanager/servicemanager.rc或者在shell中也能查看

```
➜  nougat adb shell cat ./system/etc/init/servicemanager.rc
service servicemanager /system/bin/servicemanager
    class core
    user system
    group system readproc
    critical
    onrestart restart healthd
    onrestart restart zygote
    onrestart restart audioserver
    onrestart restart media
    onrestart restart surfaceflinger
    onrestart restart inputflinger
    onrestart restart drm
    onrestart restart cameraserver
    writepid /dev/cpuset/system-background/tasks
```

### main函数

```c++
365 int main()
366 {
367     struct binder_state *bs;
368 
369     bs = binder_open(128*1024);
...
375     if (binder_become_context_manager(bs)) { // 为binder设置context manager(MGR) 
		//ioctl(bs->fd, BINDER_SET_CONTEXT_MGR, 0);
		//宏命令定义在#include <linux/binder.h>
		//binder驱动中提到的drivers/staging/android/binder.h
...
	// binder loop，传入binder 和 一个函数
402     binder_loop(bs, svcmgr_handler);
```

### binder_open

```c++
 89 struct binder_state
 90 {
 91     int fd;
 92     void *mapped;
 93     size_t mapsize;
 94 }; 
 96 struct binder_state *binder_open(size_t mapsize)
 97 {
 98     struct binder_state *bs;
 99     struct binder_version vers;
100 
101     bs = malloc(sizeof(*bs));
...
106 
107     bs->fd = open("/dev/binder", O_RDWR | O_CLOEXEC); // 打开驱动设备，如果执行exec，则新进程（实际上是替换，pid不变）中关闭本进程文件描述符
...
113 
114     if ((ioctl(bs->fd, BINDER_VERSION, &vers) == -1) ||
115         (vers.protocol_version != BINDER_CURRENT_PROTOCOL_VERSION)) { //匹配binder驱动版本
...
120     }
121 
122     bs->mapsize = mapsize;
123     bs->mapped = mmap(NULL, mapsize, PROT_READ, MAP_PRIVATE, bs->fd, 0); //设置bs
...
```

### binder_loop

```c
388 void binder_loop(struct binder_state *bs, binder_handler func)
389 {
390     int res;
	// binder驱动中可见，是一个承载传输数据的buffer相关结构体
391     struct binder_write_read bwr; 
392     uint32_t readbuf[32];
	// 告诉驱动，本进程进入looper过程
398     readbuf[0] = BC_ENTER_LOOPER; //见驱动binder.h
399     binder_write(bs, readbuf, sizeof(uint32_t)); 
400 
401     for (;;) {
402         bwr.read_size = sizeof(readbuf);
403         bwr.read_consumed = 0;
404         bwr.read_buffer = (uintptr_t) readbuf;
405 		//从驱动读取，这是一个阻塞的过程
406         res = ioctl(bs->fd, BINDER_WRITE_READ, &bwr);
412 		//解析数据
413         res = binder_parse(bs, 0, (uintptr_t) readbuf, bwr.read_consumed, func);
422     }
423 }
```

## binder control test

frameworks/native/cmds/servicemanager/bctest.cc

### preparatoin

- build whole android7 source code
- mmm frameworks/native/cmds/servicemanager
- emulator/emulator64-arm or using android avd
- adb push out/target/product/generic_arm64/system/bin/bctest /data/local/tmp/

### testing

后续添加

### Source

#### svcmgr_lookup

```c
 11 uint32_t svcmgr_lookup(struct binder_state *bs, uint32_t target, const char *name)
 12 {
 13     uint32_t handle;
 14     unsigned iodata[512/4];
 15     struct binder_io msg, reply;
 	//初始化一个struct binder_io, binder_io的作用是辅助组装和解析binder_transaction_data结构体
	//bctest中把它当作一个需要传输的msg
	//随后对这个msg进行填充
	//msg的实际作用是用于封装与service_manager的交互数据，service_manager对msg进程分析，执行任务。
 17     bio_init(&msg, iodata, sizeof(iodata), 4); 
 18     bio_put_uint32(&msg, 0);  // strict mode header
 19     bio_put_string16_x(&msg, SVC_MGR_NAME);
 20     bio_put_string16_x(&msg, name);
 	// binder_call传入msg和一个接收binder返回数据的struct binder_io reply，并传给service_manager SVC_MGR_CHECK_SERVICE
	// SVC_MGR_CHECK_SERVICE会被service_manager 的 binder_loop中的svcmgr_handler函数处理。
	// binder_call的内部根据这个msg组装一个标准的binder_transaction_data，并传给binder cmd BC_TRANSACTION，表示要进行进程间数据传输
	// binder_call内部for(;;)中读取BR_REPLY信息，利用函数bio_init_from_txn根据返回的binder_transaction_data填充binder_io reply
 22     if (binder_call(bs, &msg, &reply, target, SVC_MGR_CHECK_SERVICE))
 23         return 0;
 	//从bio data(buffer)中获得flat_binder_object structs，提取里面的handle
	//对于data来说，开头指针保存在offsets变量中，保存flat_binder_object structs，buffer指针指向剩余的data。
	//bio_init传入的maxoffs是4，因为Android.mk中指定了BINDER_IPC_32BIT=1，所以flat_binder_object structs的大小正好是4.
	//bio_put_obj函数中的obj就是flat_binder_object的意思
	//里面的handle就是struct svcinfo里面的handle，我想它能代表一个service。用数字表示，0代表service_manager这样一个服务，>0表示系统service。
	//BC_ACQUIRE表示向binder驱动请求这个服务，则这个服务的引用数+1，如果服务不存在，则创建服务，handle的值 +1。
	//所以，增加到binder驱动的服务，用数字表示，谁先添加，谁的数字就小。
	//那么flat_binder_object里面的binder(Binder)又是什么呢？？？
 25     handle = bio_get_ref(&reply);
 26 
 27     if (handle)
 28         binder_acquire(bs, handle);
 29 
 30     binder_done(bs, &msg, &reply);
 31 
 32     return handle;
 33 }
```

#### svcmgr_publish

它的功能很简单，就是往binder中添加一个服务，类似上面对svcmgr_lookup函数的理解，组装一个binder_io，调用binder_call传递SVC_MGR_ADD_SERVICE指令，告诉binder驱动添加一个服务。

## ServiceManager

ServiceManager是java层面对Service的管理，通过调用其getService方法获得Service。这里以AMS为例进行分析。

### 获得AMS

frameworks/base/core/java/android/app/ActivityManagerNative.java -> getDefault() -> gDefault.get()

```java
3017     private static final Singleton<IActivityManager> gDefault = new Singleton<IActivityManager>() {
3018         protected IActivityManager create() {
3019             IBinder b = ServiceManager.getService("activity");
3023             IActivityManager am = asInterface(b);
3027             return am;
3028         }
3029     };
```

```java
 17 package android.util;
 18 
 19 /**
 20  * Singleton helper class for lazily initialization.
 25  */
 26 public abstract class Singleton<T> {
 27     private T mInstance;
 28 
 29     protected abstract T create();
 30 
 31     public final T get() {
 32         synchronized (this) {
 33             if (mInstance == null) {
 34                 mInstance = create();
 35             }
 36             return mInstance;
 37         }
 38     }
 39 }
```

上面两段代码显示，AMS是在调用`ActivityManagerNative.java -> getDefault() -> gDefault.get()`的时候从ServiceManager中获得的。

android.os.ServiceManager

```java
 43     /**
 44      * Returns a reference to a service with the given name.
 45      * 
 46      * @param name the name of the service to get
 47      * @return a reference to the service, or <code>null</code> if the service doesn't exist
 48      */
 49     public static IBinder getService(String name) {
 50         try {
 51             IBinder service = sCache.get(name);
 52             if (service != null) {
 53                 return service;
 54             } else {
			// 从IServiceManager中获得
 55                 return getIServiceManager().getService(name); 
 56             }
 57         } catch (RemoteException e) {
 58             Log.e(TAG, "error in getService", e);
 59         }
 60         return null;
 61     }
```

```java
 33     private static IServiceManager getIServiceManager() {
 34         if (sServiceManager != null) {
 35             return sServiceManager;
 36         }
 37 
 38         // Find the service manager
 39         sServiceManager = ServiceManagerNative.asInterface(BinderInternal.getContextObject());
 40         return sServiceManager;
 41     }
```

android.os.ServiceManagerNative

```java
 29     /**
 30      * Cast a Binder object into a service manager interface, generating
 31      * a proxy if needed.
 32      */
 33     static public IServiceManager asInterface(IBinder obj)
 34     {
 35         if (obj == null) {
 36             return null;
 37         }
		// descriptor = IServiceManager.descriptor
		// static final String descriptor = "android.os.IServiceManager";
		// 第一次调用的时候，这个是空的
 38         IServiceManager in =
 39             (IServiceManager)obj.queryLocalInterface(descriptor);
 40         if (in != null) {
 41             return in;
 42         }
 43		// 如果是第一次调用，执行这里
 44         return new ServiceManagerProxy(obj);
 45     }
```

new ServiceManagerProxy(obj); // Binder obj

ServiceManagerNative.java

```java
109 class ServiceManagerProxy implements IServiceManager {
110     public ServiceManagerProxy(IBinder remote) {
111         mRemote = remote;
112     }
113     
114     public IBinder asBinder() {
115         return mRemote;
116     }
```

由此可见IServiceManager的变量，可以当作ServiceManagerProxy看待。ServiceManagerProxy维护着一个IBinder mRemote.  
这个IBinder 来自(com.android.internal.os.BinderInternal) BinderInternal.getContextObject() :

```java
 83     /**
 84      * Return the global "context object" of the system.  This is usually
 85      * an implementation of IServiceManager, which you can use to find
 86      * other services.
 87      */
 88     public static final native IBinder getContextObject();
```

android_util_Binder.cpp

```c
 902 static jobject android_os_BinderInternal_getContextObject(JNIEnv* env, jobject clazz)
 903 {
	//ProcessState 中new BpBinder(0);也就是这个handle == 0 BpBinder可以理解为在ProcessState中的Binder对象
	//IBinder中的transact -> ProcessState 中de transact -> IPCThreadState 中的transact
	//会把data完整的传输到另一端(Binder的server端)
 904     sp<IBinder> b = ProcessState::self()->getContextObject(NULL);
 905     return javaObjectForIBinder(env, b);
 906 }
```

反推到前面的android.os.ServiceManager->getService(name);函数，正是class ServiceManagerProxy 的 getService()，并返回一个 IBinder。  
这个IBinder来自下面的getService()函数。

__getService()__

class ServiceManagerProxy->getService()

```java
118     public IBinder getService(String name) throws RemoteException {
119         Parcel data = Parcel.obtain();
120         Parcel reply = Parcel.obtain();
121         data.writeInterfaceToken(IServiceManager.descriptor);
122         data.writeString(name);
		// binder driver 返回的数据被放进 reply(Parcel)。
123         mRemote.transact(GET_SERVICE_TRANSACTION, data, reply, 0);
		// 从串行化的数据中提取IBinder对象
124         IBinder binder = reply.readStrongBinder();
125         reply.recycle();
126         data.recycle();
127         return binder;
128     }
```

mRemote.transact(GET_SERVICE_TRANSACTION, data, reply, 0);中的GET_SERVICE_TRANSACTION和data分别对应struct binder_transaction_data中的code和data。这些内容都是传递到service_manager中的。

service_manager:  
前面知道，SM是使用了binder_loop不断读取binder驱动的数据，并采用svcmgr_handler处理获得信息。

```c
300     switch(txn->code) {
301     case SVC_MGR_GET_SERVICE:
302     case SVC_MGR_CHECK_SERVICE:
303         s = bio_get_string16(msg, &len);
304         if (s == NULL) {
305             return -1;
306         }
307         handle = do_find_service(s, len, txn->sender_euid, txn->sender_pid);
308         if (!handle)
309             break;
310         bio_put_ref(reply, handle);
311         return 0;
312 
313     case SVC_MGR_ADD_SERVICE:
314         s = bio_get_string16(msg, &len);
315         if (s == NULL) {
316             return -1;
317         }
318         handle = bio_get_ref(msg);
319         allow_isolated = bio_get_uint32(msg) ? 1 : 0;
320         if (do_add_service(bs, s, len, handle, txn->sender_euid,
321             allow_isolated, txn->sender_pid))
322             return -1;
323         break;
```

## 参考文献

[Linux ioctl command的设计](http://blog.chinaunix.net/uid-20754793-id-177774.html)  
[Linux ioctl函数](http://blog.chinaunix.net/uid-20754793-id-177775.html)  
[Linux 中断上半部与下半部](http://blog.chinaunix.net/uid-24203478-id-3111803.html)  
[Linux 工作队列工作原理](http://blog.csdn.net/myarrow/article/details/8090504)  
[Linux 等待队列](http://blog.csdn.net/lizuobin2/article/details/51785812)  
[Linux wait_event_interruptible 与 wake_up](http://blog.csdn.net/allen6268198/article/details/8112551)  
[Linux Debugfs](http://www.cnblogs.com/wwang/archive/2011/01/17/1937609.html)  
[Linux 驱动initcall方法 - device_initcall](http://blog.csdn.net/wh_19910525/article/details/16370863)  
[Linux MISC device driver](http://blog.csdn.net/yaozhenguo2006/article/details/6760575)  
[Linux 驱动 - 当前进程的引用current](http://www.cnblogs.com/chingliu/archive/2011/08/29/2223803.html)  
[Linux tracepoint](http://lyl19.blog.163.com/blog/static/19427205520136173531972/)  
[Linux __user](http://blog.csdn.net/q345852047/article/details/7710818)  
[Android Binder 驱动层分析](http://blog.csdn.net/u010961631/article/details/20479507)  
[Android Binder驱动与ServiceManger](http://blog.csdn.net/hu3167343/article/details/38441119)  
[Android system_server](http://blog.csdn.net/hu3167343/article/details/38375167)  
[SEAndroid安全机制对Binder IPC的保护分析](http://blog.csdn.net/luoshengyang/article/details/38326729)  





