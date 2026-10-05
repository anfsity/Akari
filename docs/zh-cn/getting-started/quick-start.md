---
title: 快速开始
description: 先看看主题效果，再试试登录流程，最后构建 Linux 应用。
---

完成[环境配置](installation.md)后，在仓库根目录执行以下命令。

## 预览主题

```sh
fvm dart run tool/akari.dart preview --theme themes/fallback
```

fallback 是一个没有持续动画的简单主题，适合先熟悉操作。想看看默认主题的效果，可以运行：

```sh
fvm dart run tool/akari.dart preview --theme themes/default
```

预览会在桌面上打开一个可调整大小的窗口，用模拟数据展示登录界面，不需要启动后端。命令会自动安装主题依赖、生成场景代码，并准备运行主题的应用项目。

调试模式支持热重载：修改 Dart 代码或资源并保存，就能看到变化。修改场景 JSON 后，工具会先生成代码再重载。在启动预览的终端里，按 `r` 重新生成并加载，按 `R` 热重启，按 `q` 退出。

## 试用完整登录流程

```sh
fvm dart run tool/akari.dart run --theme themes/fallback
```

这个命令会同时启动 Flutter 登录界面和 Rust 模拟后端，两者通过私有 D-Bus 会话通信。前端使用的通信方式与正式运行时相同。输入密码 `password` 可以模拟登录成功；测试不会验证系统账户或启动真实桌面。默认以全屏打开，如需窗口模式，可在命令前设置 `AKARI_WINDOW_MODE=windowed`。

全屏模式会在每台显示器上显示登录界面，并同步登录状态。要检查多屏焦点、热插拔、缩放或固定分辨率截图，见[显示器与缩放测试](../guides/display-testing.md)。

## 构建可发布的应用

```sh
fvm dart run tool/akari.dart build --theme themes/fallback --jobs 4
```

命令默认使用 release 模式，同时构建 Flutter 前端和正式版 Rust 后端。完成后，前端程序包在 `build/out/fallback`，后端可执行文件在 `build/out/backend`。发布时需要带上整个 Flutter 程序包，不能只复制其中的可执行文件。

构建完成后，应用还没有接入系统登录。要测试真实登录，请按照 [greetd 测试指南](../guides/greetd-testing.md)操作。

接下来可以[制作自己的主题](../guides/themes.md)。如果想了解实现，先看[代码导航](../architecture/code-map.md)。
