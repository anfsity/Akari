---
title: 前端架构
description: 分层边界、SceneRuntime 渲染机制、多显示器共享状态与性能预算。
---

## 1. 整体分层与职责边界

Flutter 前端负责界面渲染、输入处理与本地交互状态；Rust 后端通过 D-Bus 负责 PAM/`greetd` 认证协议与系统操作。

```text
GreeterFeature
  业务状态、类型化插槽（Slots）、命令、异常恢复、D-Bus 网关
        |
        v
GreeterSceneAdapter
  将业务状态映射为 ScenePredicate 条件与 GreeterHost 回调
        |
        v
ThemeDefinition
  主题标识、生成的 SceneDocument、组件工厂
        |
        v
ThemeBundle
  ThemeTokens、背景渲染器注册表、动效构建器注册表
        |
        v
SceneRuntime
  归一化布局、2.5D 变换、节点重绘边界、动效生命周期
```

核心隔离原则：
- **`GreeterFeature`** 不感知具体主题、背景渲染器、高斯模糊、动效预设或屏幕几何尺寸。
- **主题包** 不直接访问 `GreeterFeature`、D-Bus 连接或后端传输对象。
- **敏感凭据**（密码、OTP 验证码、原始 PAM 帧）绝不进入 `SceneDocument`、`ThemeBundle` 或日志。

## 2. 主题包与场景文档模型

每个主题都是独立编译进可执行文件的 Dart 包，由以下平台包提供支撑：

| 包路径 | 职责 |
| --- | --- |
| `packages/scene_schema` | 不依赖 Flutter 的 `SceneDocument` 模型、条件求值器与 JSON 编解码器 |
| `packages/scene` | `SceneRuntime`、`ThemeBundle`、背景与动效注册表（重新导出 `scene_schema`） |
| `packages/scene_codegen` | `build_runner` 生成器：校验 `*.scene.json` 并输出 `*.scene.g.dart` |
| `packages/theme_sdk` | `ThemeDefinition`、`GreeterHost` 与各区域状态插槽定义 |
| `packages/greeter_components` | 可选的标准可复用组件集（`StandardGreeterComponents`） |

### 场景节点核心约束

- **显式顺序分离**：`z`（空间深度）、`renderOrder`（绘制顺序）和 `focusOrder`（键盘焦点遍历顺序）是三个独立字段，绝不依赖 Widget 树的插入顺序推断。
- **声明式可见性（`visibleWhen`）**：基于受控的 `ScenePredicate` 枚举通过 `all`、`any`、`not` 组合求值，不支持任意脚本或运行时动态加载 Dart 代码。
- **编译期固化**：生产环境直接使用生成的 `*.scene.g.dart`，登录启动时不解析场景 JSON。

## 3. `SceneRuntime` 与渲染性能隔离

`SceneRuntime` 在节点级别隔离重建（Rebuild）与重绘（Repaint）：

- **局部订阅与独立重绘**：每个场景节点外层自动包裹独立的 `RepaintBoundary`。主题组件通过 `SceneRegion` 仅订阅自身所需的 `GreeterHost` Slot；节点的 `visibleWhen` 变化由各自的节点宿主独立响应，不会触发整棵场景树重建。
- **退出动画与卸载生命周期**：当节点的 `visibleWhen` 变为 `false` 时，节点会屏蔽指针与焦点输入并反向播放退出动画，待动画结束后再正式卸载（unmount），从而干净停止时钟等内部定时器。
- **可交互节点约束**：经过 2.5D 变换的可交互节点仍强制保持最小点击热区（`minHitTarget`）、安全区域回退和确定性的键盘焦点顺序。

### 背景、动效与模糊策略

- **背景渲染器**：内置提供 `image` 和 `solid`（`video` 与 `custom` 为编译期扩展点）。
- **动效预设**：支持 `none`、`fade`、`fadeSlide`、`fadeScale`、`hoverLift` 和 `focusGlow`。`SceneMotionBuilder` 只接收由 `SceneRuntime` 统一驱动的 `Animation<double>`，禁止使用全局 `AnimatedSwitcher` 或全屏动画遮罩。
- **模糊（Blur）**：画布背景的 `blurSigma` 只模糊一次并随背景重绘边界缓存；局部毛玻璃面板可使用受限的 `BackdropFilter`，并在低功耗或减少动效模式下自动回退为半透明纯色。

## 4. 多显示器同步与休眠状态

### 单引擎多显示器架构

1. Linux 原生运行器（`linux/runner/my_application.cc`）在单个 Flutter Engine 中为每台已连接显示器创建一个全屏 `FlView`。
2. `MyApp` 通过 `ViewAnchor` 和 `ViewCollection` 渲染多个同级视图，所有显示器共享同一个 `GreeterFeature` 与同一个 `credentialController`。
3. 每台显示器的 `GreeterSceneAdapter` 独立管理本屏幕的焦点树与唤醒动画；GTK 通过 `akari/displays` 通道上报当前激活的窗口，确保只有焦点所在屏幕响应全局键盘提交。
4. 拔除显示器时，隐式根视图会自动迁移到剩余显示器（或保持隐藏直至显示器重连），不会打断正在进行的后端认证会话。

### 休眠状态（`Escape`）

按 `Escape` 退回休眠背景（`isDormant`）时会清空 `credentialController` 中的本地输入文本，但**不会**向后端发送取消认证请求。再次唤醒界面会继续同一个 PAM 提示并恢复输入框焦点，避免休眠/唤醒切换被 PAM 计为密码失败尝试。

## 5. 测试策略与性能预算

| 测试层级 | 覆盖范围 |
| --- | --- |
| **单元测试** | `GreeterFeature` 状态机与命令、认证尝试隔离、敏感输入保护、`scene_schema` 校验与代码生成契约 |
| **交互测试** | 账户与桌面会话选择、密码框焦点、提交/取消/重试、电源操作与键盘无障碍遍历 |
| **运行时测试** | 安全区域回退、`renderOrder` / `focusOrder` 顺序、减少动效模式与背景加载失败回退 |
| **性能门槛（`themes/default`）** | 在 Linux/Wayland profile 模式下运行（`akari verify-perf`）。要求至少 3 个测量周期、首帧响应 UI 耗时 `< 5 ms`、各阶段与汇总 p95 不超过两个 `16.67 ms` 帧预算、相对基线回归不超过 `20%`，且静态画面稳定后不产生多余唤醒。 |
