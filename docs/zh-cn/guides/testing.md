---
title: 开发与测试
description: 检查代码、登录交互、多屏显示和主题性能。
---

## 运行项目检查

```sh
fvm dart run tool/akari.dart verify
fvm dart run tool/akari.dart verify --theme themes/fallback
```

这个命令会检查共享代码和 Rust 后端，并运行主题测试。指定 `--theme` 后，只检查这个主题，同时仍会检查共享代码和 Studio。主题的 UI 测试放在主题项目里；运行时和场景模型的测试放在各自的包里。

测试应覆盖场景校验、状态转换、登录尝试隔离、slot 通知、焦点、键盘交互、资源释放和性能。不要让测试依赖固定的像素位置。

`test/login_cli_test.dart` 也会运行 `test/support/login_workflow_test.py`，模拟 systemd 和账户边界，检查正式部署、切换失败、恢复、版本回退、权限及登录子进程清理。这些检查不会修改主机显示管理器；DRM 和 PAM 行为仍通过实际登录验证。

## 测试前后端交互

```sh
fvm dart run tool/akari.dart run --theme themes/fallback
```

这个命令会测试前端通过 D-Bus 与后端通信的完整流程，不会调用系统 PAM。如果只想看主题效果和本地交互，使用 `preview` 即可。

## 合成器和真实登录

```sh
fvm dart run tool/akari.dart run sway --display-profile reference
fvm dart run tool/akari.dart run sway --display-profile reference --sway-backend headless
```

嵌套/无头会话包含私有后端、总线、合成器和前端。关于共享状态检查、缩放对比和截图，请参阅[显示测试](display-testing.md)。[CLI 参考](../reference/cli.md#sway-sessions-and-display-profiles)说明显示配置及实际输出校验。

要测试真实登录，请按[独立 greetd 测试](greetd-testing.md)中的步骤安装测试工具、检查 TTY 环境，并准备恢复原来的登录管理器。

<a id="native-display-regressions"></a>

## 测试原生窗口和多屏行为

这些可选脚本会在隔离合成器中启动真正的 Flutter 窗口。它们与 `akari verify` 分开运行，并将日志和截图保留在输出的临时目录中。请安装 Sway、`swaymsg` 和 grim；多显示器脚本还需要 wtype。

要检查显示器生命周期和焦点，先运行 release 模式的演示预览：

```sh
fvm dart run tool/akari.dart preview --theme themes/default --mode release \
  --report build/tool/native-preview.json
```

启动后按 `q` 退出。从报告中读取 `artifacts.executable`，并将下方 `/path/to/preview/bundle/greeter` 替换为该路径。报告中位于当前仓库内的资源路径相对于仓库根目录。请将可执行文件保留在完整的 Flutter 程序包中。

```sh
python3 test/support/multi_display_workflow_test.py \
  --app /path/to/preview/bundle/greeter
```

此检查覆盖混合输出缩放、跨视图的指针焦点、显示器添加、主视图显示器移除、所有显示器移除、重新连接和单窗口模式。共享凭据及单次响应键盘分发由常规 Flutter 测试套件中的 `test/multi_display_test.dart` 覆盖。

要检查嵌套输出矩阵，先用模拟 D-Bus 后端准备登录界面：

```sh
fvm dart run tool/akari.dart run sway --theme themes/default \
  --display-profile reference --sway-backend headless \
  --report build/tool/native-sway.json
```

启动后退出，再从报告中读取 `artifacts.executable` 和 `artifacts.backend_executable`。将下方两个路径替换为对应资源；脚本需要 `run sway` 构建的模拟后端。

```sh
python3 test/support/sway_native_workflow_test.py \
  --app /path/to/greeter/bundle/greeter \
  --backend /path/to/mock/backend
```

测试会启动无头外层 Sway，检查外层和内层缩放为 1、1.6 的四种组合，并校验输出报告及 1920×1080 的内层图片。它不检查 Hyprland 特有的窗口定位、DRM、真实 PAM 身份验证或显示管理器恢复；这些行为请使用手动显示和独立登录流程。

## 性能

```sh
fvm dart run tool/akari.dart verify-perf --theme themes/default
fvm dart run tool/akari.dart trace-perf --theme themes/default
```

主题通过自己的 manifest 声明是否支持这些命令。主题的 runner 负责交互流程、指标、阈值和资源格式。fallback 主题没有性能测试脚本。详情见[性能约定](../reference/theme-package.md#performance-protocol)。

## 命令失败后怎么看日志

使用 `--format json` 或 `--report PATH` 生成结构化报告。开发命令的报告、事件和子进程日志保存在 `build/tool/runs/`。命令失败后，先看对应步骤的 stderr 日志。真实登录测试的日志位置见 greetd 测试指南。
