---
title: 快速开始
description: 先看看主题效果，再试试登录流程，最后构建 Linux 应用。
---

完成[环境配置](installation.md)后，在仓库根目录执行以下命令。

## 1. 自动预览主题

在单个可调整大小的桌面窗口中自动演示登录 UI 流程：

```sh
# 预览静态精简的 fallback 主题
fvm dart run tool/akari.dart preview --theme themes/fallback

# 预览默认主题
fvm dart run tool/akari.dart preview --theme themes/default
```

`preview` 通过受控的前端认证事件驱动界面，不启动后端、摄像头或 PAM，依次演示人脸识别成功（`face-success`）与密码回退（`password-fallback`）两条流程后自动退出。

- 使用 `--scenario face-success` 或 `--scenario password-fallback` 可单独运行其中一条流程。
- 若校验失败，命令会返回非零退出码，并将日志保留在 `build/tool/runs/` 下。

:::tip[单独预览原生启动画面]
如果只想查看原生 loading 动画而不启动登录界面，可以运行：
```sh
fvm dart run tool/akari.dart run splash
```
按 `Escape` 或关闭窗口即可退出。
:::

## 2. 使用模拟后端交互运行

在隔离的私有 D-Bus 会话中同时启动 Flutter 登录界面与 Rust 模拟后端：

```sh
# 默认全屏运行（覆盖所有已连接显示器）
fvm dart run tool/akari.dart run --theme themes/fallback

# 以桌面窗口模式运行，方便日常调试
AKARI_WINDOW_MODE=windowed fvm dart run tool/akari.dart run --theme themes/fallback
```

模拟后端使用与生产环境一致的 D-Bus 通信协议，但不会验证真实系统账户或启动桌面：

- 输入密码 `password` 即可模拟登录成功。
- 修改并保存 Dart 代码或 `*.scene.json` 时，会自动重新生成场景代码并触发热重载。

| 终端按键 | 操作 |
| --- | --- |
| `r` | 重新生成场景代码并热重载 |
| `R` | 热重启 |
| `q` | 退出会话 |

如需测试多显示器状态同步、热插拔、嵌套 Sway 缩放或固定分辨率截图，请参阅[显示器与缩放测试](../guides/display-testing.md)。

## 3. 构建发布产物

以 release 模式编译所选主题、原生启动画面与正式版 Rust 后端：

```sh
fvm dart run tool/akari.dart build --theme themes/fallback --jobs 4
```

构建完成后，产物会链接到 `build/out/`：

- `build/out/fallback`：完整的 Flutter Linux 程序包（分发时请保留整个目录，不要只复制单个可执行文件）。
- `build/out/backend`：正式版 Rust 后端可执行文件。

:::note
`build` 仅编译构建产物，不会修改系统登录服务。如需在真实 TTY 下验证登录，请参考[独立 greetd 测试](../guides/greetd-testing.md)。
:::

## 下一步

- [开发主题](../guides/themes.md)
- [浏览代码导航](../architecture/code-map.md)
