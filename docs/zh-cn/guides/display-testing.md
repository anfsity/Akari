---
title: 显示器与缩放测试
description: 检查多屏、缩放和截图，对比桌面预览与真实登录的效果。
---

完成[环境配置](../getting-started/installation.md)后，在仓库根目录执行以下命令。示例默认使用 `themes/default`，可通过 `--theme PATH` 切换其他主题。

## 选择测试方式

| 测试目标 | 命令 / 流程 |
| --- | --- |
| 在桌面上自动演示登录 UI 流程 | `akari preview` |
| 在多台物理显示器上测试状态同步与焦点切换 | `akari run`（默认全屏） |
| 在 Wayland 桌面中还原独立 TTY 登录的缩放比例 | `akari run sway` |
| 无需桌面环境，生成固定分辨率与缩放的对比截图 | `akari run sway --sway-backend headless` |
| 验证真实硬件显示模式、DRM/KMS 启动画面、PAM 与 SDDM 恢复 | [独立 greetd 测试](greetd-testing.md) |

:::note
`run` 与 `run sway` 默认在私有 D-Bus 会话中连接 Rust 模拟后端。Sway 相关流程需要安装 `python3`、`sway`、`swaymsg` 和 `grim`。
:::

## 检查多显示器状态同步

```sh
fvm dart run tool/akari.dart run --theme themes/default
```

全屏模式下，Akari 会按每台显示器的逻辑尺寸与缩放打开独立视图。可按以下清单验证多屏行为：

1. **状态同步**：在任意屏幕选择账户并输入密码，其余屏幕应实时同步显示相同的账户、桌面会话与输入内容。
2. **焦点唯一性**：点击另一块屏幕继续输入并按一次 `Enter`，应只触发一次认证提交。
3. **休眠与唤醒（`Escape`）**：按 `Escape` 会隐藏所有屏幕上的控件并清空已输入文本，但不会中断当前的后端认证会话；再次唤醒后继续原提示。
4. **显示器热插拔**：在密码提示激活期间拔掉焦点所在的显示器再重新接入，其余屏幕应保留当前会话，重连屏幕应恢复最新状态。

:::tip
如果只需要单个可调整大小的桌面窗口，可在运行 `run` 前设置 `AKARI_WINDOW_MODE=windowed`。在启动终端按 `q` 退出。
:::

<a id="compare-a-nested-session-with-standalone-login"></a>

## 对比嵌套会话与独立登录

1. **尚未捕获真实登录配置时**，使用内置的 `1920x1080`（缩放 `1.0`）参考配置启动：

   ```sh
   fvm dart run tool/akari.dart run sway --theme themes/default \
     --display-profile reference
   ```

2. **完成[独立 greetd 测试](greetd-testing.md)并生成显示快照后**，回到桌面直接复用该真实登录配置：

   ```sh
   fvm dart run tool/akari.dart run sway --theme themes/default \
     --display-profile login
   ```

   - 若本地没有有效的登录快照，`--display-profile login` 会直接报错；默认的 `auto` 则会自动回退到 `reference`。
   - 可加上 `--dry-run` 预览将要采用的配置来源，无需实际启动合成器。

3. **在 Hyprland 下全屏对比**：在同一台物理显示器上，用 Hyprland 全屏快捷键将嵌套 Sway 窗口设为全屏。`run sway` 会自动补偿宿主机缩放（`内层缩放 = 登录缩放 / Hyprland 缩放`），使全屏窗口的逻辑视口与真实 TTY 登录完全一致。

## 生成固定分辨率截图

使用 `--sway-backend headless` 可在不依赖桌面环境的情况下渲染指定分辨率与缩放：

```sh
fvm dart run tool/akari.dart run sway --theme themes/default \
  --display-profile reference --sway-backend headless \
  --resolution 1920x1080 --scale 1.6
```

- 在 `1920x1080` 分辨率、缩放 `1.6` 下，逻辑视口为 `1200x675`，输出 PNG 尺寸为 `1920x1080`。
- 所有登录窗口完成首帧显示后，截图会自动保存在 `build/tool/runs/<run-id>/sway/screenshots/` 下，同目录还包含 `display-report.json` 与 `outputs.json`。
- 查看完截图路径后，在终端按 `q` 退出。

## 常见问题排查

| 现象 | 解决方法 |
| --- | --- |
| `login` 提示没有有效配置 | 重新运行 `akari greetd-test install` 并完成一次独立登录测试，确保生成了 `display-profile.json`。 |
| 多输出配置拒绝 `--resolution` 或 `--scale` | 单输出覆盖参数需配合 `--display-profile reference` 使用。 |
| 嵌套启动提示缺少 Wayland 桌面 | 请在 Wayland 桌面会话中运行，或改用 `--sway-backend headless`。 |
| 无头模式提示输出偏差（output drift） | 查看 `display-report.json` 与 `sway.log`；无头模式要求请求的 `target` 与实际 `actual` 完全一致。 |
| Hyprland 窗口视口与 TTY 不一致 | 在同一台物理显示器上将窗口全屏后再对比，并检查 `display-report.json` 中 `effective_target` 的 `host_scale`。 |
| 初始截图中看不到登录控件 | 截图捕获的是初始渲染状态；请检查主题是否在休眠状态（`isDormant`）下隐藏了控件。 |

如需自动执行多显示器热插拔与缩放矩阵回归，请参阅[原生窗口与多屏回归测试](testing.md#native-display-regressions)。
