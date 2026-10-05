---
title: 快速开始
description: 预览主题、运行模拟登录界面并构建原生程序包。
---

完成[环境配置](installation.md)后，在仓库根目录执行以下命令。

## 预览主题

```sh
fvm dart run tool/akari.dart preview --theme themes/fallback
```

fallback 主题是一个小型静态示例。要预览默认主题：

```sh
fvm dart run tool/akari.dart preview --theme themes/default
```

预览使用模拟的前端状态，不需要后端，并会打开一个可调整大小的桌面窗口。CLI 会解析主题依赖、生成场景 Dart 代码，并创建可复用的应用宿主。

在调试模式下，保存 Dart 或资源文件会触发热重载。场景 JSON 会在重载前重新生成。在启动命令的终端中，按 `r` 重新生成并加载，按 `R` 重启，按 `q` 退出。

## 运行模拟后端

```sh
fvm dart run tool/akari.dart run --theme themes/fallback
```

此命令会在私有 D-Bus 会话中启动 Flutter 登录界面和 Rust 模拟后端，并使用与生产环境相同的前端传输。模拟对话接受密码 `password`；它不会验证系统账户，也不会启动真正的桌面会话。登录界面默认全屏；如需窗口模式，请在命令前设置 `AKARI_WINDOW_MODE=windowed`。

全屏模式会在所有已连接显示器上呈现相同的登录状态。请参阅[显示与缩放测试](../guides/display-testing.md)，检查焦点、热插拔、嵌套 Sway 会话或固定分辨率截图。

## 构建生产程序包

```sh
fvm dart run tool/akari.dart build --theme themes/fallback --jobs 4
```

构建默认使用 release 模式，并同时构建前端和生产版 Rust 后端。成功后，前端程序包位于 `build/out/fallback`，后端可执行文件位于 `build/out/backend`。分发时请保留完整的 Flutter 程序包。

构建不会安装或切换显示管理器。测试真实登录时，请使用专门的 [greetd 测试指南](../guides/greetd-testing.md)。

接下来可以[创建主题](../guides/themes.md)，或浏览[实现代码导航](../architecture/code-map.md)。
