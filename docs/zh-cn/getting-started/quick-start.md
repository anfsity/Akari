---
title: 快速开始
description: 快速体验主题预览、模拟后端交互运行与生产版本构建。
---

完成[环境配置](installation.md)后，在仓库根目录执行以下命令。

## 1. 自动化 UI 流程预览

在独立的可缩放桌面窗口中快速查看登录界面交互与动画：

```sh
# 预览静态精简的 fallback 主题
fvm dart run tool/akari.dart preview --theme themes/fallback

# 预览默认主题
fvm dart run tool/akari.dart preview --theme themes/default
```

`preview` 命令无需启动后台服务或调用 PAM，直接在纯前端模拟认证流程。它会依次演示人脸识别成功（`face-success`）与密码认证回退（`password-fallback`）两条典型交互旅程，并在完成后自动退出。

- 使用 `--scenario face-success` 或 `--scenario password-fallback` 可指定运行单条流程。
- 若运行中发生异常，命令会返回非零退出码，执行日志保存在 `build/tool/runs/` 下。

:::tip[预览原生 Splash 加载画面]
如果只需调试原生启动动画（不加载完整登录界面），可运行：
```sh
fvm dart run tool/akari.dart run splash
```
按 `Escape` 或直接关闭窗口退出。
:::

## 2. 模拟后端交互调试

在私有 D-Bus 会话中启动 Flutter 前端与 Rust 模拟后端（Mock Backend），体验完整交互：

```sh
# 默认全屏运行（覆盖所有已连接显示器）
fvm dart run tool/akari.dart run --theme themes/fallback

# 以桌面窗口模式运行，方便日常调试
AKARI_WINDOW_MODE=windowed fvm dart run tool/akari.dart run --theme themes/fallback
```

模拟后端实现了完整的 D-Bus 接口规范，但不会触碰真实系统账户或启动实际桌面环境：

- 输入默认测试密码 `password` 即可模拟登录成功。
- 修改并保存 Dart 代码或 `*.scene.json` 时，工具链会自动重新生成场景并触发热重载（Hot Reload）。

| 终端按键 | 操作 |
| --- | --- |
| `r` | 重新生成场景代码并触发热重载 |
| `R` | 热重启（Hot Restart） |
| `q` | 退出当前会话 |

如需测试多显示器状态同步、热插拔、嵌套 Sway 缩放或固定分辨率截图，请参阅[显示器与缩放测试](../guides/display-testing.md)。

## 3. 构建生产发布产物

以 release 模式编译主题包、原生 Splash 模块与正式版 Rust 后端服务：

```sh
fvm dart run tool/akari.dart build --theme themes/fallback --jobs 4
```

构建完成后，符号链接会生成在 `build/out/` 下：

- `build/out/fallback`：完整的 Flutter Linux 程序包（包含资源与动态库，分发或部署时需保留整个目录）。
- `build/out/backend`：正式版 Rust 后端二进制文件。

:::note
`build` 仅编译生成二进制产物，不会修改系统登录服务。如需在真实 TTY 下验证登录，请参考[独立 greetd 测试](../guides/greetd-testing.md)。
:::

## 下一步

- [开发主题](../guides/themes.md)
- [浏览代码导航](../architecture/code-map.md)
