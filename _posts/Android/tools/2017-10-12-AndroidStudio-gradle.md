---
layout: post
title: Android Studio Gradle 技巧
categories: Android
tags: Android Tool Gradle
author: Jasper
---

* content
{:toc}

本文记录在AndroidStudio中配置Gradle的常用技能和技巧，内容可能涉及多版本、多module、Gradle与源码交互等内容。



## 自动重命名apk名称

即对output.outputFile的重定义

```java
android {
    //修改生成的apk名字
    applicationVariants.all { variant ->
        variant.outputs.each { output ->
            def appName
            if (variant.name.contains("cleanux")){
                appName = 'CleanuxTest-v'
            }
            if(variant.name.contains("ostest")){
                appName = 'OsTest-v'
            }
            def oldFile = output.outputFile
            def releaseApkName
            releaseApkName = appName + versionName + '.apk'
            output.outputFile = new File(oldFile.parent, releaseApkName)
        }
    }
}
```	

## dependencies 的版本问题

定义dependencies，很多时候本地没有对应版本的库，这时需要重新设置。但有时候网络比较坑，况且你又懒得去查版本号，怎么办？直接在不明确的地方用一个 + 号替代。

```
dependencies {
    compile 'com.android.support:appcompat-v7:24+'
    compile 'com.android.support:support-core-utils:24+'
    compile 'com.android.support:support-compat:24+'
}
```

## 一套代码两个主逻辑

假如有这么一个需求，同样一套代码实现两个不同的事情，但是使用的基础代码块是一样的。通俗的做法可能是另起一个sourceSet，然后把公共的代码包含进来编译。  
现在尝试让java代码根据编译属性进行自动选择：  

```
    productFlavors {
        cleanux {
            buildConfigField "boolean", "CLEAN_UX", "true"  //编译配置
        }
        ostest {            
        }
    }
```

代码中获取编译配置

```java
        if (BuildConfig.CLEAN_UX){
            startActivity(new Intent(this, ActivityTestService.class));
        }else {
            startActivity(new Intent(this, OsTestActivity.class));
        }
```

## applicationId的使用与注意事项

applicationId属于应用的唯一标识符，区别去java命令空间的包名package。

```
    productFlavors {
        cleanux {
            applicationId "com.example.myapp.cleanuxtest"
        }
        ostest {
            applicationId "com.example.myapp.ostest"
        }
    }
```

build - select build variant 选择需要编译的Flavor。

最后产生的两个apk可以同时运行在手机上。

值得注意的而是，Provider是对外开放的，它的命名必须是全局唯一，为了不产生冲突，可以根据applicationId设置：

```xml
        <provider
            android:name="android.support.v4.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/path"/>
        </provider>
```

另外 摘录一段官方的文字

```
您还需要了解以下内容：尽管清单 package 和 Gradle applicationId 可以具有不同的名称，
但构建工具会在构建结束时将应用 ID 复制到 APK 的最终清单文件中。所以，如果您在构建后检查 AndroidManifest.xml 文件，
package 属性发生更改就不足为奇。实际上，Google Play 商店和 Android 平台会注意 package 属性来标识您的应用；
所以构建利用原始值后（用作 R 类的命名空间并解析清单类名称），它将会舍弃此值并将其替换为应用 ID。
```

也就是说，apk文中的AndroidManifest.xml文件中的package将会被自动替换为applicationId。

最后

Context.getPackageName() 得到的是applicationId，而不是java命名空间的package。

## 参考文献

[https://developer.android.com/studio/build/application-id.html?hl=zh-cn](https://developer.android.com/studio/build/application-id.html?hl=zh-cn)  
[https://developer.android.com/topic/libraries/support-library/rev-archive.html#rev24-2-1](https://developer.android.com/topic/libraries/support-library/rev-archive.html#rev24-2-1)  
[https://developer.android.com/topic/libraries/support-library/revisions.html](https://developer.android.com/topic/libraries/support-library/revisions.html)  