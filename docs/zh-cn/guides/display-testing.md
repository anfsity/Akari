---
title: 显示器与缩放测试
description: 检查多屏、缩放和截图，对比桌面预览与真实登录的效果。
---

完成[环境配置](../getting-started/installation.md)后，在仓库根目录运行以下命令。示例使用默认主题；`--theme PATH` 可选择其他已编译主题。

## 该用哪种测试方式

| 检查内容 | 会话 |
| --- | --- |
| 当前桌面上的主题布局和本地交互 | `preview` |
| 实际多台显示器上的共享登录状态和键盘焦点 | 全屏 `run` |
| Wayland 桌面中的独立内容缩放 | `run sway` |
| 可重复的分辨率和截图 | `run sway --sway-backend headless` |
| 硬件输出模式、DRM、PAM 和恢复流程 | [独立 greetd 测试](greetd-testing.md) |

`preview` 使用演示状态。`run` 和 `run sway` 默认使用模拟后端；它们的前端仍通过 D-Bus 通信。合成器工作流需要 Python 3、Sway、`swaymsg` 和 grim。原生输入检查还需要 wtype。

## 检查多台显示器上的共享状态

```sh
fvm dart run tool/akari.dart run --theme themes/default
```

全屏模式会在每台显示器上打开登录窗口。点击其中一个窗口，选择账户并输入凭据；其他屏幕应同步显示相同账户、桌面会话和输入内容。再切到另一块屏幕继续输入，按一次 Enter 应只提交一次。

按 Escape 会隐藏所有显示器上的控件并清除共享凭据文本。唤醒后会恢复原有身份验证提示。在提示激活时拔掉当前焦点所在的显示器再重新连接：其余视图应保留对话，重新连接的视图应显示当前状态。每个视图会依据各自的逻辑尺寸和缩放进行布局。

如需一个可调整大小的窗口，可使用 `preview`，或在运行 `run` 前设置 `AKARI_WINDOW_MODE=windowed`。在启动命令的终端中按 `q` 退出。

<a id="compare-a-nested-session-with-standalone-login"></a>

## 对比嵌套会话与独立登录

还没有保存登录显示配置时，先使用项目参考配置：

```sh
fvm dart run tool/akari.dart run sway --theme themes/default \
  --display-profile reference
```

完成[独立登录测试](greetd-testing.md)并保存显示配置后，回到桌面，用这个配置启动：

```sh
fvm dart run tool/akari.dart run sway --theme themes/default \
  --display-profile login
```

对比前检查输出的来源和目标。如果没有有效的显示配置，`login` 会失败；默认的 `auto` 可以回退到参考配置。使用 `--dry-run` 可检查所选配置，而无需导入或启动它。[CLI 参考](../reference/cli.md#sway-sessions-and-display-profiles)说明截图选择、持久化和多输出映射。

在 Hyprland 中，使用桌面常用快捷键将嵌套窗口切换为全屏。对比时应使用与独立测试相同的物理显示器和模式。会话会补偿宿主显示器的缩放；平铺窗口的视口可能不同。将窗口移至另一台显示器或调整大小，可检查视口及补偿后缩放在主题运行期间是否同步更新。

## 拍摄固定分辨率的截图

```sh
fvm dart run tool/akari.dart run sway --theme themes/default \
  --display-profile reference --sway-backend headless \
  --resolution 1920x1080 --scale 1.6
```

这个配置的逻辑视口是 1200×675，截图尺寸是 1920×1080。无头模式不需要桌面，但会持续运行。查看命令输出中的截图路径，检查完成后在启动终端按 `q` 退出。

所有登录窗口出现后，会话会为每个输出捕获一次截图。初始图像保存在 `build/tool/runs/<run-id>/sway/screenshots/` 下；这不是持续录屏。`display-report.json` 和 `outputs.json` 会记录采用的显示设置。使用 `--report PATH` 时，CLI 报告的 `artifacts` 指向这些文件，`display` 字段则包含显示报告。

无头检查应对比请求的 `target` 和实际的 `actual`，并要求 `matched: true`。在 Hyprland 上还要检查 `effective_target`，包括 `host_monitor` 和 `host_scale`，因为外层合成器控制窗口尺寸。只要显示内容尺寸一致，内层图像像素尺寸仍可能与 TTY 登录截图不同。

## 常见问题

| 现象 | 下一步 |
| --- | --- |
| `login` 报告没有有效配置 | 重新安装当前测试工具，并完成会发布 `display-profile.json` 的独立测试；检查已保存运行的日志 |
| 多个输出时拒绝覆盖参数 | 对单输出分辨率或缩放覆盖使用 `--display-profile reference` |
| 嵌套启动需要 Wayland 桌面 | 在运行中的 Wayland 会话启动，或选择 `--sway-backend headless` |
| 无头模式报告输出偏差 | 查看 `display-report.json` 的检查项和 `sway.log`；输出不匹配会使会话失败 |
| Hyprland 对比中的视口不同 | 在同一显示器和物理模式下全屏对比，并检查有效目标中的宿主缩放 |
| 初始截图缺少预期控件 | 检查主题的休眠状态条件；截图捕获的是初始渲染状态 |

运行[原生回归检查](testing.md#native-display-regressions)，覆盖混合缩放、热插拔和嵌套输出矩阵。硬件输出和真实登录行为仍需通过独立测试检查。
