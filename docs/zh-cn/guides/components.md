---
title: 开发主题组件
description: 读取类型化宿主状态，同时保持身份验证归属清晰。
---

## 组件工厂

`ThemeDefinition.components` 接收一个 `GreeterThemeContext`，其中包含主题 token 和 `GreeterHost`。工厂返回 `GreeterThemeComponents`，通过 `build(context, node)` 将场景组件标识符映射到 Flutter widget。这些标识符仅对该工厂有意义；Scene 运行时不规定统一的 widget 目录。

使用 `StandardGreeterComponents` 时，请沿用 fallback 场景支持的标识符。自行编写工厂时，确保场景和工厂对每个标识符的定义一致。节点的 `properties` 是由对应组件负责解释的字符串配置；应由组件在理解其含义的位置进行解析。

## 订阅一个区域

使用类型化 slot 订阅 widget 要显示的内容。例如，服务状态小组件只需订阅 `serviceSlots`：

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

这样，账户、会话或电源状态的无关更新不会触发该标签重建。`SceneRuntime` 已为每个场景节点设置重绘边界。只有性能分析证明确有需要时，才添加额外边界。

## 分发语义操作

组件调用宿主回调，例如 `onSelectUser`、`onSelectSession`、`onRespondToPrompt` 和 `onRequestPowerAction`。请使用对应 slot 启用控件，并保留原生键盘、焦点和无障碍行为。身份验证状态、传输对象和 D-Bus 调用属于登录功能层及后端。

凭据 widget 借用 `credentialController` 和 `credentialFocusNode`；它们由所有者释放，主题 widget 不得释放它们。不要将凭据文本复制到场景属性、视觉配置或日志。

## 遵循挂载生命周期

组件出现动画和预热机制可能会让隐藏节点继续保持挂载。隐藏期间的订阅和计时器应尽量轻量；widget 卸载时，释放组件自己创建的资源。动效 builder 借用由运行时驱动的动画，不拥有动画控制器。

精确类型请查阅 [API 参考](../reference/api.md)，所有权细节请查阅[前端架构](../architecture/frontend.md)。
