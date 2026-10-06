---
title: 开发主题组件
description: 用 Flutter 编写主题组件，读取登录状态并响应用户操作。
---

## 组件工厂

`ThemeDefinition.components` 是主题的组件工厂。它接收 `GreeterThemeContext`，从中取得样式参数和 `GreeterHost`，再返回 `GreeterThemeComponents`。运行时调用 `build(context, node)`，由工厂根据场景中的组件标识符创建 Flutter widget。标识符由主题自己定义，不需要遵循统一的组件列表。

使用 `StandardGreeterComponents` 时，可以沿用 fallback 场景中的标识符。自己写工厂时，确保场景里使用的每个标识符都有对应组件。节点的 `properties` 是字符串配置，具体含义和解析方式由组件决定。

## 读取需要显示的状态

通过 slot 订阅组件需要的状态。例如，显示服务状态的标签只需订阅 `serviceSlots`：

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

这样，账户、会话或电源状态变化时，这个标签无需重新构建。`SceneRuntime` 已经为每个节点设置了重绘边界；只有性能分析发现问题时，才需要添加额外的边界。

## 响应用户操作

用户选择账户、切换桌面、提交密码、启动桌面会话或操作电源时，组件调用对应的宿主回调：`onSelectUser`、`onSelectSession`、`onRespondToPrompt`、`onStartSession` 和 `onRequestPowerAction`。根据对应 slot 的状态决定控件是否可用，并保留键盘操作、焦点和无障碍支持。登录功能层和后端会处理身份验证及 D-Bus 通信。

输入凭据的 widget 可以使用宿主提供的 `credentialController` 和 `credentialFocusNode`。它们由宿主管理和释放，主题组件不要调用它们的 `dispose`。密码等输入也不要复制到场景属性、样式配置或日志中。

## 管理组件生命周期

在进入、退出动画或预热期间，隐藏节点可能仍然挂载着。避免让隐藏组件的订阅和计时器做太多工作；组件卸载时，释放自己创建的资源。动效 builder 使用运行时提供的动画，动画控制器由运行时管理。

具体类型见 [API 参考](../reference/api.md)。各部分由谁管理、何时释放，见[前端架构](../architecture/frontend.md)。
