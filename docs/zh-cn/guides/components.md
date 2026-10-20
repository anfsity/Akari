---
title: 开发主题组件
description: 用 Flutter 编写主题组件，读取登录状态并响应用户操作。
---

主题组件是标准的 Flutter Widget，负责展示 `GreeterHost` 提供的类型化状态并触发操作回调，无需直接处理 PAM 认证逻辑或 D-Bus 通信。

## 1. 在组件工厂中映射节点

`ThemeDefinition.components` 接收 `GreeterThemeContext`（包含 `tokens` 与 `host`），并返回 `GreeterThemeComponents`。渲染时，运行时调用 `build(context, node)` 将场景节点的 `component` 标识符转换为具体的 Widget：

- **复用内置组件集**：直接使用 `StandardGreeterComponents`，并沿用 fallback 场景中的组件标识符。
- **自定义组件工厂**：在 `*.scene.json` 与工厂实现中约定专属的组件标识符。
- **解析节点属性**：节点的 `node.properties` 是字符串键值映射，由对应组件自行解析其业务含义。

## 2. 按需订阅局部状态（Slot）

使用 `SceneRegion` 仅订阅当前组件所需的 Slot，避免账户、会话或电源状态变化引起无关重绘：

```dart
import 'package:flutter/material.dart';
import 'package:theme_sdk/theme_sdk.dart';

class ServiceLabel extends StatelessWidget {
  const ServiceLabel({required this.host, super.key});

  final GreeterHost host;

  @override
  Widget build(BuildContext context) {
    return SceneRegion<ServiceSlots>(
      valueListenable: host.serviceSlots,
      builder: (context, slots) => Text(slots.mode.name),
    );
  }
}
```

:::tip
`SceneRuntime` 已默认在每个场景节点外层包裹 `RepaintBoundary`。除非性能分析表明某个复杂子组件需要独立重绘，否则无需在组件内部重复添加 `RepaintBoundary`。
:::

## 3. 调用宿主操作回调

通过 `GreeterHost` 回调响应用户交互，并根据 Slot 状态控制按钮可用性、键盘导航与无障碍焦点：

| 宿主回调 | 作用 |
| --- | --- |
| `onSelectUser` | 切换登录账户 |
| `onSelectSession` | 选择要启动的桌面会话 |
| `onRespondToPrompt` | 提交当前认证提示的输入内容 |
| `onStartSession` | 启动已通过认证的桌面环境 |
| `onRequestPowerAction` | 请求挂起、重启或关机 |

:::caution[凭据控制器的所有权]
密码输入框借用宿主的 `host.credentialController` 与 `host.credentialFocusNode`。它们的生命周期由外层应用管理——主题组件**不得**调用它们的 `dispose()`，也严禁将密码文本复制到场景属性或日志中。
:::

## 4. 遵守挂载生命周期约定

- **隐藏节点的资源开销**：在进入/退出过渡动画期间，不可见节点仍处于挂载状态。请避免在隐藏状态下运行高开销定时器，并在组件卸载（`dispose`）时释放自有订阅。
- **动效控制器所有权**：`SceneMotionBuilder` 直接使用运行时传入的 `Animation<double>`，无需自行创建或销毁节点进出场的 `AnimationController`。

详细的 Slot 类型定义请查阅 [API 参考](../reference/api.md)，前后端职责边界请参阅[前端架构](../architecture/frontend.md)。
