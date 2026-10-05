---
title: 环境配置
description: 为 Akari 开发准备 Linux 工具链。
---

## 前置条件

Akari 目前仅在 Linux 上构建和运行。请安装：

- Git 和 [FVM](https://fvm.app/)，用于使用仓库指定的 Flutter SDK。
- Rust 和 Cargo，用于构建后端。
- Clang、CMake、Ninja、pkg-config，以及 Flutter Linux 所需的 GTK 3 开发文件。
- D-Bus 工具，包括后端会话所需的 `dbus-run-session` 和 `busctl`。

可选的合成器工作流还需要 Sway、`swaymsg`、Python 3 和 grim。原生输入回归检查需要 wtype。独立登录测试需要 greetd，以及对应指南中介绍的现有测试环境。

## 获取项目

```sh
git clone https://github.com/anfsity/Akari.git
cd Akari
bash scripts/bootstrap-toolchain.sh
```

引导脚本会安装或选择 `.fvmrc` 指定的 SDK、启用 Flutter Linux 开发、解析根目录 Dart 依赖并获取已锁定的 Cargo 依赖。它不会安装上面列出的 Linux 系统软件包。

```sh
bash scripts/check-toolchain.sh
```

检查器会覆盖常规开发以及可选的 Sway/greetd 工作流。缺少 `WAYLAND_DISPLAY` 时，在嵌套合成器场景下会显示警告；无头合成器测试不需要正在运行的 Wayland 桌面。

## 可选的 Shell 启动器

```sh
fvm dart run tool/akari.dart install --shell zsh
```

bash 用户请改用 `--shell bash`。打开新终端，或加载安装器输出的环境文件。安装的 `akari` 命令指向当前 checkout；移动仓库后需要重新安装。

接下来阅读[快速开始](quick-start.md)。如需使用其他 SDK 路径，请参阅 [CLI 参考](../reference/cli.md)。
