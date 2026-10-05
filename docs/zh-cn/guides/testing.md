---
title: 开发与测试
description: 选择单元、模拟集成、合成器和性能检查流程。
---

## 仓库验证

```sh
fvm dart run tool/akari.dart verify
fvm dart run tool/akari.dart verify --theme themes/fallback
```

验证流程会检查共享代码和 Rust 后端，并运行发现的主题项目测试。指定主题会缩小主题检查范围，但仍保留共享检查，包括 Studio 分析与测试。主题负责自己的 UI 测试；运行时和 schema package 负责各自的约定。

应测试重要行为：场景校验、状态转换、尝试隔离、slot 通知、焦点与键盘交互、资源生命周期和性能。避免编写固定精确视觉位置的测试。

## 模拟集成

```sh
fvm dart run tool/akari.dart run --theme themes/fallback
```

此流程可在不调用系统 PAM 的情况下覆盖完整的前端/D-Bus 路径。只需检查主题渲染和本地行为时，请使用 `preview`。

## 合成器和真实登录

```sh
fvm dart run tool/akari.dart run sway --display-profile reference
fvm dart run tool/akari.dart run sway --display-profile reference --sway-backend headless
```

嵌套/无头会话包含私有后端、总线、合成器和前端。关于共享状态检查、缩放对比和截图，请参阅[显示测试](display-testing.md)。[CLI 参考](../reference/cli.md#sway-sessions-and-display-profiles)说明显示配置及实际输出校验。

真正的 greetd 测试是单独的[独立工作流](greetd-testing.md)，包含安装、TTY 前置检查和恢复流程。

<a id="native-display-regressions"></a>

## 原生显示回归

这些可选脚本会在隔离合成器中启动真正的 Flutter 窗口。它们与 `akari verify` 分开运行，并将日志和截图保留在输出的临时目录中。请安装 Sway、`swaymsg` 和 grim；多显示器脚本还需要 wtype。

要检查显示器生命周期和焦点，先运行 release 模式的演示预览：

```sh
fvm dart run tool/akari.dart preview --theme themes/default --mode release \
  --report build/tool/native-preview.json
```

启动后按 `q` 退出。从报告中读取 `artifacts.executable`，并将下方 `/path/to/preview/bundle/greeter` 替换为该路径。报告中位于此 checkout 内的资源路径相对于仓库根目录。请将可执行文件保留在完整的 Flutter 程序包中。

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

主题通过自己的 manifest 声明是否支持这些命令。主题的 runner 负责交互流程、指标、阈值和资源格式。fallback 主题没有性能 runner。详情见[性能约定](../reference/theme-package.md#performance-protocol)。

## 诊断失败命令

使用 `--format json` 或 `--report PATH` 生成结构化报告。开发运行会在 `build/tool/runs/` 下保留报告、事件日志和子进程日志。先查看失败步骤的 stderr 日志。独立 greetd 诊断日志路径见对应指南。
