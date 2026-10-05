---
title: Akari
description: 面向 Linux 登录管理器的编译期 Flutter 主题。
template: splash
hero:
  tagline: 由你掌控主题的 Linux 登录管理器。组合 Flutter 组件、编写场景，并构建为一个原生可执行文件。
  actions:
    - text: 从这里开始
      link: /Akari/zh-cn/getting-started/quick-start/
      icon: right-arrow
    - text: 开发主题
      link: /Akari/zh-cn/guides/themes/
      variant: minimal
---

## 选择阅读路径

| 目标 | 阅读内容 |
| --- | --- |
| 准备开发环境 | [环境配置](getting-started/installation.md) |
| 预览现有主题 | [快速开始](getting-started/quick-start.md) |
| 创建自己的主题 | [主题开发](guides/themes.md) |
| 检查多显示器或独立登录缩放 | [显示测试](guides/display-testing.md) |
| 查找类型和方法 | [API 参考](reference/api.md) |
| 了解实现方式 | [代码导航](architecture/code-map.md) |

## Akari 的工作方式

Flutter 前端负责呈现和交互。Rust 桥接层负责 greetd/PAM 对话及系统操作。主题通过 Theme SDK 接收类型化的显示状态和语义操作回调，无需接管身份验证。

场景描述布局、可见性和动效。构建过程从场景 JSON 生成 Dart 代码，并将所选主题及其资源编译进可执行文件。

本文档与仓库中的代码保持同步。你可以从桌面预览或模拟后端开始；[独立 greetd 测试工具](guides/greetd-testing.md)则是一套单独的开发测试流程。
