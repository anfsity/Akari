# Theme Studio 架构提案

> [!NOTE]
> **状态**：架构提案，阐述 Theme Studio、Flutter 登录界面与 Rust 后端之间的目标协作架构。当前已实现的进程间通信规范请参阅 [D-Bus 接口约定](../reference/dbus.md)。

## 1. 产品形态与端到端拓扑

Akari 将编译期 Flutter 登录界面平台与可视化编辑器 **Theme Studio** 相结合，二者共用同一套 `GreeterHost` 契约与 `SceneRuntime`。

```text
Linux 系统层（greetd / PAM、systemd-logind、桌面会话 .desktop 文件）
        |
        v
Rust 后端桥接层（私有会话总线、AuthActor、io.akari.Greeter1）
        |
        v
Flutter 宿主适配层（类型化状态快照、认证提示、命令与各领域数据流）
        |
        v
Theme Runtime（宿主组件、自定义主题 Widget、布局、动效与输入管理）
        |
        v
主题包（基于 Akari Theme SDK 编写，可在 Theme Studio 中实时预览与编辑）
```

主题作者负责视觉表现（背景、布局、字体排版、过渡动画与自定义装饰组件），Akari 则提供四项核心语义宿主能力：

- **`Password`**：安全凭据输入与多步 PAM 提示交互。
- **`Account`**：登录账户切换与头像/名称展示。
- **`Session`**：目标桌面会话选择。
- **`PowerAction`**：挂起、重启与关机系统操作。

## 2. Rust 后端控制面

| 模块 | 职责 |
| --- | --- |
| `backend/src/main.rs` | 服务启动、信号处理与用户侧桌面启动器入口分发 |
| `backend/src/service.rs` | `io.akari.Greeter1` D-Bus 服务暴露与 `systemd-logind` 电源调用 |
| `backend/src/auth.rs` | 单一 `AuthActor`，负责命令串行化、取消操作与 `attempt_id` 事务所有权 |
| `backend/src/greetd.rs` | `greetd` Unix Socket JSON 协议帧传输（`GREETD_SOCK`）与模拟实现 |
| `backend/src/state.rs` | 纯身份验证状态机（`AuthState`）与转换校验 |
| `backend/src/users.rs` 与 `session_catalog.rs` | 面向界面安全展示的系统用户与 `.desktop` 会话目录扫描 |

### 身份验证与桌面交接生命周期

```text
Idle -> CreatingSession -> PromptPending -> WaitingForInput -> SubmittingResponse
     -> Authenticated -> ResolvingSession -> StartingSession -> HandingOff
```

- 每条认证提示（`visible`、`secret`、`info`、`error`）均绑定唯一的 `attempt_id`。
- 密码等敏感输入保存在自动清零的内存缓冲区中，绝不进入日志或 D-Bus 信号。
- 会话交接阶段，Rust 校验 `session_id`、向 `greetd` 发送 `start_session(cmd, env)`、发出 `HandingOff` 通知并关闭登录界面，交由 `greetd` 启动目标桌面。

## 3. Flutter 宿主与 Theme Runtime

Flutter 宿主适配层将 D-Bus 信号转换为按领域划分的响应式数据流，使状态变化仅触发最小范围的局部重绘：

| 数据流 / 渲染区域 | 消费组件 |
| --- | --- |
| `AuthPrompt` 与 `Authentication` | 密码输入框、认证状态提示与交接过渡动画 |
| `User` 与 `Session` 目录流 | 账户选择器与桌面会话选择器 |
| `Power` 状态流 | 电源操作按钮组 |
| `Theme` 与 `Studio` 叠加层 | 背景渲染器、节点 2.5D 变换、选中控制点与对齐参考线 |

## 4. Theme Studio 编辑器架构

| 子系统 | 核心职责 |
| --- | --- |
| `ProjectSession` | 场景 JSON 文件读写、资源导入、防覆盖原子保存、未保存标记与撤销/重做栈 |
| `PreviewSession` | 模拟 `GreeterHost` 状态切换（`Login` / `Dormant`）、画布缩放/平移与参考分辨率 |
| `CanvasController` | 节点选择、2.5D 变换下的命中测试，以及按单次手势提交的拖拽/缩放事务 |
| `Inspector` | 布局、变换、动效预设与组件属性的表单校验与草稿应用 |
| `DiagnosticsPanel` | 场景格式校验、JSON/Dart 代码生成检查与帧耗时预算分析 |

画布交互采用单手势事务模型：
1. **按下指针（Pointer down）**：记录节点初始几何属性。
2. **移动指针（Pointer move）**：按帧率实时更新预览投影，不产生中间撤销记录。
3. **抬起指针（Pointer up）**：校验并提交一条完整的文档修改记录。

## 5. 质量验证、性能预算与 AI 工具桥接

- **帧耗时预算**：60 Hz 下每帧 `16.6 ms`（120 Hz 下 `8.3 ms`），覆盖休眠、账户选择、密码提示、认证报错、会话选择与电源菜单等全部状态。
- **外部 AI 工具桥接**：通过标准化工具操作（`theme_inspect`、`theme_validate`、`theme_preview`、`theme_screenshot`、`theme_profile`）暴露项目检查、场景校验、状态预览、截图对比与性能分析能力，使 AI Agent 能在相同的运行时约束下辅助开发和验证主题。
