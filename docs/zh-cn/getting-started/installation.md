---
title: 环境配置
description: 安装运行 Akari 所需的工具，准备好开发环境。
---

## 需要安装什么

Akari 目前只支持在 Linux 上构建和运行。开始前，请先安装这些工具：

- Git 和 [FVM](https://fvm.app/)，用于使用仓库指定的 Flutter SDK。
- Rust 和 Cargo，用于构建后端。
- Clang、CMake、Ninja、pkg-config，以及 Flutter Linux 所需的 GTK 3 开发文件。
- D-Bus 工具，包括后端会话所需的 `dbus-run-session` 和 `busctl`。

如果要在嵌套或无头合成器中测试，还需要 Sway、`swaymsg`、Python 3 和 grim。测试原生键盘输入时需要 wtype。真实登录测试需要 greetd；具体环境要求见[独立 greetd 测试](../guides/greetd-testing.md)。

## 获取项目

```sh
git clone https://github.com/anfsity/Akari.git
cd Akari
bash scripts/bootstrap-toolchain.sh
```

这个脚本会准备 `.fvmrc` 指定的 Flutter SDK，启用 Linux 开发支持，再下载 Dart 和 Cargo 依赖。上面列出的系统软件包需要自行安装。

```sh
bash scripts/check-toolchain.sh
```

这个脚本会检查开发环境，以及 Sway 和 greetd 测试所需的工具。如果没有设置 `WAYLAND_DISPLAY`，嵌套合成器检查会给出警告；无头测试不需要先启动 Wayland 桌面。

## 用 `akari` 命令简化操作

```sh
fvm dart run tool/akari.dart install --shell zsh
```

使用 bash 时，把选项改成 `--shell bash`。安装后打开新终端，或加载命令输出中列出的环境文件，就能直接使用 `akari`。这个命令绑定当前仓库路径；移动仓库后需要重新安装。

接下来阅读[快速开始](quick-start.md)。如需使用其他 SDK 路径，请参阅 [CLI 参考](../reference/cli.md)。
