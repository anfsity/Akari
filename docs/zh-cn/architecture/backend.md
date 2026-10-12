---
title: 后端代码指南
description: 查找负责进程生命周期、身份验证和传输的 Rust 模块。
---

| 模块 | 职责 |
| --- | --- |
| `main.rs` | 选择服务启动或用户侧桌面执行模式；处理服务信号及关闭流程 |
| `service.rs` | D-Bus 方法/信号、身份验证 actor 和系统操作 |
| `auth.rs` | 串行处理认证事务及 greetd 交接，作为 `service` 的私有模块 |
| `greetd.rs` | greetd 协议传输及模拟实现 |
| `state.rs` | 身份验证状态与事务数据 |
| `session_catalog.rs` | 桌面会话发现和启动数据校验 |
| `session_launch.rs` | 转发原生 login shell、传递桌面 argv、检查 locale 及记录用户日志 |
| `users.rs` | 账户发现 |

目前后端是一个应用 crate。外部使用方依赖的是 [D-Bus 接口约定](../reference/dbus.md)，而非 Rust 库 API。`service.rs` 将 `auth.rs` 声明为自己的私有认证模块。

## 生命周期与事务

进程会同时监控服务生命周期和身份验证 actor 的生命周期。关闭时会先停止接受新调用，再取消正在进行的协议工作。交接桌面会话时，必须释放登录界面，让 greetd 启动所选桌面。

交接命令先进入认证用户的 login shell，再以 `--exec-desktop` 模式调用同一个已安装的可执行文件。该模式不启动 greeter 的异步运行时或 D-Bus 服务。桌面参数通过 greetd 环境中的 JSON 传递，完成原生初始化后直接执行。配置、日志和服务就绪边界见[真实登录指南](../guides/greetd-testing.md#用户会话环境)。

每次登录验证都有一个用于区分尝试的 generation token。界面信号和响应必须关联到对应尝试；取消后，这个 token 会失效。电源请求单独管理状态。

## 本地代码参考

如需在本地浏览 Rust 实现细节：

```sh
cargo doc --manifest-path backend/Cargo.toml --no-deps --document-private-items
```

生成的页面位于 `backend/target/doc/`。Rustdoc 会读取 `///` 项目注释和 `//!` 模块文档。这些注释应说明协议必须遵守的规则，以及资源由谁创建、管理和释放。涉及多个模块的流程写在本指南中。

网站目前只发布 Theme SDK API。以后如果需要让其他项目使用 Rust API，或让贡献者在线查阅后端代码，再加入 Rustdoc 页面。
