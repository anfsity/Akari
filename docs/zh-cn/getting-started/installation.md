---
title: 环境配置
description: 安装运行 Akari 所需的工具，准备好开发环境。
---

Akari 目前支持在 Linux 上构建与运行。开始开发或预览前，请按以下步骤准备环境。

## 前置依赖

### 核心构建依赖

| 类别 | 所需工具 / 软件包 | 用途 |
| --- | --- | --- |
| 源码与 SDK | `git`、`python3`、[FVM](https://fvm.app/) | 管理 `.fvmrc` 中锁定的 Flutter SDK（`3.47.3`）并执行工作流脚本 |
| Rust 与会话底座 | `rustc`、`cargo`、`libseat` 开发文件（Debian/Ubuntu 为 `libseat-dev`，Arch 由 `seatd` 提供） | 构建 D-Bus 后端与原生启动画面 |
| Flutter Linux | `clang`、`cmake`、`ninja`、`pkg-config`、GTK 3 与 `libepoxy` 开发文件 | 编译 Linux 端 Flutter 宿主程序 |
| D-Bus 与进程隔离 | `dbus-daemon`、`busctl`、`setpriv`、`setsid` | 启动隔离的私有 D-Bus 会话与降权登录界面进程 |

### 可选测试工具

- **嵌套或无头合成器测试**：`sway`、`swaymsg`、`swaybg`、`grim`
- **原生键盘输入回归测试**：`wtype`
- **真实登录测试**：`greetd`（详见[独立 greetd 测试](../guides/greetd-testing.md)）

## 初始化仓库

1. 克隆仓库并初始化工具链与依赖：

   ```sh
   git clone https://github.com/anfsity/Akari.git
   cd Akari
   bash scripts/bootstrap-toolchain.sh
   ```

   该脚本会安装 `.fvmrc` 锁定的 Flutter SDK、启用 Linux 桌面支持、拉取根级 Dart Pub Workspace 依赖、生成内置主题场景代码，并拉取 `crates/` Cargo Workspace 的锁定依赖。

2. 检查工具链状态：

   ```sh
   bash scripts/check-toolchain.sh
   # 如需同时强制检查 Sway/greetd 运行时二进制：
   bash scripts/check-toolchain.sh --runtime
   ```

:::note
`bootstrap-toolchain.sh` 不会自动安装系统软件包。未传入 `--runtime` 时，`check-toolchain.sh` 会将缺失的 `sway`/`greetd` 与未设置的 `WAYLAND_DISPLAY` 作为警告输出，以便在无头（headless）或纯构建环境中正常通过检查。
:::

## 安装 `akari` 命令行启动器

将 `akari` 命令和自动补全安装到用户目录，省去每次输入 `fvm dart run packages/akari_cli/bin/akari.dart`：

```sh
# zsh 用户
fvm dart run packages/akari_cli/bin/akari.dart install cli --shell zsh

# bash 用户
fvm dart run packages/akari_cli/bin/akari.dart install cli --shell bash
```

打开新终端（或按命令提示加载环境脚本）即可直接使用 `akari`。

:::caution
`akari` 启动器绑定当前仓库路径。如果移动了仓库目录，请重新执行 `install cli`。
:::

## 部署为开机登录管理器

在已安装 `systemd`、`greetd` 和 `sway` 的系统上，可以直接构建并启用 Akari 作为开机登录服务：

```sh
akari install
akari login enable
```

这两条命令都不会中断当前正在运行的桌面。有关 PAM 密钥环解锁、日志排查及恢复原显示管理器的说明，请参阅[安装正式登录环境](../reference/cli.md#production-login-installation)。

接下来请阅读[快速开始](quick-start.md)。
