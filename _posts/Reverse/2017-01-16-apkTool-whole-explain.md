---
layout: post
title:  "apkTool -- 全解析"
categories: Android逆向工程
tags: android reverse
author: Jasper
---

* content
{:toc}

apkTool是Android apk反编译，修改，回编的工具。可以把二进制形式的Android apk 反编译出可阅读的AndroidManifest.xml文件，smali文件和资源文件。
同时支持将修改后的文件回编打包成新的apk，实现Android apk的直接修改。当apk需要使用framework资源时，使用 apkTool if 命令可以安装framework资源。apkTool是开源项目，采用Java编写，专人维护和更新，请勿用于非法目的。具体使用方法和说明请查阅[ apkTool github ](https://github.com/iBotPeaches/Apktool)。



## 准备

- git clone --depth=1 \<gitpath to apkTool\>
- build apkTool
- Add apkTool project to Android Studio

##  命令演示

演示一：decode apk

```
➜  apktool-demo java -jar ~/updateScript/lib/apktool_2.2.1.jar d Hangouts.apk 
I: Using Apktool 2.2.1 on Hangouts.apk
I: Loading resource table...
I: Decoding AndroidManifest.xml with resources...
I: Loading resource table from file: /home/jaren/.local/share/apktool/framework/1.apk
I: Renamed manifest package found! Replacing com.google.android.talk with com.google.android.apps.hangouts
I: Decoding file-resources...
I: Decoding values */* XMLs...
I: Baksmaling classes.dex...
I: Baksmaling classes2.dex...
I: Copying assets and libs...
I: Copying unknown files...
I: Copying original files...
```

演示二：encode apk

```
➜  apktool-demo java -jar ~/updateScript/lib/apktool_2.2.1.jar b Hangouts    
I: Using Apktool 2.2.1
I: Checking whether sources has changed...
I: Smaling smali folder into classes.dex...
I: Checking whether sources has changed...
I: Smaling smali_classes2 folder into classes2.dex...
I: Checking whether resources has changed...
I: Building resources...
I: Copying libs... (/lib)
I: Building apk file...
I: Copying unknown files/dir...
```

## 解析decode apk

`Main.java`

```java
	if (opt.equalsIgnoreCase("d") || opt.equalsIgnoreCase("decode")) {
                cmdDecode(commandLine);
                cmdFound = true;
        }
```

```java
    private static void cmdDecode(CommandLine cli) throws AndrolibException {
        ApkDecoder decoder = new ApkDecoder();
	decoder.setApkFile(new File(apkName));
	try {
            decoder.decode();
        }
```

`ApkDecoder.java`

```java
public class ApkDecoder {
    public ApkDecoder() {
        this(new Androlib());
    }
    public void setApkFile(File apkFile) {
        mApkFile = new ExtFile(apkFile);
        mResTable = null;
    }
```

- resources.asrc ?
  - yes
    - hasManifest -> mAndrolib.decodeManifestWithResources(mApkFile, outDir, getResTable());
  - no 
    - hasManifest -> mAndrolib.decodeManifestFull(mApkFile, outDir, getResTable());  
mResTable = mAndrolib.getResTable(mApkFile, hasResources);
- hasSources()?
  - yes -> mAndrolib.decodeSourcesSmali(mApkFile, outDir, "classes.dex", mBakDeb, mApi);
- hasMultipleSources() -> file.endsWith(".dex") except classes.dex -> mAndrolib.decodeSourcesSmali(mApkFile, outDir, file, mBakDeb, mApi);
- mAndrolib.decodeRawFiles(mApkFile, outDir);  
mAndrolib.decodeUnknownFiles(mApkFile, outDir, mResTable);  
mUncompressedFiles = new ArrayList<String>();  
mAndrolib.recordUncompressedFiles(mApkFile, mUncompressedFiles);  
mAndrolib.writeOriginalFiles(mApkFile, outDir);  
writeMetaFile();

**mResTable的获取**

`mAndrolib.getResTable(mApkFile, hasResources);`
-> mAndRes.getResTable(apkFile, hasResources);

AndroidResources.java

```java
    public ResTable getResTable(ExtFile apkFile, boolean loadMainPkg)
            throws AndrolibException {
        ResTable resTable = new ResTable(this);
        if (loadMainPkg) {
            loadMainPkg(resTable, apkFile);
        }
        return resTable;
    }

ResPackage[] pkgs = getResPackagesFromApk(apkFile, resTable, false);
--> 
try {
            BufferedInputStream bfi = new BufferedInputStream(apkFile.getDirectory().getFileInput("resources.arsc"));
            return ARSCDecoder.decode(bfi, false, false, resTable).getPackages();
        } 

-->
```

解析resources.arsc

```
    public static ARSCData decode(InputStream arscStream, boolean findFlagsOffsets, boolean keepBroken,
                                  ResTable resTable)
            throws AndrolibException {
        try {
            ARSCDecoder decoder = new ARSCDecoder(arscStream, resTable, findFlagsOffsets, keepBroken);
            ResPackage[] pkgs = decoder.readTableHeader();
            return new ARSCData(pkgs, decoder.mFlagsOffsets == null
                    ? null
                    : decoder.mFlagsOffsets.toArray(new FlagsOffset[0]), resTable);
        } catch (IOException ex) {
            throw new AndrolibException("Could not decode arsc file", ex);
        }
    }
```

### 后续

偷懒了，但不想删除写过的，有需要根据本文信息进行检索。

```
### Decode AndroidManifest.xml with/without resources.arsc

##  解析命令二

##  解析命令三

##  总结
```

## 参考文献

[apkTool官方文档](https://ibotpeaches.github.io/Apktool/)  
[手把手教你解析resources.arsc，参考里面对这种内容的解释](http://blog.csdn.net/beyond702/article/details/51744082)  
[了解AssetManager对资源的加载过程](http://blog.csdn.net/luoshengyang/article/details/8806798)  

