---
title: 代码导航
description: 了解 Akari 各部分代码的位置和职责。
---

## 仓库结构

| 路径 | 职责 |
| --- | --- |
| `lib/app/app.dart` | 应用生命周期、所选主题、共享功能状态和显示器 |
| `lib/infrastructure/` | D-Bus 网关和会话偏好存储 |
| `packages/greeter_ui/` | 登录界面业务状态、带有明确类型的命令和场景适配器 |
| `packages/theme_sdk/` | 公开主题宿主、状态接口类型和主题组装 |
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

## 主题是怎么构建的

从 `tool/akari.dart` 开始。`tool/src/cli_definition.dart` 定义通用命令语法。`theme_project.dart` 解析项目及 builder；`command_plans.dart` 描述执行步骤；`theme_host.dart` 创建所选宿主。场景构建器使用 `scene_schema` 校验文档，再生成主题需要导入的 Dart 代码。

## 界面是怎么更新的

先阅读 `packages/greeter_ui/lib/feature/` 下的 `GreeterFeature` 及其状态和命令，再查看 `GreeterSceneAdapter`、`GreeterHost` 和主题组件工厂。slot 为各界面区域提供状态，场景条件决定组件是否显示。`SceneRuntime` 独立处理布局和动效，不参与身份验证。

## 登录验证在哪里处理

从 `lib/infrastructure/dbus/greeter_dbus_gateway.dart` 开始，然后查看 `backend/src/service.rs` 和 `backend/src/greetd.rs`。服务负责串行处理身份验证并隔离每次尝试；传输层负责协议帧。详细说明见[后端指南](backend.md)和 [D-Bus 接口约定](../reference/dbus.md)。

## Studio 是怎么编辑场景的

`SceneEditor` 管理当前文档、选中节点和撤销/重做，并在保存前检查文件是否被外部修改。`NodeInspectorController` 管理待应用的字段值；`node_geometry.dart` 根据运行时布局和变换计算移动与缩放。`StudioViewport` 独立管理缩放和平移，不将其记入文档历史。`StudioAssets` 解析已加载场景所属的主题包并管理导入资源。编译后的预览继续使用所选主题的组件工厂。

## 多屏和显示测试在哪里实现

`linux/runner/my_application.cc` 管理显示器窗口和原生焦点上报；`lib/app/app.dart` 管理共享功能状态及凭据控制器。`scripts/greetd-test/display_profile.py` 校验并解析登录显示配置快照。`scripts/sway-session.py` 管理嵌套/无头合成器、实际输出检查和截图。具体测试步骤见[显示指南](../guides/display-testing.md)。

## 公开入口

从对应包导入 `theme_sdk.dart`、`scene.dart`、`scene_schema.dart` 或 `greeter_components.dart`。`lib/src/` 中的代码属于内部实现。公开接口见[生成的 API 参考](../reference/api.md)。

Studio 仍在开发中。它的内部说明和未来提案保留在仓库中，不纳入已发布的文档集合。
