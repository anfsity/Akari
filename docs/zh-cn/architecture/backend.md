---
title: 后端代码指南
description: 查找负责进程生命周期、身份验证和传输的 Rust 模块。
---

| 模块 | 职责 |
| --- | --- |
| `main.rs` | 服务启动、信号、总线断开、actor 完成及交接时的关闭流程 |
| `service.rs` | D-Bus 方法/信号、身份验证 actor 和系统操作 |
| `greetd.rs` | greetd 协议传输及模拟实现 |
| `state.rs` | 身份验证状态与事务数据 |
| `session_catalog.rs` | 桌面会话发现和启动数据校验 |
| `users.rs` | 账户发现 |

目前后端是一个应用 crate。外部使用方依赖的是 [D-Bus 接口约定](../reference/dbus.md)，而非 Rust 库 API。当前二进制的模块树未声明 `auth.rs`；要查看正在使用的身份验证实现，请从 `service.rs` 开始。

## 生命周期与事务

进程会同时监控服务生命周期和身份验证 actor 的生命周期。关闭时会先停止接受新调用，再取消正在进行的协议工作。交接桌面会话时，必须释放登录界面，让 greetd 启动所选桌面。

每次身份验证尝试都有一个 generation token。UI 信号和响应必须关联到对应尝试；取消操作会使 token 失效。电源请求使用独立的状态域。

## 本地代码参考

如需在本地浏览 Rust 实现细节：

```sh
cargo doc --manifest-path backend/Cargo.toml --no-deps --document-private-items
```

生成的页面位于 `backend/target/doc/`。Rustdoc 会读取 `///` 项目注释和 `//!` 模块文档。请在这些注释中说明协议不变量和资源所有权；跨模块流程则放在本指南中。

当前公开网站只发布 Theme SDK API。当出现 Rust API 的使用者，或需要托管的贡献者参考资料时，再添加后端代码参考。
