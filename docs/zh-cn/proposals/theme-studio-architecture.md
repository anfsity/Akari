# Theme Studio 架构规范

Akari 将编译期 Flutter 登录界面平台与可视化场景编辑器 **Theme Studio** 相结合，二者共用同一套 `GreeterHost` 契约与 `SceneRuntime`。进程间通信规范请参阅 [D-Bus 接口约定](../reference/dbus.md)。

## 1. 产品形态与端到端拓扑

```text
Linux 系统层（greetd / PAM、systemd-logind、桌面会话 .desktop 文件）
        |
        v
Rust 后端桥接层（私有会话总线、AuthActor、io.akari.Greeter1）
        |
        v
GreeterFeature 与 GreeterSceneAdapter（业务状态机、ScenePredicate 条件、GreeterHost 插槽）
        |
        v
SceneRuntime 与 ThemeBundle（归一化布局、容器 Frame、样式 Token、着色器与动效）
        |
        v
主题包（基于 Akari Theme SDK 编写，在 Theme Studio 中可视化编辑与实时预览）
```

主题作者负责视觉表现（背景、着色器、布局、字体排版、过渡动画与自定义组件），Akari 则提供语义化的宿主状态与交互回调：

- **账户选择**：系统可登录账户列表、当前选中账户及 `onSelectUser`。
- **桌面会话选择**：经校验的 `.desktop` 会话列表、当前选中会话及 `onSelectSession`。
- **凭据输入与提示**：由宿主托管的文本/焦点控制器、PAM 提示类型与状态文本、`onRespondToPrompt` 及 `onStartSession`。
- **电源操作**：通过 `onRequestPowerAction` 触发挂起、重启与关机。

## 2. Rust 后端控制面

| 模块 | 职责 |
| --- | --- |
| `crates/akari-backend/src/main.rs` | 运行模式分发（D-Bus 守护进程或用户侧桌面启动器）与系统信号处理 |
| `crates/akari-backend/src/service.rs` | `io.akari.Greeter1` D-Bus 接口暴露与 `systemd-logind` 电源调用 |
| `crates/akari-backend/src/auth/` | `AuthHandle`、单队列 `AuthActor`、活动 `Attempt` 生命周期管理与调用方断连监听 |
| `crates/akari-backend/src/greetd/` | 协议帧定义（`protocol.rs`）、Unix Socket 传输（`transport.rs`）与模拟实现（`mock.rs`） |
| `crates/akari-backend/src/state.rs` | 纯身份验证状态机（`AuthState`）与转换校验 |
| `crates/akari-backend/src/users.rs` 与 `session_catalog.rs` | 可交互系统用户发现与 `.desktop` 会话目录扫描校验 |
| `crates/akari-backend/src/session_launch.rs` | 用户侧两阶段 login shell 转发（`--start-session` / `--exec-desktop`） |

### 身份验证与桌面交接生命周期

```text
Idle -> CreatingSession -> PromptPending -> WaitingForInput -> SubmittingResponse
     -> Authenticated -> ResolvingSession -> StartingSession -> HandingOff
```

- 每条认证提示（`visible`、`secret`、`info`、`error`）均绑定唯一的 `attempt_id`。
- 密码等敏感响应保存在自动清零的内存缓冲区中，绝不写入日志或 D-Bus 信号。
- 会话交接阶段，Rust 校验 `session_id`、向 `greetd` 发送 `start_session(cmd, env)`、发出 `StateChanged("HandingOff")` 通知并退出登录界面，交由 `greetd` 启动目标桌面。

## 3. Flutter 宿主与场景运行时

`GreeterSceneAdapter` 将 `GreeterState` 投影为 `ScenePredicate` 布尔条件集合与 `GreeterHost` 上按领域细分的 `ValueListenable` 插槽（Slots），使状态更新仅触发相关组件的局部重建：

| 插槽 / 状态投影 | 消费方 |
| --- | --- |
| `userSlots`（`ValueListenable<UserSlots>`） | 账户选择器、头像与显示名称组件 |
| `sessionSlots`（`ValueListenable<SessionSlots>`） | 桌面会话选择器 |
| `promptSlots`（`ValueListenable<PromptSlots>`） | 凭据输入框、提示文案与提交按钮 |
| `powerSlots`（`ValueListenable<PowerSlots>`） | 电源操作控件 |
| `serviceSlots`（`ValueListenable<ServiceSlots>`） | 后端连接状态与错误提示组件 |
| `activePredicates`（`Set<ScenePredicate>`） | 节点 `visibleWhen` 求值、状态入场动效与转换边触发 |

## 4. Theme Studio 编辑器架构

Theme Studio（`packages/theme_studio/`）在内部按职责域划分模块，并复用 `packages/theme_project/` 提供的纯 Dart 项目校验与独立主题合成能力：

| 职责域 | 核心模块与职责 |
| --- | --- |
| `authoring/` | `SceneEditor`（管理当前 `SceneDocument`、选中项、撤销/重做栈与原子保存）、布局插槽装配（`ThemeLayoutDefinition`）及独立主题项目生成（`StudioCreateTheme`） |
| `canvas/` | `StudioViewport`（画布平移与缩放）、`node_geometry.dart`（2.5D 变换命中测试与拖拽/缩放/旋转矩阵计算）、智能对齐参考线（`smart_guides.dart`）、标尺与多分辨率对比画板 |
| `inspector/` | `NodeInspectorController`（属性草稿校验）、组件与主题预设控件、Frame 自动布局与响应式断点编辑、样式 Token 编辑器，以及 `CodeInspector`（JSON/Dart 代码检查） |
| `preview/` | `StudioPreviewHost`（无需启动后端即可模拟休眠、输入提示、提交中、认证错误、服务不可用等全部 `GreeterHost` 状态） |
| `resources/` | `StudioAssets`（资源分类检索、导入并登记 `pubspec.yaml`、图片/SVG 独立图层、字体动态注册）与 `StudioShaderCompiler` / `StudioShaderPlayground`（调用 `impellerc` 实时编译与 Uniform 反射绑定） |
| `timeline/` | `StudioTimeline`（确定性时间轴采样、节点时长/延迟滑块、属性关键帧轨道编辑）与 `StudioStateGraph`（状态转换边可视化配置） |
| `workspace/` | `StudioWorkspaceLayout`（左右停靠面板、浮动窗口与 `Design`/`Motion`/`Focus` 工作区模式）、自定义键鼠快捷键与编辑器偏好持久化 |

画布手势与滑块调节采用单手势事务模型：
1. **交互开始**：记录节点初始几何状态或属性快照。
2. **拖拽 / 滑动过程**：按帧率实时更新预览画面，不向撤销栈写入中间状态。
3. **交互结束**：校验结果并向 `SceneEditor` 提交一条完整的撤销记录。

## 5. 质量验证与性能基准

- **全仓校验（`akari verify`）**：统一执行静态分析、Rust 单元与集成测试、场景 Schema 与代码生成校验，以及所有共享包、Theme Studio 和主题包的测试套件。
- **性能与预览工具链（`packages/greeter_harness/`）**：在 `akari preview`、`akari verify-perf` 与 `akari trace-perf` 之间共享自动化交互旅程（`face-success`、`password-fallback`）、帧归属统计与 Timeline 指标汇总。
