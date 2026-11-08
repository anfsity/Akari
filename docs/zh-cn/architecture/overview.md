---
title: 系统概览
description: 梳理主题包、Flutter 前端呈现与 Rust 安全后端的架构权责边界。
---

```mermaid
flowchart TD
    Project[主题包] --> Codegen[场景代码生成]
    Codegen --> Host[生成的 Flutter 宿主]
    Project --> Host
    Host --> Feature[登录功能]
    Feature --> Adapter[场景适配器]
    Adapter --> Runtime[主题定义与 Scene 运行时]
    Feature --> Bridge[Rust D-Bus 桥接层]
    Bridge --> Greetd[greetd 与 PAM]
    Bridge --> Logind[systemd-logind]
```

```mermaid
flowchart TD
    Schema["scene_schema：纯 Dart 场景与契约"] --> Codegen["scene_codegen：代码生成"]
    Schema --> Project["theme_project：项目发现与主题合成"]
    Project --> CLI["akari_cli：纯 Dart 命令行工具"]
    Project --> Studio["theme_studio：可视化编辑器"]
    Schema --> Scene["scene：Flutter 场景运行时"]
    Scene --> SDK["theme_sdk：公开主题 API"]
    SDK --> Components["greeter_components：通用组件"]
    SDK --> UI["greeter_ui：业务状态与适配"]
    SDK --> Studio
    Components --> Themes["独立主题包（themes/*）"]
    SDK --> Themes
    UI --> App["apps/greeter：原生宿主与 D-Bus"]
    UI --> Harness["greeter_harness：预览旅程与性能采集"]
```

主题包与生成的 Flutter 宿主均通过独立路径依赖解析，不依赖根级 Pub Workspace。`theme_sdk` 重新导出了场景运行时与声明契约，使主题包只需依赖核心 SDK 与场景库。

## 职责边界划分

| 层级 | 所属模块 | 核心职责 |
| --- | --- | --- |
| **构建边界** | 主题包 + CLI（`packages/akari_cli/`） | 每个主题包独立维护其 `*.scene.json`、样式配置（Tokens）、本地资源与组件实现。CLI 依据所选主题驱动代码生成（`*.scene.g.dart`），并组装直接导入该主题 Builder 的编译宿主。 |
| **前端边界** | Flutter 应用 + `greeter_ui` + `scene` | `GreeterFeature` 驱动登录业务流、管理凭据控制器并分发类型化命令；`GreeterSceneAdapter` 将认证状态投影为场景谓词（`ScenePredicate`）与数据插槽（Slots）；`SceneRuntime` 负责归一化坐标布局、2.5D 几何变换与节点进出场动效。 |
| **后端边界** | Rust 桥接服务（`crates/akari-backend/`） | 负责与 `greetd` Unix Socket 通信、驱动 PAM 认证流程、维护认证会话生命周期（`attempt_id`）、发现与校验 `.desktop` 桌面环境，并通过 `systemd-logind` 执行电源操作。所有能力均通过私有会话总线上的 [D-Bus 接口规范](../reference/dbus.md) 暴露。 |

:::note
主题包完全与底层的 `greetd`、PAM 及 D-Bus 细节解耦，仅需从 `GreeterHost` 读取安全的展示状态并触发对应的语义操作回调。
:::

## 延伸阅读

- [代码导航](code-map.md)：快速定位仓库中各个模块、运行器与工具脚本的位置。
- [前端架构](frontend.md)：了解 `GreeterFeature`、`ThemeDefinition` 与 `SceneRuntime` 的协作机制。
- [后端代码指南](backend.md)：了解 Rust 认证 Actor 与用户桌面交接流程。
