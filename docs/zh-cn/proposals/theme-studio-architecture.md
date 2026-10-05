# Theme Studio 架构提案

这是一份架构提案，描述 Theme Studio、Flutter 登录界面和 Rust 后端未来如何协作。以下设计尚未全部实现。

## 1. 产品形态

Akari 提供登录界面和主题编辑工具。主题是使用 Akari Theme SDK 编写的独立的 Dart/Flutter 包。Theme Studio 提供开发宿主、实时预览、热重载、诊断、模拟状态和性能工具。正式登录界面使用相同的 Host 约定和 Theme Runtime。

```text
Theme package
      |
      v
Theme Studio host -> Flutter hot reload -> Theme Runtime
      |
      v
Production greeter -> Theme Runtime -> Greeter Host
```

主题作者可以设计背景、布局、装饰、动画、字体和自定义组件。Akari 通过几个宿主接口提供登录相关功能：

```text
Password
Account
Session
PowerAction
```

宿主组件管理身份验证状态、安全输入、焦点、键盘导航、无障碍信息和系统操作。主题决定这些组件的布局和外观。

## 2. 系统各部分的关系

```text
Linux system
  greetd / PAM
  system D-Bus / systemd-logind
  user catalog and desktop session files
          |
          v
Rust greeter launcher
  private session bus
  AuthActor
  GreeterService
  Flutter child process
          |
          v
Flutter Host Adapter
  typed snapshots, prompts, commands, and domain streams
          |
          v
Theme Runtime
  host components, custom theme widgets, layout, motion, input
          |
          v
Theme package
```

Rust launcher 是 greetd 启动命令，并接收 `GREETD_SOCK`。它会启动私有会话总线、拥有 Rust 后端服务，并监控 Flutter 子进程。Flutter 通过私有 `io.akari.Greeter1` 接口与 Rust 通信。

Theme Studio 使用相同的 Flutter Host 约定以及确定性的 `MockGreeterHost`。编辑器可以切换身份验证状态，无需启动真实 PAM 或 greetd 服务。

## 3. Rust 后端

Rust 后端负责身份验证、greetd 通信、查找桌面会话、电源操作，以及从登录界面切换到桌面。

### 3.1 后端模块

```text
backend/src/main.rs
  启动器、私有总线配置、Flutter 子进程生命周期

backend/src/greetd.rs
  greetd Unix socket 传输及带帧 JSON 协议

backend/src/auth.rs
  AuthActor、命令串行化、取消及尝试所有权

backend/src/state.rs
  纯身份验证状态机和转换校验

backend/src/users.rs
  用户目录和可安全显示的用户记录

backend/src/session_catalog.rs
  桌面会话发现、校验、命令和环境解析

backend/src/service.rs
  io.akari.Greeter1 D-Bus 接口和信号
```

当前 greetd 登录尝试由一个 `AuthActor` 管理。它依次处理命令，管理连接和取消 token，发布 watch 快照，并为每个事件标记 `attempt_id`。

身份验证生命周期如下：

```text
Idle
  -> CreatingSession
  -> PromptPending
  -> WaitingForInput
  -> SubmittingResponse
  -> Authenticated
  -> ResolvingSession
  -> StartingSession
  -> HandingOff
```

actor 会将重试、取消、超时、客户端断开和过期尝试等情形作为明确的状态转换处理。

### 3.2 PAM 对话约定

后端支持完整的 greetd/PAM 对话模型：

```text
PromptKind:
  visible
  secret
  info
  error
```

每个提示都属于某个事务，并带有递增序号：

```text
Prompt(attempt_id, prompt_seq, kind, text)
Respond(attempt_id, prompt_seq, response)
```

一次身份验证尝试可以包含多个普通文本输入、密码输入、信息或错误消息。在保持提示协议稳定的前提下，硬件或多因子进度可通过单独的安全显示事件表示。

敏感输入在 Rust 中使用可清零缓冲区处理，不会进入日志或信号，并通过响应当前活动提示的私有方法调用传输。

### 3.3 D-Bus 与系统服务

Rust 暴露专用的私有会话 D-Bus 服务：

```text
Bus name:    io.akari.Greeter
Object path: /io/akari/Greeter
Interface:   io.akari.Greeter1
```

启动器会为 Rust 和 Flutter 提供相同的私有总线地址。Rust 电源控制器通过 system D-Bus 调用 `systemd-logind`。Rust 会读取并校验桌面会话文件和用户记录，之后才把适合界面显示的字段交给 Flutter。

## 4. 交接生命周期

启动器负责协调从登录界面切换到桌面会话的最后流程：

```text
Flutter -> StartSession(attempt_id, session_id)
Rust -> resolve and validate session_id
Rust -> HandoffPreparing
Flutter -> play transition and send HandoffReady
Rust -> greetd start_session(cmd, env)
greetd -> success
Rust -> HandoffStarted
Rust -> close Flutter child and private bus
launcher -> exit
greetd -> start selected desktop session
```

交接协议规定界面何时播放过渡动画，最后向 greetd 发请求和关闭进程的步骤由 Rust 执行。

## 5. Flutter Host 约定

Flutter 侧会将 D-Bus 值转换为带有明确类型的状态对象：

```text
GreeterSnapshot
AuthPrompt
AuthenticationState
UserSummary
SessionSummary
PowerState
HandoffState
```

Host Adapter 按顺序处理 D-Bus 信号，把各类状态变化发送给对应组件：

```text
AuthPrompt stream       -> Password component
Authentication stream   -> status and transition regions
User catalog stream     -> Account component
Session catalog stream  -> Session component
Power stream             -> PowerAction component
Handoff stream           -> transition overlay
```

首个实现使用 `package:dbus` 和私有会话总线。适配器会在数据进入 Theme Runtime 前执行类型化解码、事件排序、过期尝试过滤和本地状态通知。

## 6. Theme SDK 与 Runtime

主题包使用常规 Dart/Flutter 源代码：

```text
my_theme/
  pubspec.yaml
  lib/
    theme.dart
    components/
      background.dart
      account_layout.dart
      credential_decoration.dart
  assets/
  test/
  screenshots/
```

Theme SDK 包提供：

```text
akari_theme_sdk
  宿主组件
  类型化宿主状态
  布局和动画辅助工具
  资源和字体辅助工具
  局部重绘边界
  主题诊断信息
```

主题作者可以使用 Flutter widget、`CustomPainter`、动画、图像、shader 或其他 SDK 支持的视觉技术实现装饰组件。Theme Runtime 会将其与四个登录宿主组件组合。

运行时分为以下区域：

```text
Host region       身份验证和系统控件
Theme region      背景和自定义视觉组件
Input region      指针捕获和命中测试
Focus region      键盘与无障碍遍历
Studio overlay    选择、控制点、参考线和诊断
```

各区域有独立状态源和重绘边界。主题局部状态保留在主题组件树中；宿主快照只更新受影响最小的区域。

## 7. Theme Studio

Theme Studio 是运行和编辑主题项目的 Flutter 应用：

```text
ProjectSession
  文件、资源、保存、未保存状态、撤销/重做

PreviewSession
  MockGreeterHost、所选状态、语言环境、视口

CanvasController
  选择、指针会话、临时变换

Inspector
  组件属性、布局、动效、宿主绑定

DiagnosticsPanel
  编译器、布局、交互和性能结果
```

画布把一次手势视为一个事务：

```text
pointer down -> 捕获初始几何
pointer move -> 按帧频率更新临时变换结果
pointer up   -> 提交一项项目修改
```

所选组件和编辑器遮罩根据同一临时变换结果渲染。手势提交时，才会更新已保存项目模型、未保存状态、轮廓和诊断结果。

## 8. 开发与发布工具链

Theme Studio 使用现有 Dart/Flutter 工具链：

```text
akari theme create <name>
akari theme run
akari theme test
akari theme screenshot
akari theme profile
akari theme build
```

开发模式使用 Flutter JIT 和热重载。主题源代码更新时，Host 快照和 Studio 选择状态会继续保留。

发布模式使用 Flutter AOT，并在登录界面构建中打包所选主题。首个实现因而可以获得成熟的 Dart 分析、调试、热重载、widget 测试、golden 测试和发布编译能力，无需另行维护主题语言编译器。

## 9. 性能与正确性

平台计划采用以下帧耗时目标：

```text
60 Hz 目标：每帧 16.6 ms
120 Hz 目标：每帧 8.3 ms
```

Theme Studio 提供 profile 场景，并记录构建、布局、光栅、GPU 和指针手势耗时的 p95/p99。

每个主题都可以在以下状态下测试：

```text
dormant
account selection
password prompt
authentication error
session selection
power menu
service unavailable
```

测试还应覆盖不同窗口大小、DPI 和语言，以及减少动效、键盘导航、长文本、空目录和截图样本。

诊断范围包括布局约束、溢出、组件重叠、焦点顺序、命中区域、文本裁切和帧预算使用情况。

## 10. 外部 AI 工具桥接

AI 通过 skills 和工具调用作为外部开发工具集成。平台暴露项目及测试操作：

```text
theme_inspect
theme_validate
theme_preview
theme_screenshot
theme_apply_patch
theme_run_tests
theme_profile
```

AI agent 可以检查主题包、创建或编辑组件、渲染指定 Host 状态、比较截图并运行性能 profile。相同的 Theme Studio 诊断机制会校验每项生成的更改。

## 11. 平台包

目标包结构如下：

```text
akari_greeter_host
  Rust/Dart Host 约定和类型化显示状态

akari_theme_sdk
  主题作者 API 和语义组件

akari_theme_runtime
  主题组装、布局、输入、动效和重绘区域

akari_theme_studio
  项目编辑器、预览、Inspector 和诊断

akari_theme_tooling
  主题生成器、构建命令、源码映射和 profile

akari_theme_test
  状态、截图、交互和性能测试套件
```

Rust 后端处理系统操作，主题包定义界面效果。Theme Studio 和正式登录界面使用相同的 Host 接口和 Theme Runtime，让编辑预览与实际运行保持一致。

## 12. 交付阶段

1. 稳定 Rust Host 约定、提示序列、私有总线和交接生命周期。
2. 将四个语义 Host 组件提取到 Theme SDK。
3. 创建一个独立 Dart/Flutter 主题包和 Mock Greeter Host。
4. 围绕该包构建 Theme Studio 预览和 Flutter 热重载。
5. 添加按区域独立渲染、手势事务、模拟状态和 profile。
6. 添加截图、交互和性能一致性测试套件。
7. 添加主题生成器命令和外部 AI 工具桥接。

现有的详细 IPC 规格仍是协议参考：`docs/dbus-contract.md`。本文讨论重构后，后端、Theme Studio 和正式登录界面如何协作。
