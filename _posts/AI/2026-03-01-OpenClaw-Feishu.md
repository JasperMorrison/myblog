---
layout: post
title: OpenClaw 接入飞书即时通讯指南
categories: "AI"
tags: OpenClaw 飞书 教程
author: Jasper
---

* content
{:toc}

本文记录了将 OpenClaw 接入飞书的过程，包括安装、配置、飞书应用创建，以及遇到的坑和解决方案。

## 什么是 OpenClaw

OpenClaw 是一个开源的个人 AI 助手框架，支持多种消息渠道接入（飞书、Telegram、Discord 等），可以运行在本地或服务器上。

## 安装 OpenClaw

OpenClaw 支持多种安装方式，本文使用 npm 全局安装：

```shell
npm install -g openclaw
```

安装完成后，运行初始化向导：

```shell
openclaw onboard
```

按照提示配置工作空间、默认模型（推荐 MiniMax）等。

## 飞书应用配置

### 1. 创建应用

1. 访问 [飞书开放平台](https://open.feishu.cn/)
2. 创建企业自建应用
3. 在「权限管理」中开启以下权限：
   - 消息权限（全部开启）
   - 必要的通讯录权限

### 2. 发布应用

创建应用后，需要点击「发布」按钮，将应用发布到企业工作台。

### 3. 事件与回调配置（重要！）

这是最容易踩坑的地方：

1. 在应用详情页面，点击「事件与回调」
2. 设置**回调 URL**：需要填写公网可访问的 URL（OpenClaw Gateway 需要暴露到公网，或者使用内网穿透）
3. 订阅事件：选择需要接收的事件类型

**注意**：必须先完成 OpenClaw 与飞书的连接配置（即在 OpenClaw 配置文件中填入 appId 和 appSecret 并启动 Gateway）后，才能成功设置事件与回调，否则会验证失败。

### 4. 管理员授权

应用配置完成后，**必须由企业管理员访问授权链接进行授权**，否则 API 调用会失败。

授权链接格式：
```
https://open.feishu.cn/app/{app_id}/auth?q=contact:contact.base:readonly
```

## OpenClaw 飞书配置

编辑 `~/.openclaw/openclaw.json`，配置飞书通道：

```json
{
  "channels": {
    "feishu": {
      "enabled": true,
      "appId": "你的 appId",
      "appSecret": "你的 appSecret"
    }
  }
}
```

重启 Gateway 使配置生效：

```shell
openclaw gateway restart
```

## 遇到的坑

### 1. 没有设置事件与回调

在飞书开放平台创建应用后，如果没有设置「事件与回调」并订阅相关事件，OpenClaw 将无法接收消息。

### 2. 验证飞书账号环节

OpenClaw 文档中没有明确提到，还需要进行一次管理员账号的授权验证，导致初期配置一直失败。

### 3. Token 消耗问题

在飞书开放平台网页上反复操作会消耗大量 token，建议提前了解需要配置的选项，减少不必要的操作。

### 4. Web UI 访问问题

OpenClaw Gateway 默认绑定 `127.0.0.1`（本地回环地址），关闭 Web 服务后，原来的 URL 将无法访问。

如果需要长期使用，建议：
- 将 Gateway 设为系统服务（LaunchAgent）开机自启
- 如需外网访问，配置 tailscale 或使用内网穿透

## 总结

OpenClaw 接入飞书的核心步骤：
1. npm 安装 OpenClaw
2. 飞书开放平台创建应用并开启权限
3. **发布应用** + **管理员授权**
4. 配置回调地址（需要公网或内网穿透）
5. 在 OpenClaw 配置文件中填入 appId 和 appSecret
6. 重启 Gateway

希望这篇记录能帮你避开这些坑～

---

**参考**：
- [OpenClaw 官方文档](https://docs.openclaw.ai)
- [飞书开放平台](https://open.feishu.cn/)
