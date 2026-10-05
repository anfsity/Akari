---
title: 代码导航
description: 了解 Akari 各部分代码的位置和职责。
---

## 仓库结构

| 路径 | 职责 |
| --- | --- |
| `lib/app/app.dart` | 应用生命周期、所选主题、共享功能状态和显示器 |
| `lib/infrastructure/` | D-Bus 网关和会话偏好存储 |
| `packages/greeter_ui/` | 登录界面业务状态、类型化命令和场景适配器 |
| `packages/theme_sdk/` | 公开主题宿主、插槽类型和主题组装 |
| `packages/scene_schema/` | 不依赖 Flutter 的场景模型、编解码器和条件 |
| `packages/scene/` | 布局、变换、背景渲染器和动效运行时 |
| `packages/scene_codegen/` | 构建时将场景 JSON 生成为 Dart 代码 |
| `packages/greeter_components/` | 可选的通用视觉组件集 |
| `packages/theme_studio/` | 场景编辑、检查器草稿、编辑视口和场景资源 |
| `themes/` | 可独立编译的主题项目及主题测试 |
| `backend/src/` | D-Bus 服务、身份验证、greetd 传输和目录 |
| `linux/` | Flutter 原生运行器和显示器集成 |
| `tool/` | CLI 语法、项目发现、生成的宿主和执行报告 |
| `scripts/` | 工具链配置及 Linux 会话/测试支持 |
| `test/` | 应用、CLI、基础设施和原生工作流测试 |

## 跟踪主题构建

从 `tool/akari.dart` 开始。`tool/src/cli_definition.dart` 定义通用命令语法。`theme_project.dart` 解析项目及 builder；`command_plans.dart` 描述执行步骤；`theme_host.dart` 创建所选宿主。场景构建器将校验委托给 `scene_schema`，并生成主题会导入的 Dart 代码。

## 跟踪 UI 更新

先阅读 `packages/greeter_ui/lib/feature/` 下的 `GreeterFeature` 及其状态和命令，再查看 `GreeterSceneAdapter`、`GreeterHost` 和主题组件工厂。插槽将业务状态映射到视觉区域；场景谓词控制组件是否出现。`SceneRuntime` 独立处理布局和动效，不参与身份验证。

## 跟踪身份验证

从 `lib/infrastructure/dbus/greeter_dbus_gateway.dart` 开始，然后查看 `backend/src/service.rs` 和 `backend/src/greetd.rs`。服务负责串行处理身份验证并隔离每次尝试；传输层负责协议帧。详细说明见[后端指南](backend.md)和 [D-Bus 接口约定](../reference/dbus.md)。

## 跟踪 Studio 编辑

`SceneEditor` 管理当前文档、选择、撤销/重做及冲突感知保存。`NodeInspectorController` 管理待应用的字段值；`node_geometry.dart` 根据运行时布局和变换计算移动与缩放。`StudioViewport` 独立管理缩放和平移，不将其记入文档历史。`StudioAssets` 解析已加载场景所属的主题包并管理导入资源。编译后的预览继续使用所选主题的组件工厂。

## 跟踪显示会话

`linux/runner/my_application.cc` 管理显示器窗口和原生焦点上报；`lib/app/app.dart` 管理共享功能状态及凭据控制器。`scripts/greetd-test/display_profile.py` 校验并解析登录截图。`scripts/sway-session.py` 管理嵌套/无头合成器、实际输出检查和截图。[显示指南](../guides/display-testing.md)将这些代码与手动及原生回归流程联系起来。

## 公开入口

从对应 package 导入 `theme_sdk.dart`、`scene.dart`、`scene_schema.dart` 或 `greeter_components.dart`。将 `lib/src/` 视为实现细节，并通过[生成的 API 参考](../reference/api.md)查看公开接口。

Studio 仍在开发中。它的内部说明和未来提案保留在仓库中，不纳入已发布的文档集合。
