---
title: 后端代码指南
description: 查找负责进程生命周期、身份验证和传输的 Rust 模块。
---

Rust 后端（`crates/akari-backend/`）是一个二进制应用 crate，对外通过 [D-Bus 接口约定](../reference/dbus.md)与前端交互。

`crates/Cargo.toml` 将后端和 `akari-splash` 纳入同一 workspace，共享 `Cargo.lock` 与 Rust Edition。后端 crate 名称为 `akari-backend`，安装后的可执行文件仍叫 `backend`。

## 模块职责一览

| 模块文件 | 核心职责 |
| --- | --- |
| `main.rs` | 入口模式分发（D-Bus 守护进程或用户侧桌面启动器）、系统信号监听与优雅退出 |
| `service.rs` | `io.akari.Greeter1` D-Bus 接口暴露、认证 Actor 监控与 `systemd-logind` 电源调用 |
| `auth/handle.rs` | D-Bus 命令句柄与认证 Actor 任务的生命周期管理 |
| `auth/actor.rs` | 单一串行命令队列、命令接收与调用结果回复 |
| `auth/attempt.rs` | 活动认证资源、传输操作、清理及状态/提示信号顺序 |
| `auth/caller_watch.rs` | 监听调用方断连并取消认证，使用弱发送端避免延长队列生命周期 |
| `greetd/protocol.rs` | 协议消息与共享传输错误定义 |
| `greetd/transport.rs` | 真实 Unix Socket、受限协议帧及凭据缓冲区清零 |
| `greetd/mock.rs` | 仅在 `mock` 特性下编译的确定性模拟传输 |
| `state.rs` | 纯身份验证状态机（`AuthState`）与状态转换校验 |
| `session_catalog.rs` | 扫描并校验 `/usr/share/wayland-sessions` 与 `/usr/share/xsessions` 下的 `.desktop` 会话 |
| `session_launch.rs` | 用户侧 login shell 转发（`--start-session` / `--exec-desktop`）、参数透传、Locale 检查与会话日志记录 |
| `users.rs` | 可交互登录的系统账户发现 |

## 生命周期与桌面会话交接

### 服务与认证事务生命周期

- 后端进程同时管理 D-Bus 服务与单一认证 Actor（`auth/actor.rs`）。
- 每次认证尝试都会生成唯一的 `attempt_id`。所有信号与客户端响应都必须匹配当前活动的 `attempt_id`；取消认证或客户端断开会使该令牌立即失效。
- 电源操作（`PowerAction`）使用独立的状态域，不会阻塞或中断正在进行的 PAM 认证。
- 进程收到退出信号或完成会话交接时，会先停止接收新请求，再清理正在进行的 `greetd` I/O 并退出登录界面，以便 `greetd` 启动用户桌面。

### 用户桌面两阶段启动（`session_launch.rs`）

认证通过后，`greetd` 会以目标用户身份分两阶段调用同一后端可执行文件（此模式不启动异步运行时或 D-Bus 服务）：

1. **`--start-session`**：将原生 login shell 启动阶段的输出重定向至私有 `startup-*.log`，并以非交互 login 模式调用用户的 `$SHELL`。
2. **`--exec-desktop`**：在 login shell 完成环境初始化后再次进入可执行文件，从环境变量读取 JSON 编码的桌面 `argv`，打开 `session-*.log` 并直接 `exec` 目标桌面命令。

关于 Profile 加载顺序与日志文件位置，请参阅[用户会话环境](../guides/greetd-testing.md#用户会话环境)。

<a id="local-code-reference"></a>

## 本地代码参考

在本地生成包含私有模块与内部符号的 `rustdoc` 文档：

```sh
cargo doc --manifest-path crates/akari-backend/Cargo.toml --no-deps --document-private-items
```

生成的 HTML 文档位于 `crates/target/doc/`。单模块内的协议不变量与资源所有权请写在源码的 `//!` 和 `///` 注释中；跨模块协作流程则维护在本指南中。
