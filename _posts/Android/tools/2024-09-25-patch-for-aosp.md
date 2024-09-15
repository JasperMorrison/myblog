---
layout: post
title: 向AOSP提交patch经验分享
categories: Android
tags: Android AOSP
author: Jasper
---

* content
{:toc}

分享一次向AOSP提交patch的经验，个人开发者可能很难被merge，但重在参与。



# 代码准备

首先要下载AOSP代码，这里推荐兰州大学的 https://help.mirrors.cernet.edu.cn/aosp-monthly/ ，下载后解压到本地。


# 修改代码

1. 创建分支 repo start <my_branch>
2. 修改代码
3. 编译
4. 验证

# 设置代理

1. 终端代理，比如：` export http_proxy=http://127.0.0.1:8118`
2. git代理，比如：` git config --global http.proxy 'http://127.0.0.1:8118'`

如果代理需要用户名和密码，需要使用 `http://username:password@127.0.0.1:8118` 格式，如果密码中包含@，需要使用 `http://username%40password:127.0.0.1:8118` 格式。

# 提交代码

参考官方提交patch教程：https://source.android.google.cn/docs/setup/contribute/submit-patches?hl=zh-cn

1. 签署协议、创建账号等等
2. 同步远程仓库，并rebase，处理冲突，可以直接使用 `git pull --rebase`
3. 创建密码，将页面显示的内容直接复制到shell终端，运行即可。（这里补贴内容有点抽象，有了这一步，就不需要像我们通过https提交github那样，要手动输入用户名密码啦。用到自知）
4. 上传 repo upload

# 创建 issuse

参考 https://source.android.google.cn/docs/setup/contribute/report-bugs?hl=zh-cn  
进入 https://issuetracker.google.com/issues  
创建issuse，根据要求的格式详细填写内容，可以先搜索一个别人的issuse，然后参考着修改。

得到issue id后，在patch中添加 `Bug: <issue id>` 即可，或者直接贴issue的url。

# 指定reviewer

gerrit会自动推荐一些reviewer，我不懂，选了前面两个。

# 踩过的坑

1. 清华镜像站已经不好用了，找不到仓库包，建议使用兰州大学镜像站。
2. 代理问题，需要设置终端代理和git代理。
3. repo upload 时提示tsl问题，设置git代理完美解决。
4. repo sync . 时也提示tsl问题，不清楚如果当时设置了git代理是否能解决，我使用了另一个技巧，自己增加一个 `git remote`，并将https改为http，然后同步成功。

# 其它发现或者建议

如果你不需要编译验证（已经基于最新aosp验证过了，只是为了将patch提交给google），其实不需要同步整个aosp仓库也是可以的，直接到gerrit上clone对应的子仓库，比如 `git clone https://android.googlesource.com/platform/frameworks/base`，在上面修改、push就行了。
