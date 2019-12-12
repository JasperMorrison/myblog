---
layout: post
title: Android应用资源管理
categories: Android
tags: Android resource
author: Jasper
---

* content
{:toc}

本文记录对Android应用资源管理的系统学习。虽然我们按照说明会适配不同的设备，放置资源，开发UI，但是内部实现机理是否系统学习过呢，摆脱一遇到问题就百度/谷歌的水平是不是很爽呢。同时，这样系统的认识有助于对app逆向处理（呵呵，这才是重点）。



## App Resource Class（分类）

- assets, 属于用户资产，aapt原封不动的加载到apk中
- res， Resouces简写属于app资源，aapt按照Android的处理方式进行二进制处理和对应的索引工作
  - animator，描述属性动画。
  - anim，描述[补间动画](http://blog.csdn.net/sgx425021234/article/details/9195829)。
  - color,描述对象颜色状态。
  - drawable，描述可绘制对象。
  - layout，描述应用程序界面布局。
  - menu， 描述应用程序菜单，例如，Options Menu、Context Menu和Sub Menu。
  - raw，它们和assets类资源一样，原装不动地打包在apk文件中，并会被赋予资源ID。  
    Resources res = getResources();  
    InputStream is = res .openRawResource(R.raw.filename);  
  - values，描述值，例如，arrays.xml、colors.xml、dimens.xml、strings.xml和styles.xml文件。
  - xml，这类任何合适的xml文件，当不知道放哪的时候，放这吧。

## [Providing Resource](https://developer.android.com/guide/topics/resources/providing-resources.html)

- 按照资源分类进行放置
- 根据修饰语动态适配资源，低版本设备自动忽略高版本才定义的修饰符，以下修饰语类型，如何采用组合形式，必须按照从前到后的顺序设置：
  - MCC + MNC (mobile country code + mobile network code)
  - [Language and region](http://www.iso.org/iso/en/prods-services/iso3166ma/02iso-3166-code-lists/list-en1.html)
    - The language is defined by a two-letter [ISO 639-1 language code](http://www.loc.gov/standards/iso639-2/php/code_list.php), optionally followed by a two letter [ISO 3166-1-alpha-2 region code](https://www.iso.org/obp/ui/#search/code/) (preceded by lowercase "r").   
例子：Estonia（爱沙尼亚）的Estonian（爱沙尼亚语）编码  
先从第一个链接中得到语言et，再重第二个链接得到地区EE，结果为et-rEE。  
如果是写在Android系统源码中(build/target/product/languages_full.mk)，用et_EE，在app的资源文件夹使用et-rEE。  
当我们从api获得语言列表`android.content.res.Resources.getSystem.getAssets.getLocales.toList`(scala)，显示的是et-EE。
  - Layout Direction(ldrtl & ldltr) (一般不使用，除非文字方向要求反过来读，像古文)
  - smallestWidth(sw\<N\>dp)（最小宽度）:
    - 不考虑屏幕的方向，长宽谁小取谁
    - 如果UI被其它元素占用，那么这个值会适当变小，比如屏幕最小宽度320，UI被100宽度的元素占据，sw被设置成320-100=220
    - 如果设置多个sw，将采用最接近的不超过实际宽度的sw。比如屏幕最小宽度320，设置sw1=280 sw2=290 sw3=328，sw=sw2=290.
  - 可用宽度 w\<N\>dp
  - 可用高度 h\<N\>dp
  - 屏幕大小： 如果设定的内容并没有提供，将[使用最合适的资源](https://developer.android.com/guide/topics/resources/providing-resources.html#BestMatch)；如果使用比实际屏幕大的资源，应用程序将崩溃（比如在large的机器上设定xlarge资源）。
    - small >320x426
    - normal >320x470
    - large >480x640
    - xlarge >720x960
  - Screen aspect，屏幕的大体形状，长得长不长，long or notlong，直接就是WQVGA, WVGA, FWVGA屏，前缀是W/FW
  - Round screen,round or notround
  - 屏幕方向，port or land
  - UI mode，UI在什么设备上显示？车载？电视机？等等，[设备类型查询和判别方法](https://developer.android.com/training/monitoring-device-state/docking-monitoring.html)
  - Night mode
  - Screen pixel density (dpi)，大约值
    - ldpi - 120
    - mdpi - 160 
    - hdpi - 240
    - xhdpi - 320
    - xxhdpi - 480
    - xxxhdpi - 640
    - nodpi - bitmap的情况下使用
    - tvdpi - 213 电视dpi
    - anydpi - 当采用[矢量图](https://developer.android.com/training/material/drawables.html#VectorDrawables)时采用
  - 屏幕是否可触摸
  - 键盘可用性，可能一些商用嵌入式设备会用到
  - Primary text input method，文件输入方式，nokeys qwerty 12key
  - Primary non-touch navigation method，硬件设备的导航方式
  - [API-level](https://developer.android.com/guide/topics/manifest/uses-sdk-element.html#ApiLevels)
- 注意修饰符定义的规则：
  - 可以多个定义
  - 必须按照表的顺序
  - 不区分大小写
  - 一种类型只能指定在两个 - 之间，如果同一种类型的修饰符需要同时定义多个，请使用多个文件的形式

另外，还可以给资源定义别名，定义资源的时候注意一些技巧。

## [访问资源](https://developer.android.com/guide/topics/manifest/uses-sdk-element.html#ApiLevels)

- code 中 [\<package_name\>.]R.\<resource_type\>.\<resource_name\>
- xml 中 @[\<package_name\>:]\<resource_type\>/\<resource_name\>
- 引用style样式快速定义?[\<package_name\>:][\<resource_type\>/]\<resource_name\>
- 引用系统自带资源，在引用的资源面前加上'Android.'，如`android.R.layout.simple_list_item_1`

## [Handling Configuration Changes](https://developer.android.com/guide/topics/resources/runtime-changes.html#HandlingTheChange)

某些配置会动态改变（screen orientation, keyboard availability, and language），一旦发生，Activity会执行onDestroy()->onCreate()，以使用变化后的适配资源。onSaveInstanceState()函数能让开发者找回Activity的当前状态，参考[Saving and restoring activity state.](https://developer.android.com/training/basics/activity-lifecycle/recreating.html).为保证你的app能在Activity自动重启的时候不丢失状态，比如配置改变或者进来一个电话，请学习Activity的生命周期相关内容。如果重启后需要保存大量数据，回复网络连接或者执行其它密集操作，将会影响用户体验。

两个解决方案：

- 携带一个object到新的Activity实例  
onSaveInstanceState()不会用来处理大量数据的，比如bitmap、序列化再反序列化，那么采用Fragment将是一个很好的策略。添加到Activity中的Fragment可以被标志为不执行Destroy操作，从而可以被新Activity对象直接使用。  
To retain stateful objects in a fragment during a runtime configuration change:
  - Extend the Fragment class and declare references to your stateful objects.
  - Call setRetainInstance(boolean) when the fragment is created.
  - Add the fragment to your activity.
  - Use FragmentManager to retrieve the fragment when the activity is restarted.
While onCreate() is called only once when the retained fragment is first created you can use onAttach() or onActivityCreated() to know when the holding activity is ready to interact with this fragment.  
在Activity中采用FragmentManager加载Fragment。然后在onPause()中采用isFinishing()判断是否需要保存数据到Fragment中。  
注意：不应该保存本身绑定到Activity的对象，比如Drawable, an Adapter, a View or any other object that's associated with a Context，否则，这些资源将常驻内存(资源泄露，即使Activity重建，也不会使用它们，而是重新创建对象)，这将消耗大量的用户内存。

- 屏蔽自动重启，采用回调的方式，在需要的情况下人为重启  
介入篇幅和实用性，不详细记录。大体是定义Activity的configuration，然后再回调函数中处理。多个configurations配置的情况可能有别，需要注意，比如`android:configChanges="orientation|screenSize"`.

## Localization（地方化）

系统是怎么根据语言-区域挑选合适的或者默认的资源？  
请保持添加默认资源，再添加可选资源。优先级请看Providing Resource那张修饰符表。  
除了普通的资源外，layout也可以根据修饰符表进行适配，在不同情况下使用不同的layout。  
测试方法：  
采用模拟器，设置persist.sys.locale的值，如`setprop persist.sys.locale fr-CA;stop;sleep 5;start`

Android7有哪些更新？  
- [ICU4J Android Framework APIs](https://developer.android.com/guide/topics/resources/icu4j-framework.html) 国际化支持库的子集
- 语言和区域的选择更智能

## 内嵌复杂的XML资源

当实现一个UI需要多个XML文件的时候，可以使用aapt内联功能把它们写到一个XML文件中。

## App编译打包过程

![aapt](http://dl.iteye.com/upload/attachment/288325/ee45e498-97d2-3d40-87c3-5c4247cb2ff8.png)  
图：apk打包过程
源码解析见参考文献。

## AndroidManifest.xml二进制文件结构

![](http://img.blog.csdn.net/20160123095309010?watermark/2/text/aHR0cDovL2Jsb2cuY3Nkbi5uZXQv/font/5a6L5L2T/fontsize/400/fill/I0JBQkFCMA==/dissolve/70/gravity/Center)  
图：AndroidManifest.xml(Binary)

## Resoures.arsc文件结构

详细解析，参考`frameworks/base/include/androidfw/ResourceTypes.h`文件

![](http://img.blog.csdn.net/20160203162759825?watermark/2/text/aHR0cDovL2Jsb2cuY3Nkbi5uZXQv/font/5a6L5L2T/fontsize/400/fill/I0JBQkFCMA==/dissolve/70/gravity/Center)  
![](http://img.blog.csdn.net/20160623160422218?watermark/2/text/aHR0cDovL2Jsb2cuY3Nkbi5uZXQv/font/5a6L5L2T/fontsize/400/fill/I0JBQkFCMA==/dissolve/70/gravity/Center)  
图：resources.arsc(Binary)


## classes.dex文件结构

参考另一篇文章《dex文件格式分析例子》

![](/images/Reverse/dex-header.png)  
图：classes.dex(Binary)

## 参考文献

[App Resources](https://developer.android.com/guide/topics/resources/index.html)  
[Android资源管理框架（Asset Manager）简要介绍和学习计划](http://blog.csdn.net/luoshengyang/article/details/8738877)



