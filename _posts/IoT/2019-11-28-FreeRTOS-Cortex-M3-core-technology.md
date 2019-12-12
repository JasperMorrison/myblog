---
layout: post
title:  FreeRTOS Cortex-M3 核心技术
categories: FreeRTOS
tags:  FreeRTOS RTOS Cortex-M3 任务切换 内存管理 SVC PendSV
author: Jasper
---

* content
{:toc}

本文是关于FreeRTOS在Cortex-M3上的核心技术，主要涉及任务的创建、任务内存管理和任务切换，展示了系统切换到用户级运行FreeRTOS任务的过程。  
内存管理基于heap\_2，基于Demo `FreeRTOS\Demo\CORTEX_STM32F103_Keil`。







# 1. 概念

本文基本包含所有FreeRTOS port Cortex-M3的芯片级技术，基本包含`FreeRTOS\Source\portable\RVDS\ARM_CM3\port.c`中的内容。

FreeRTOS Port：FreeRTOS终端，每一种编译器、设备类型都可称为port，比如GCC可以称为port，STM32也可以称为port，cortex-m3也可以称为port。  
堆栈(Stack)：即是栈，官方的翻译称堆栈。  
堆(Heap)：堆是与堆栈相对于的堆，动态分配内存时使用的部分。  

TCB、Stack：(heap_2)本文的Stack与堆栈有一定的区别，它也是堆栈的意思，但是特指task所使用的stack。task占用的内存包括TCB和Stack。  
ucHeap：整块可自由分配的内存的大小，是需要开发者手动配置的。

阅读本文建议的基本要求：  

- 已经阅读过并理解FreeRTOS官方指导手册《FreeRTOS_Real_Time_Kernel-A_Hands-On_Tutorial_Guide》或者中文翻译版  
- 熟悉Cortex-M3基本概念和技术
- 熟悉汇编、C语言
- 拥有足够的操作系统相关知识

通篇点到为止，适合结合源码阅读。

# 2. 创建任务

以官方Demo为例，创建了一个Led闪烁的任务。  

```
xTaskCreate( vLEDFlashTask, "LEDx", ledSTACK_SIZE, NULL, uxPriority, 
( TaskHandle_t * ) NULL );
```

vLEDFlashTask : 任务函数体  
第二参数：任务名称，仅作为可读字符串，无实际意义  
ledSTACK_SIZE： 任务的堆栈深度  
第四参数：传给任务的参数（void*）指针    
uxPriority：任务优先级，任务的优先级都是事先安排的，同一类型的任务优先级一般相同  
第六参数：任务变化的回调（包括优先级变化、任务要被删除等）  

堆栈大小（字节数） = 堆栈的深度 x 堆栈的宽度（比如4 bytes）  
堆栈的宽度是通过StackType_t决定的，在M3中，它是32-bits（4字节）  

xTaskCreate被宏定义为xTaskGenericCreate，如果是使用MPU，再次被定义为MPU_xTaskGenericCreate，这里不涉及MPU。

```
BaseType_t xTaskGenericCreate( TaskFunction_t pxTaskCode, const char * const pcName, const uint16_t usStackDepth, void * const pvParameters,
UBaseType_t uxPriority, TaskHandle_t * const pxCreatedTask, StackType_t * const puxStackBuffer, const MemoryRegion_t * const xRegions ) 
/*lint !e971 Unqualified char types are allowed for strings and single characters only. */
```

前面的几个参数，与XTaskCreate一一对应，最后两个参数，这里是为固定的NULL（包括puxStackBuffer, xRegions）。

## 2-1. 申请内存

```c
TCB_t * pxNewTCB;
pxNewTCB = prvAllocateTCBAndStack( usStackDepth, NULL );
```

先申请一个TCB Block，再申请一个Stack的Block，一个任务有两个Block。  
总大小等于 usStackDepth * sizeof(StackType_t)。

### 2-1-1. TCB Block

直接进入该函数的内部

`pxNewTCB = ( TCB_t * ) pvPortMalloc( sizeof( TCB_t ) );`

使用pvPortMalloc申请内存，从函数的定义可以猜到，它在Source/portable相关文件中实现。

FreeRTOS的动态内存管理方式有5个，分别是heap_1/2/3/4/5.  
以heap_2为例。

看看`void *pvPortMalloc( size_t xWantedSize )`的heap_2实现。

先通过`vTaskSuspendAll();`禁止任务调度，任务调度暂停与启动的做法是维护一个volatile类型的全局变量。  
`PRIVILEGED_DATA static volatile UBaseType_t uxSchedulerSuspended   = ( UBaseType_t ) pdFALSE;`

第一次申请时，还要对heap进行初始化：`prvHeapInit();`  
初始化的结果是，将heap均分一个完整的大Block，并将一个BlockLink_t结构体存放到heap的头部。

xWantedSize 是任务获得的可用内存大小，实际申请时，还需要加上heap头部结构体的大小，并进行8字节对齐。 
调整后的xWantedSize如果小于configTOTAL_HEAP_SIZE，就表示可以进行分配了。

怎么分配，当然分配Block，一个一个Block地配，直到分配的内存总量等于mWantedSize，或者内存不足。

如果是第一次分配，那么，一个Block的大小就是configADJUSTED_HEAP_SIZE，除去heap头部，可用大小是非常可观。

但是太大了，于是将多余的部分分出来，独立为一个新的Block.

新的Block的头部，同样是一个heap头部，下次分配内存时，同样类似上述过程。

最后，将新的Block添加到Block list中。

最后的最后，恢复任务调度。

注意这里的返回值，是一个TCB_t结构体。

### 2-1-2. Stack Block

类似申请TCB Block，将一个新的Block分配给TCB_t结构体中的pxStack成员。  
申请好之后，使用memset对整块Block清零。  

Stack大小 = usStackDepth - TCB Block

Stack可以配置为向上增长或者向下生长。

将Stack的信息保存到TCB中。

## 2-2. Heap初始化

`prvHeapInit();`

它以BlockLink_t类型为基本管理单位，每一个该类型代表一个RAM Block。当内存还没别分配时，是一个完整的大Block。  
Block的总大小与configADJUSTED_HEAP_SIZE一致。

`#define configADJUSTED_HEAP_SIZE   ( configTOTAL_HEAP_SIZE - portBYTE_ALIGNMENT )`  
与configTOTAL_HEAP_SIZE相当。

有必要看看它的函数体：

```c
static void prvHeapInit( void )
{
BlockLink_t *pxFirstFreeBlock;
uint8_t *pucAlignedHeap;

    /* Ensure the heap starts on a correctly aligned boundary. */
    pucAlignedHeap = ( uint8_t * ) ( ( ( portPOINTER_SIZE_TYPE ) &ucHeap[ portBYTE_ALIGNMENT ] ) & ( ( portPOINTER_SIZE_TYPE ) ~portBYTE_ALIGNMENT_MASK ) );

    /* xStart is used to hold a pointer to the first item in the list of free
    blocks.  The void cast is used to prevent compiler warnings. */
    xStart.pxNextFreeBlock = ( void * ) pucAlignedHeap;
    xStart.xBlockSize = ( size_t ) 0;

    /* xEnd is used to mark the end of the list of free blocks. */
    xEnd.xBlockSize = configADJUSTED_HEAP_SIZE;
    xEnd.pxNextFreeBlock = NULL;

    /* To start with there is a single free block that is sized to take up the
    entire heap space. */
    pxFirstFreeBlock = ( void * ) pucAlignedHeap;
    pxFirstFreeBlock->xBlockSize = configADJUSTED_HEAP_SIZE;
    pxFirstFreeBlock->pxNextFreeBlock = &xEnd;
}
```

xStart和xEnd都是全局静态变量。  
`static BlockLink_t xStart, xEnd;`

ucHeap是整块配置的RAM内存，一次性作为全局变量申请了。

```c
/* Allocate the memory for the heap. */
static uint8_t ucHeap[ configTOTAL_HEAP_SIZE ];
```

xStart指向heap头，xEnd指向heap尾部，并指定了大小，此时xEnd的大小代表了自身Block的大小，xStart的大小是0，则表示xStart只是包含了heap头的指针。  
所以，prvHeapInit函数实际是将configADJUSTED_HEAP_SIZE划分为完整的一个大块。

pxFirstFreeBlock的作用是在heap的头部存放整个heap的信息（同样是一个BlockLink_t结构体），可以称其为heap的头部信息。

## 2-3. 任务TCB初始化

到此，任务的TCB和Stack内存都已经申请好了，但它们基本是空的，并不能代表一个有效的任务。

开始往TCB填充任务信息，比如设置任务名称、任务优先级、初始化任务Event链表、执行状态时间计数等。

用到`static void prvInitialiseTCBVariables()`

其中的动作不多，但有些还不是很清楚用途何在，在用到任务相关的属性时，可以回头再来看看。

## 2-4. Stack初始化

`pxNewTCB->pxTopOfStack = pxPortInitialiseStack( pxTopOfStack, pxTaskCode, pvParameters );`

对新申请到的Stack Block进行初始化，利用头部传递信息或者在任务切换时保护现场。

Stack Block头部信息如下，默认每一行表示一个StackType_t：

Stack Block | 作用
---|---
xPSR初始值 | 任务切换时初始化xPSR
任务函数指针 | 任务内的PC初始值
prvTaskExitError | LR
保留|R12 
保留|R3
保留|R2
保留|R1
任务参数指针pvParameters|传给R0
保留8个StackType_t|留给R11-R4

从Stack的头部就可以看到，PC指针指向了任务函数，传给任务的参数会保存在R0中。当进行任务切换时，都要将这些信息保存到Stack中，当切入任务后，从Stack中恢复到寄存器，正式开始任务的执行。

当正在执行的任务被切换出去而脱离运行状态时，Stack的头部正好用于来保护现场。

Stack头部（除了最后的8个StackType_t）与M3异常退出时栈的结构是一样的，这就是任务的上下文。如此，当从SVC中跳转到任务执行，这些内容会以此被弹出到响应的寄存器中，从而实现上下文切换。

## 2-5. 更新任务列表

先创建一个临界区，然后在临界区中更新任务列表，将新的任务添加到列表中。其实，是将任务的TCB加入列表。

创建临界区的方法，见本文的**禁止系统调用**部分。

初始化各种任务列表

根据任务数量及优先级更新 pxCurrentTCB 

将TCB添加到Ready list，这里也说了，一个任务刚刚创建的时候，处于Ready状态。  
但处于Ready不一定会被调度，只有最高优先级的Ready状态的任务会被调度。

### 2-5-1. 任务列表

```
PRIVILEGED_DATA static List_t pxReadyTasksLists[ configMAX_PRIORITIES ];
/*< Prioritised ready tasks. */
PRIVILEGED_DATA static List_t xDelayedTaskList1;                        
/*< Delayed tasks. */
PRIVILEGED_DATA static List_t xDelayedTaskList2;                        
/*< Delayed tasks (two lists are used - one for delays that have overflowed the current tick count. */
PRIVILEGED_DATA static List_t * volatile pxDelayedTaskList;             
/*< Points to the delayed task list currently being used. */
PRIVILEGED_DATA static List_t * volatile pxOverflowDelayedTaskList;     
/*< Points to the delayed task list currently being used to hold tasks that have overflowed the current tick count. */
PRIVILEGED_DATA static List_t xPendingReadyList;                        
/*< Tasks that have been readied while the scheduler was suspended.  They will be moved to the ready list when the scheduler is resumed. */
```

从上到下分别是：  
保存ready状态的任务列表  
保存延迟的任务列表1  
保存延迟的任务列表2  
指向当前正在使用的任务列表   
指向当前正在使用的任务列表，且任务的滴答计数已经溢出（还不清楚用途）  
Pending状态的任务列表（任务调度器正在休眠）

还有两个根据配置而定的列表：  
等待终止的任务列表（任务被删除了，但是所占用的内存还没清空）  
suspend状态的任务列表（如果系统支持任务suspend）

Ready状态的任务列表比较特殊，它是一个二维列表，第一维是任务的优先级，第二维才是任务。这也很符合RTOS，它只调度最高优先级任务。

# 3. 禁止系统调用

当进入临界区时，就要禁止系统调用，方法是屏蔽SVC中断。

参考：http://www.FreeRTOS.org/RTOS-Cortex-M3-M4.html 

```
# 4. define configMAX_SYSCALL_INTERRUPT_PRIORITY    191
/* equivalent to 0xb0, or priority 11. */
```

SVC中断的优先级正好就是11，将11以下的中断都禁止，就是禁止了系统调用。比如：11，12，13 ... 这些都被屏蔽。

禁止中断：

```
__asm uint32_t ulPortSetInterruptMask( void )
{
    PRESERVE8

    mrs r0, basepri
    mov r1, #configMAX_SYSCALL_INTERRUPT_PRIORITY
    msr basepri, r1
    bx r14
}
```

将basepri保存到r0中，然后设置为0xb0。  
恢复中断时，将r0恢复到basepri。

```
__asm void vPortClearInterruptMask( uint32_t ulNewMask )
{
    PRESERVE8

    msr basepri, r0
    bx r14
}
```

bx r14，返回调用者，相当于bx lr

# 5. 启动任务调度器

禁止系统调用

设置time count timer，这是一个用于统计任务运行时间的时间计数（时间测量），周期越短，统计精度越高。具体参考《161204_Mastering_the_FreeRTOS_Real_Time_Kernel-A_Hands-On_Tutorial_Guide.pdf》的有关章节。

调用xPortStartScheduler()启动调度器

```c
    /* Make PendSV and SysTick the lowest priority interrupts. */
    portNVIC_SYSPRI2_REG |= portNVIC_PENDSV_PRI;
    portNVIC_SYSPRI2_REG |= portNVIC_SYSTICK_PRI;

    /* Start the timer that generates the tick ISR.  Interrupts are disabled
    here already. */
    vPortSetupTimerInterrupt();

    /* Initialise the critical nesting count ready for the first task. */
    uxCriticalNesting = 0;

    /* Start the first task. */
    prvStartFirstTask();
```

portNVIC_SYSPRI2_REG = 0xE000_ED20，从它开始的32-bits空间内，包含了PendSV优先级寄存器和SysTick优先级寄存器。

```
0xE000_ED20 PRI_12 调试监视器的优先级
0xE000_ED21 - - - -
0xE000_ED22 PRI_14 PendSV 的优先级
0xE000_ED23 PRI_15 SysTick 的优先级
```

这两个优先级都设置为最低优先级255。

之所以设置为最低优先级，是因为PendSV/SysTick不应该抢占CPU异常及外部中断。  
PendSV的作用在于，SVC应当悬起，直到所有中断都得到执行，具体参考《Contex-M3权威指南-7.6小节》。

vPortSetupTimerInterrupt() 设置Systick为10ms

prvStartFirstTask() 启动第一个任务。

# 6. 启动第一个任务

启动第一个任务，是将系统从特权级线程模式转换为用户级线程模式，它通过SVC异常服务程序进行切换。调用系统服务程序时，系统暂时切换为特权级handler模式，系统服务内使用msp堆栈。这里没有使用PendSV，因为第一个任务必须根据需要立即得到运行。

```c
__asm void prvStartFirstTask( void )
{
    PRESERVE8

    /* Use the NVIC offset register to locate the stack. */
    ldr r0, =0xE000ED08
    ldr r0, [r0]
    ldr r0, [r0]

    /* Set the msp back to the start of the stack. */
    msr msp, r0
    /* Globally enable interrupts. */
    cpsie i
    cpsie f
    dsb
    isb
    /* Call SVC to start the first task. */
    svc 0
    nop
    nop
}
```

PRESERVE8: 声明采用8字节对齐  
0xE000ED08：向量表的偏移地址，如果没有重新安排向量表，它的内容为0x0  
向量表的第一个内容是MSP，三个ldr指令将MSP的值传到r0寄存器。  
msr msp, r0：将MSP（系统堆栈起始地址）传到msp寄存器。

msp寄存器指向系统堆栈起始地址后，进入handler模式才能使用全部的系统堆栈。这里就是初始化msp，每次进入handler都应该初始化msp。

cpsie i/f：关中断、关异常   
dsb/isb：指令/存储器同步  

svc 0：调用 0号系统服务，实际上，数字并没使用。

两个nop：不清楚有什么用

# 7. SVC 系统服务的服务例程

SVC 触发软中断后，SVC系统服务例程被调用，此时系统处于特权级handler模式，使用msp堆栈。

```c
__asm void vPortSVCHandler( void )
{
    PRESERVE8

    ldr r3, =pxCurrentTCB   /* Restore the context. */
    ldr r1, [r3]            /* Use pxCurrentTCBConst to get the pxCurrentTCB address. */
    ldr r0, [r1]            /* The first item in pxCurrentTCB is the task top of stack. */
    ldmia r0!, {r4-r11}     /* Pop the registers that are not automatically saved on exception entry and the critical nesting count. */
    msr psp, r0             /* Restore the task stack pointer. */
    isb
    mov r0, #0
    msr basepri, r0
    orr r14, #0xd
    bx r14
}
```

根据上文有关任务的创建过程，pxCurrentTCB代表了当前最高优先级任务，它指向任务的TCB Block。

三个ldr，取出TCB Block中的第一项内容，其实就是任务堆栈的栈顶（Stack顶部 - Stack头部），保存到r0。

`volatile StackType_t   *pxTopOfStack;`

`ldmia r0!, {r4-r11}`:  
从栈中弹出数据保存到寄存器，这些内容保存在Stack头部最低的几个双字中。

将堆栈栈顶保存到psp，任务使用psp，系统使用msp。
其实，这时，psp并不是真正的栈顶，见上方**Stack初始化**小节：  
psp此时指向任务参数指针pvParameters。pvParameters的作用在于，系统可以在创建任务时，向任务传递系统数据，很多时候，它被设为NULL。

将basepri设置为0，对basepri的作用是**停止屏蔽所有中断**。

将LR寄存器低4位设置为1101或者1111，bx r14后，进入用户级线程模式，使用psp，并从psp中弹出堆栈信息，里面包含了PC值。  
参考《Cortex-M3权威指南-9.2/9.6小节》有关的异常返回内容。

从psp中弹出PC值，更新PC寄存器，程序从任务开始执行。

正式闯进FreeRTOS Task的大门，用户的应用程序至此跑起来了。

同样的，任务切换也是走这个逻辑。

# 8. 任务切换

从上面的内容基本已经清楚SVC系统服务0，及第一个任务，代表了从handler模式切换到线程模式的过程。那么，系统正常运行之后，多任务之间又是如何切换的呢，是如何保存任务的现场不被破坏的？

系统滴答会导致任务切换，系统异常服务例程是`void xPortSysTickHandler( void );`。

```c
void xPortSysTickHandler( void )
{
    /* The SysTick runs at the lowest interrupt priority, so when this interrupt
    executes all interrupts must be unmasked.  There is therefore no need to
    save and then restore the interrupt mask value as its value is already
    known. */
    ( void ) portSET_INTERRUPT_MASK_FROM_ISR();
    {
        /* Increment the RTOS tick. */
        if( xTaskIncrementTick() != pdFALSE )
        {
            /* A context switch is required.  Context switching is performed in
            the PendSV interrupt.  Pend the PendSV interrupt. */
            portNVIC_INT_CTRL_REG = portNVIC_PENDSVSET_BIT;
        }
    }
    portCLEAR_INTERRUPT_MASK_FROM_ISR( 0 );
}
```

它看起来很简单，先是屏蔽SVC异常，触发PendSV：  
`portNVIC_INT_CTRL_REG = portNVIC_PENDSVSET_BIT;`

将SVC改成PendSV是任务切换的基本策略，防止SVC异常上访为硬fault。

## 8-1. 任务切换的判断

`xTaskIncrementTick()`

将延期任务加入就绪任务列表，判断就绪任务列表是否符合切换要求：  
- 最高优先级的就绪列表中有2个以上的任务
- 有更高优先级的任务存在

## 8-2. PendSV服务例程

```c
__asm void xPortPendSVHandler( void )
{
    extern uxCriticalNesting;
    extern pxCurrentTCB;
    extern vTaskSwitchContext;

    PRESERVE8

    mrs r0, psp
    isb

    ldr r3, =pxCurrentTCB       /* Get the location of the current TCB. */
    ldr r2, [r3]

    stmdb r0!, {r4-r11}         /* Save the remaining registers. */
    str r0, [r2]                /* Save the new top of stack into the first member of the TCB. */

    stmdb sp!, {r3, r14}
    mov r0, #configMAX_SYSCALL_INTERRUPT_PRIORITY
    msr basepri, r0
    bl vTaskSwitchContext
    mov r0, #0
    msr basepri, r0
    ldmia sp!, {r3, r14}

    ldr r1, [r3]
    ldr r0, [r1]                /* The first item in pxCurrentTCB is the task top of stack. */
    ldmia r0!, {r4-r11}         /* Pop the registers and the critical nesting count. */
    msr psp, r0
    isb
    bx r14
    nop
}
```

将psp传给r0  
取Stack顶部地址（不包括Stack头部），保存到r2  
将{r4-r11}入栈（psp指向的栈）  
`str r0, [r2]`将psp保存到TCB中  
屏蔽SVC异常，也就是下面的内容不允许发生另一个任务切换    
调用vTaskSwitchContext  
放开SVC屏蔽  
从`ldr r1, [r3]`则是跳转到下一个任务，当`bx r14`调用结束，进入下一个任务，这一点与上面的**执行第一个任务**小节是类似的。

完成任务的切换。

## 8-3. vTaskSwitchContext

取出需要换入的任务的TCB指针存放到pxCurrentTCB指向的地址中。  
r3寄存器指向的位置，内容被更新为新的TCB。

完事。

本文其它链接：https://blog.csdn.net/weixin_45866432/article/details/103284720
