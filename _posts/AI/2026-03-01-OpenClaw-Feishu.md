---
layout: post
title: OpenClaw 接入飞书即时通讯指南
categories: "AI"
tags: OpenClaw 飞书 教程
author: Jasper
---

本文记录了将 OpenClaw 接入飞书的完整过程，包括安装、配置向导、大模型 API Key 设置、飞书应用创建，以及遇到的坑和解决方案，帮助你快速搭建自己的 AI 助手机器人。




* content
{:toc}

## 什么是 OpenClaw

OpenClaw 是一个开源的个人 AI 助手框架，支持多种消息渠道接入（飞书、Telegram、Discord 等），可以运行在本地或服务器上。

## 环境要求

* Node.js 22 或更高版本
* macOS / Linux / Windows

检查 Node 版本：
```shell
node --version
```

## 安装 OpenClaw

### 方法一：官方安装脚本（推荐）

```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```

### 方法二：npm 全局安装

```bash
npm install -g openclaw
```

## 安装飞书插件

OpenClaw 需要单独安装飞书插件：

```bash
openclaw plugins install @openclaw/feishu
```

## 运行初始化向导

安装完成后，运行向导进行基础配置：

```bash
openclaw onboard --install-daemon
```

向导会引导你完成：
1. 配置认证信息（API Key）
2. Gateway 设置
3. 添加飞书通道（可选）

### 配置大模型 API Key

在向导中会选择默认模型，推荐使用 MiniMax 或其他支持的模型。

如果你需要手动配置 API Key，编辑 `~/.openclaw/openclaw.json`：

```json
{
  "auth": {
    "profiles": {
      "minimax-cn:default": {
        "provider": "minimax-cn",
        "mode": "api_key",
        "apiKey": "你的 API Key"
      }
    }
  },
  "models": {
    "providers": {
      "minimax-cn": {
        "baseUrl": "https://api.minimaxi.com/anthropic",
        "api": "anthropic-messages",
        "models": [
          {
            "id": "MiniMax-M2.5",
            "name": "MiniMax M2.5"
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "minimax-cn/MiniMax-M2.5"
      }
    }
  }
}
```

### 启动 Gateway

向导运行后会自动启动 Gateway，也可以手动启动：

```shell
openclaw gateway start
```

检查状态：
```shell
openclaw gateway status
```

### 打开控制台 UI

```shell
openclaw dashboard
```

或者直接访问：http://127.0.0.1:18789/

## 飞书应用配置

### 1. 创建应用

1. 访问 [飞书开放平台](https://open.feishu.cn/)
2. 点击「创建企业自建应用」
3. 填写应用名称和描述

### 2. 获取凭据

在「凭据与基础信息」中获取：
- **App ID**（格式：`cli_xxx`）
- **App Secret**

### 3. 配置权限

在「权限管理」中，点击「批量导入」并粘贴以下权限配置：

```json
{
  "scopes": {
    "tenant": [
      "im:message",
      "im:message:readonly",
      "im:message:send_as_bot",
      "im:message.p2p_msg:readonly",
      "im:message.group_at_msg:readonly",
      "im:chat.access_event.bot_p2p_chat:read",
      "im:chat.members:bot_access",
      "im:resource",
      "aily:file:read",
      "aily:file:write",
      "application:application:self_manage",
      "application:bot.menu:write"
    ],
    "user": [
      "aily:file:read",
      "aily:file:write",
      "im:chat.access_event.bot_p2p_chat:read"
    ]
  }
}
```

### 4. 开启 Bot 能力

在「应用能力」>「Bot」中：
1. 开启 Bot 能力
2. 设置 Bot 名称

### 5. 配置事件订阅（重要！）

⚠️ **必须先完成 OpenClaw 配置并启动 Gateway 后，才能成功设置事件订阅！**

1. 在「事件与回调」中
2. 选择「使用长连接接收事件」（WebSocket）
3. 添加事件：`im.message.receive_v1`

### 6. 发布应用

在「版本管理与发布」中：
1. 创建版本
2. 提交发布申请
3. 等待管理员审批（企业应用通常自动通过）

### 7. 管理员授权

应用配置完成后，**必须由企业管理员访问授权链接进行授权**，否则 API 调用会失败。

授权链接格式：
```
https://open.feishu.cn/app/{app_id}/auth?q=contact:contact.base:readonly
```

## OpenClaw 飞书配置

有两种配置方式：

### 方式一：命令行添加（推荐）

```bash
openclaw channels add
```

选择「Feishu」，输入 App ID 和 App Secret。

### 方式二：手动配置

编辑 `~/.openclaw/openclaw.json`：

```json
{
  "channels": {
    "feishu": {
      "enabled": true,
      "appId": "你的 App ID",
      "appSecret": "你的 App Secret"
    }
  }
}
```

### 重启 Gateway

配置完成后，重启 Gateway 使配置生效：

```shell
openclaw gateway restart
```

## 遇到的坑

### 1. 没有安装飞书插件

OpenClaw 默认不包含飞书插件，必须手动安装：
```bash
openclaw plugins install @openclaw/feishu
```

### 2. 没有设置事件与回调

在飞书开放平台创建应用后，如果没有设置「事件与回调」并订阅相关事件，OpenClaw 将无法接收消息。

### 3. 事件与回调设置顺序错误

**必须先完成 OpenClaw 与飞书的连接配置（即在 OpenClaw 配置文件中填入 appId 和 appSecret 并启动 Gateway）后，才能成功设置事件与回调**，否则会验证失败。

### 4. 验证飞书账号环节

OpenClaw 文档中没有明确提到，还需要进行一次管理员账号的授权验证，导致初期配置一直失败。

### 5. Token 消耗问题

在飞书开放平台网页上反复操作会消耗大量 token，建议提前了解需要配置的选项，减少不必要的操作。

### 6. Web UI 访问问题

OpenClaw Gateway 默认绑定 `127.0.0.1`（本地回环地址），关闭 Web 服务后，原来的 URL 将无法访问。

如果需要长期使用，建议：
- 将 Gateway 设为系统服务（LaunchAgent）开机自启
- 如需外网访问，配置 tailscale 或使用内网穿透

## 总结

OpenClaw 接入飞书的核心步骤：

1. 安装 OpenClaw：`npm install -g openclaw`
2. 安装飞书插件：`openclaw plugins install @openclaw/feishu`
3. 运行初始化向导：`openclaw onboard --install-daemon`
4. 配置大模型 API Key
5. 飞书开放平台创建应用并开启权限
6. **发布应用** + **管理员授权**
7. 配置回调地址（需要公网或内网穿透）
8. 在 OpenClaw 配置文件中填入 appId 和 appSecret
9. 重启 Gateway

希望这篇记录能帮你避开这些坑～

---

**参考**：
- [OpenClaw 官方文档](https://docs.openclaw.ai)
- [飞书开放平台](https://open.feishu.cn/)
