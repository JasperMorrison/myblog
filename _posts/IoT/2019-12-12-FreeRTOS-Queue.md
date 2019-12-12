---
layout: post
title:  FreeRTOS Queue（队列）
categories: FreeRTOS
tags:  FreeRTOS RTOS 队列 信号量 互斥量 邮箱
author: Jasper
---

* content
{:toc}

本文介绍了FreeRTOS队列的创建、发送和阻塞接收的过程和原理，以及基于队列实现的其它系统功能。







> 由于FreeRTOS很多API其实是通过宏定义，不同的FreeRTOS版本，宏的实际函数可能不相同，所以，本文并不区分是宏还是函数。

# 队列的创建

- 创建队列管理结构体Queue_t，包括申请内存
- 申请队列内容所需内存，填充Queue_t

创建队列接口：  
`xQueueCreate( uxQueueLength, uxItemSize ) `  
返回QueueHandle_t，其实是void *.

申请队列管理结构体内存：  
`pxNewQueue = ( Queue_t * ) pvPortMalloc( sizeof( Queue_t ) );`

申请队列内容所需内存，并填充Queue_t:  
```
pxNewQueue->pcHead = ( int8_t * ) pvPortMalloc( xQueueSizeInBytes );
pxNewQueue->uxLength = uxQueueLength;
pxNewQueue->uxItemSize = uxItemSize;
```

返回Queue_t： 
以void *的形式返回，使用时需要转换为Queue_t *.

# 队列发送

为了简便，以下使用“发送队列消息”代表“往队列中发送内容”。

任务可以使用创建队列时获得的全局变量QueueHandle_t，虽然它属于系统的变量，但是任务也可以访问。

# 发送队列消息

`xQueueSend( xQueue, pvItemToQueue, xTicksToWait )`

该函数保留着，主要还是为了兼容旧的FreeRTOS版本，在新的版本中，它等同于` xQueueSendToBack()`，新版本还包括`xQueueSendToFront() and xQueueSendToBack()`.

> 其实队列消息的发送有三种模式

```
/* For internal use only. */
#define	queueSEND_TO_BACK		( ( BaseType_t ) 0 )
#define	queueSEND_TO_FRONT		( ( BaseType_t ) 1 )
#define queueOVERWRITE			( ( BaseType_t ) 2 )
```

前面两种很容易理解，第三种是有特殊用途的，当队列元素个数只有一个的时候。用队列实现信号量，队列元素就只有一个或者是0个（见有关信号量相关文章）。

本小节中，其实就是`queueSEND_TO_BACK`模式。

该函数不应当当ISR中调用，ISR中发送队列消息，有特定的函数`xQueueSendFromISR()`。

发送队列消息时，消息是以值拷贝的方法填充到队列中，所有它会发生一个值拷贝的过程。

消息的结构以及在创建队列时确定了，所以，pvItemToQueue的结构是确定的。

消息发送过程

在一个`for(;;)`实体中操作。

先是创建一个临界区(通过`taskENTER_CRITICAL()`)

```
使用prvCopyDataToQueue()函数将消息插入到队列的尾部
    使用memcopy将消息复制到队列的第一个空闲的位置
    调整Queue_t中的相关指针pcWriteTo，使得它指向下一个空闲的位置
    如果队列已满，则指向队列头，让队列形成一个封闭的环状结构
查询xTasksWaitingToReceive是否有任务正在阻塞等待消息
    如果有，且优先级比当前任务的优先级高，则唤醒等待中的任务
    如果有，而优先级比当前任务低，则将等待的任务转入就绪态
根据需要，唤醒高优先级任务
```

退出临界区。

> 临界区就不多介绍了，它的做法是屏蔽pendSV以下的异常和中断

注意：上面提到的正在等待消息的任务，是按优先级排序的，所以，我们每次只需要处理第一个等待的任务即可（它的优先级肯定是所有正在等待的任务中最高的）。

如何唤醒高优先级任务？非常简单，直接触发一次任务切换就行。  
具体函数是vPortYield()，即产生一个pendSV异常。

# 接收队列消息

> 本小节的重点在于接收的原理和过程，难点在于如何实现阻塞等待。

`xQueueReceive( xQueue, pvBuffer, xTicksToWait )`

ISR中可以调用xQueueReceiveFromISR。

接收消息会把消息从队列中移除。

pvBuffer用于保存从队列中收到的消息，它的大小是在队列创建时确定的。

xTicksToWait表示设置一个超时，超时单位是滴答，等于N表示最多等待N个滴答。

进入 for(;;) 循环
创建一个临界区

```
如果队列中有消息，直接复制消息到pvBuffer中，并删除对应项
接收到消息后，如果有其它更高优先级的任务等待往队列发送消息，则请求任务切换
如果队列中没有消息，则等待：
    vTaskSetTimeOutState( &xTimeOut );
	xEntryTimeSet = pdTRUE;
```
退出临界区

使用`vTaskSuspendAll();`防止任务调度

使用`#define prvLockQueue( pxQueue )`宏锁定队列（宏内部建立一个临界区）

队列被锁定后，任务无法往队列发送消息也无法接收消息

```
如果队列不为空，则将当前任务放入队列结构体的等待接收列表中
void vTaskPlaceOnEventList()的作用正是如此
    该函数会将当前任务加入DelayList
    被加入DelayList中的任务在正常的任务调度中不会被调度
```

使用`prvUnlockQueue( pxQueue );`解锁队列

根据情况，触发任务调度，本任务进入阻塞态。

# Queue的拓展用途

## Queue集

FreeRTOS允许将多个queue加入到一个queue集合中。

前面的Queue，当任务读取Queue时，会阻塞在读取等待，此时任务只能等待一个队列，功能非常有限。Queue集合就是使得任务可以从多个源读取消息。

## Queue邮箱

使用Queue可以实现邮箱功能，往邮箱中发送邮件，所有任务都可以读取到邮件。往邮箱投递邮件，先前的邮件会被覆盖。

读取邮件时，并不会自动移除队列中的元素。

当发送邮件的任务优先级低于接收邮件的任务的优先级时，则所有任务都能及时接收到发送的邮件。

邮箱要求队列中只有一个元素。

## 互斥量

在资源管理中，互斥量/信号量是保证资源不被意外破坏的便捷方法。当然，你还可以使用禁止任务调度来防止多任务“同时”操作资源。

互斥量的使用非常简单，比如防止串口乱码：

`xMutex = xSemaphoreCreateMutex();`

```
xSemaphoreTake( xMutex, portMAX_DELAY );
{
printf( "%s", pcString );
fflush( stdout );
}
xSemaphoreGive( xMutex );
```

创建互斥量，实则是创建一个长度为1的队列，队列的元素item的长度是0.

互斥量需要一个优先级继承的机制，基于这种机制，可以避免优先级反转问题。

queue与互斥量的函数对应关系：

```
#define xSemaphoreCreateMutex() xQueueCreateMutex( queueQUEUE_TYPE_MUTEX )
#define xSemaphoreTake( xSemaphore, xBlockTime )		xQueueGenericReceive( ( QueueHandle_t ) ( xSemaphore ), NULL, ( xBlockTime ), pdFALSE )
#define xSemaphoreGive( xSemaphore )		xQueueGenericSend( ( QueueHandle_t ) ( xSemaphore ), NULL, semGIVE_BLOCK_TIME, queueSEND_TO_BACK )
```

创建互斥量后，先往互斥量中发送一个消息（pxQueue->uxMessagesWaiting == 1），使得队列拥有一个元素（满状态）。

```
QueueHandle_t xQueueCreateMutex( const uint8_t ucQueueType )
	{
	/* Start with the semaphore in the expected state. */
	( void ) xQueueGenericSend( pxNewQueue, NULL, ( TickType_t ) 0U, queueSEND_TO_BACK );
	}
```

当任务take这个互斥量，即是接收队列中的消息，使得队列为空（--( pxQueue->uxMessagesWaiting )）。下一个期望take此互斥量的任务，必定会阻塞在接收队列消息的地方。

如何实现优先级继承：

假设已经有一个任务A获取（take）互斥量。  
当前任务B，在take互斥量时，如果B的优先级比A的优先级高，则将A的优先级提升到与B相同的优先级。由于B的优先级与A的优先级一样高，从而避免了优先级反转。

参考函数：`void vTaskPriorityInherit( TaskHandle_t const pxMutexHolder )`

