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

预览只打开一个可调整大小的登录窗口，依次自动演示人脸识别成功、失败后密码回退两条流程，完成后退出。它使用受控的前端认证事件，不启动后端、不调用摄像头或 PAM，并检查提示、密码框焦点与模拟会话交接。使用 `--scenario face-success` 或 `--scenario password-fallback` 可单独选择一条。失败时返回非零退出码，日志保存在 `build/tool/runs/`。

单独查看原生 loading 动画，运行 `fvm dart run tool/akari.dart run splash`。动画持续到按 Escape 或关闭窗口为止，之后不会启动登录界面。真实 VT 的画面交接仍需实机验证。

## 试用完整登录流程

```sh
fvm dart run tool/akari.dart run --theme themes/fallback
```

这个命令会同时启动 Flutter 登录界面和 Rust 模拟后端，两者通过私有 D-Bus 会话通信。前端使用的通信方式与正式运行时相同。输入密码 `password` 可以模拟登录成功；测试不会验证系统账户或启动真实桌面。默认以全屏打开，如需窗口模式，可在命令前设置 `AKARI_WINDOW_MODE=windowed`。

`run` 的 debug 模式支持保存后热重载：场景 JSON 变更先生成代码；在启动终端按 `r` 重新生成并加载，按 `R` 热重启，按 `q` 退出。`preview` 自动运行一次，不进行热重载。

全屏模式会在每台显示器上显示登录界面，并同步登录状态。要检查多屏焦点、热插拔、缩放或固定分辨率截图，见[显示器与缩放测试](../guides/display-testing.md)。

## 构建可发布的应用

```sh
fvm dart run tool/akari.dart build --theme themes/fallback --jobs 4
```

命令默认使用 release 模式，同时构建 Flutter 前端和正式版 Rust 后端。完成后，前端程序包在 `build/out/fallback`，后端可执行文件在 `build/out/backend`。发布时需要带上整个 Flutter 程序包，不能只复制其中的可执行文件。

构建完成后，应用还没有接入系统登录。要测试真实登录，请按照 [greetd 测试指南](../guides/greetd-testing.md)操作。

接下来可以[制作自己的主题](../guides/themes.md)。如果想了解实现，先看[代码导航](../architecture/code-map.md)。
