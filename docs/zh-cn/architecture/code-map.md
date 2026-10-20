---
title: 代码导航
description: 了解 Akari 各部分代码的位置和职责。
---

## 仓库目录总览

| 路径 | 核心职责 |
| --- | --- |
| `lib/app/app.dart` | 应用生命周期、主题注入、共享 `GreeterFeature` 与多显示器视图管理 |
| `lib/infrastructure/` | D-Bus 网关（`GreeterDbusGateway`）与本地偏好持久化 |
| `packages/greeter_ui/` | 登录业务状态、类型化命令与场景适配器（`GreeterSceneAdapter`） |
| `packages/theme_sdk/` | 公开宿主接口（`GreeterHost`）、状态插槽（Slots）与 `ThemeDefinition` |
| `packages/scene_schema/` | 不依赖 Flutter 的场景模型、JSON 编解码器、校验规则与条件求值器 |
| `packages/scene/` | `SceneRuntime`、`ThemeBundle`、背景渲染器与动效生命周期管理 |
| `packages/scene_codegen/` | 构建时将 `*.scene.json` 生成为 `*.scene.g.dart` 的代码生成器 |
| `packages/greeter_components/` | 可选的通用登录组件集（`StandardGreeterComponents`） |
| `packages/theme_studio/` | 可视化场景编辑器、检查器草稿、画布视口与主题资源导入工具 |
| `themes/` | 独立编译的主题包（`default`、`fallback`、`preset1`）及性能测试脚本 |
| `backend/src/` | Rust D-Bus 服务、认证 Actor、`greetd` 传输层与用户/桌面会话目录 |
| `linux/` | 原生 GTK/Flutter 运行器与多显示器全屏窗口管理 |
| `splash/` | 独立的 Rust DRM/KMS 与窗口化启动加载画面渲染器 |
| `tool/` | `akari` CLI 语法定义、主题宿主生成器与运行报告引擎 |
| `scripts/` | 工具链初始化、Sway 嵌套会话启动器与正式/测试环境管理脚本 |
| `test/` | 单元、Widget、CLI 及原生合成器回归测试 |

## 核心链路追踪

### 1. 主题构建与宿主生成链路

1. `tool/akari.dart` 通过 `tool/src/cli/definition.dart` 解析命令行参数。
2. `tool/src/commands/` 构建包含步骤图与产物的 `RunPlan`，交由 `tool/src/execution/` 执行并记录报告。
3. `tool/src/theme/project.dart` 解析主题包与 Builder 入口，`tool/src/theme/host.dart` 在 `build/tool/hosts/` 下生成对应的 Flutter 宿主工程。
4. `scene_codegen` 调用 `scene_schema` 校验 `*.scene.json`，并输出 `*.scene.g.dart`。

### 2. 界面状态更新与场景渲染链路

1. `GreeterFeature`（`packages/greeter_ui/lib/feature/`）更新业务状态，并按区域触发 Slot 通知。
2. `GreeterSceneAdapter` 将状态映射为 `ScenePredicate` 布尔条件与 `GreeterHost` 可监听对象。
3. `SceneRuntime` 逐节点求值 `visibleWhen` 条件、驱动进出场过渡动画，并在独立的 `RepaintBoundary` 中渲染主题组件。

### 3. 身份验证与桌面交接链路

1. `lib/infrastructure/dbus/greeter_dbus_gateway.dart` 调用 `io.akari.Greeter1` 方法并监听 `Prompt` / `StateChanged` 信号。
2. `backend/src/service.rs` 与 `backend/src/auth.rs` 串行处理当前 `attempt_id` 的认证请求。
3. `backend/src/greetd.rs` 通过 `GREETD_SOCK` 收发 JSON 协议帧；认证通过后由 `backend/src/session_launch.rs` 经用户 login shell 启动所选桌面。

### 4. 多屏显示与 Sway 缩放测试链路

- **原生多屏同步**：`linux/runner/my_application.cc` 为每台显示器创建全屏 `FlView`，并通过 `akari/displays` 上报活动窗口焦点；`lib/app/app.dart` 让所有视图共享同一个 `GreeterFeature` 与密码输入控制器。
- **显示快照与嵌套 Sway**：`scripts/greetd-test/display_profile.py` 校验并导入 TTY 登录显示快照；`scripts/sway-session.py` 负责管理嵌套或无头 Sway 会话、缩放补偿及自动截图。

### 5. Theme Studio 场景编辑链路

- `SceneEditor` 管理当前场景文档、选中节点、撤销/重做栈以及防外部覆盖的原子保存。
- `NodeInspectorController` 管理未提交的字段草稿；`node_geometry.dart` 基于运行时布局与变换矩阵计算画布拖拽与缩放手柄。
- `StudioViewport` 独立管理画布缩放与平移；`StudioAssets` 自动识别所属 `theme_*` 包并导入资源。

## 公开包导入约定

请始终从各包的根入口文件导入（`theme_sdk.dart`、`scene.dart`、`scene_schema.dart`、`greeter_components.dart`）。`lib/src/` 下均属内部实现细节。完整公开符号请查阅[生成的 API 参考](../reference/api.md)。
