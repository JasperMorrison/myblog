---
layout: post
title: Android Apk 版本控制
categories: "Android"
tags: android AppVersion 翻译
author: Jasper
---

* content
{:toc}

这里记录怎么定义apk的版本号和版本名，怎么一次性控制多个分支版本的版本号和版本名，以及怎么获得一个已经编译好的apk的版本信息。



## 获得一个现成apk的版本信息

### 方法一

使用apktool进行反编译，查看apktool.yml文件可以看到。  
例如：

```
 20 versionInfo:
 21   versionCode: '1' //正整数，大到够用一辈子（2100000000）
 22   versionName: '1' //Name没有要求跟versionCode保持一致，只要是String或者字符序列即可
```

比如，我们平时看到的某个app的版本信息是6.0.1200，其实就是versionName  
是用来给用户看的，而实际的versionCode是对用户隐蔽的，只要你认为需要就把它+1，  
以表示你完成了一个模块或者修复了一个重要的bug.

### 方法二

如果知道android:label的值，也就是一个apk的名称。可以进入Settings->apps里面查看。

## 设置apk的版本信息

在\<manifest\>中定义
versionCode和
versionName

在Gradle中定义以上两个信息。在Gradle中定义的信息会覆盖掉\<manifest\>的版本信息。  
在productFlavors{}中，可以根据开发者需要定义多个版本分支的版本信息。

**这两个值写在编译好的二进制文件中，具体在哪里呢？**
这个需要查看apktool的有关内容了。

## 官方文档Version Your App的简单翻译

App的版本信息很重要，关系到App的升级和维护策略。有以下几点：

- App的使用者需要明确地知道安装在机器里的App的现有版本信息，以及可供升级的版本信息。
- 开发者开发和发布的App，需要通过版本信息控制对启动App的兼容性。
- App发布平台服务需要熟知App的版本信息，以控制推送更新以及兼容性。

Android系统并不使用应用版本信息控制第三方App的升级、降级以及兼容性。这些工作都应该由开发者斟酌和决定，负责维护自己的app正常工作。
对应的，Android系统采用类似minSdkVersion这样的设置控制sdk兼容性，而且这个是强制性的。

在Gradle中设置Android版本的例子：

```
android {
  ...
  defaultConfig {
    ...
    versionCode 2
    versionName "1.1"
  }
  productFlavors {
    demo {
      ...
      versionName "1.1-demo"
    }
    full {
      ...
    }
  }
}
```
这里有三个版本特性，分别是默认的、demo、full。对应的会在Gradle的tasks出现这三个任务名称可供选择。  
开发这也可以利用productFlavors的相关知识控制这三个版本特性的编译情况。类似的，你可以还可以别的特性，比如test特性，以专门用于app的测试工作。

在Gradle进行sdk兼容性设置：

```
android {
  ...
  defaultConfig {
    ...
    minSdkVersion 14
    targetSdkVersion 24
  }
  productFlavors {
    main {
      ...
    }
    afterLollipop {
      ...
      minSdkVersion 21
    }
  }
}
```

## 参考文献

[Version Your App](https://developer.android.com/studio/publish/versioning.html#minsdkversion)
[在Gradle中根据git tag信息自动生成versionCode和versionName](http://www.oschina.net/code/snippet_2545423_53287)
