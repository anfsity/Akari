---
title: 开发与测试
description: 检查代码、登录交互、多屏显示和主题性能。
---

Akari 将测试划分为仓库快速校验、模拟 D-Bus 会话、隔离合成器回归以及真实 TTY 登录验证四个层级。

## 1. 仓库快速校验

运行静态分析、Rust 后端检查以及共享包与主题的单元/组件测试：

```sh
# 检查全部共享包、后端及所有内置主题
fvm dart run tool/akari.dart verify

# 仅针对指定主题运行主题测试，同时保留共享包与后端检查
fvm dart run tool/akari.dart verify --theme themes/fallback
```

编写测试时的原则：
- **关注行为与核心不变量**：校验场景模型、状态机转换、认证尝试隔离、Slot 通知、键盘焦点遍历、资源释放与帧耗时预算。
- **避免脆弱的像素坐标断言**：不要断言固定的像素位置；应验证控件可达性、最小点击热区、焦点顺序以及内容不溢出。

:::note
`test/login_cli_test.dart` 还会调用 `test/support/login_workflow_test.py`，在模拟的 systemd 与账户环境中验证部署、回滚与异常恢复，不会修改宿主机的显示管理器。
:::

## 2. 模拟会话与合成器调试

| 测试方式 | 命令 | 适用场景 |
| --- | --- | --- |
| 自动 UI 流程演示 | `fvm dart run tool/akari.dart preview --theme themes/fallback` | 在单窗口中自动运行一次人脸成功与密码回退流程并退出 |
| 交互式模拟后端 | `fvm dart run tool/akari.dart run --theme themes/fallback` | 通过私有 D-Bus 联调 Flutter 前端与 Rust 模拟后端，支持热重载 |
| 嵌套 / 无头 Sway | `fvm dart run tool/akari.dart run sway --display-profile reference` | 验证显示器缩放还原与固定分辨率截图（详见[显示测试](display-testing.md)） |
| 真实 TTY 登录 | `akari greetd-test ...` | 验证真实 PAM、DRM/KMS 启动画面与桌面启动（详见[独立 greetd 测试](greetd-testing.md)） |

<a id="native-display-regressions"></a>

## 3. 原生窗口与多屏回归测试

以下可选脚本会在隔离的无头 Sway 合成器中启动真实 Flutter 窗口，并将日志与截图输出到临时目录。运行前需安装 `sway`、`swaymsg`、`grim` 和 `wtype`。

### 多显示器生命周期与焦点回归

使用 `tool/dev_main.dart` 构建持久运行的演示包（不要使用运行完即退出的 `preview` 产物），然后执行回归脚本：

```sh
fvm dart run tool/akari.dart generate-scenes --theme themes/default
fvm flutter build linux --release --target tool/dev_main.dart --dart-define=AKARI_BACKEND=demo
python3 test/support/multi_display_workflow_test.py \
  --app build/linux/x64/release/bundle/greeter
```

该脚本会验证混合 DPI 缩放、跨屏幕指针焦点切换、热插拔（含拔除主显示器、拔除全部显示器后重连）以及单窗口模式。

### 嵌套缩放矩阵回归

1. 先运行一次无头 Sway 会话以生成登录界面与模拟后端构建产物：

   ```sh
   fvm dart run tool/akari.dart run sway --theme themes/default \
     --display-profile reference --sway-backend headless \
     --report build/tool/native-sway.json
   ```

2. 启动后按 `q` 退出，从 `build/tool/native-sway.json` 中读取 `artifacts.executable` 与 `artifacts.backend_executable`，替换到以下命令中执行：

   ```sh
   python3 test/support/sway_native_workflow_test.py \
     --app /path/to/greeter/bundle/greeter \
     --backend /path/to/mock/backend
   ```

该测试会遍历外层与内层缩放为 `1.0` 和 `1.6` 的全部四种组合，并校验输出报告与 `1920x1080` 内层截图尺寸。

## 4. 性能测试

运行主题在 `pubspec.yaml` 中声明的性能门槛校验或耗时追踪：

```sh
fvm dart run tool/akari.dart verify-perf --theme themes/default
fvm dart run tool/akari.dart trace-perf --theme themes/default
```

交互步骤、测量指标与通过标准由主题包自行定义（详见[性能约定](../reference/theme-package.md#performance-protocol)）。

## 5. 排查失败命令

每次 CLI 运行都会在 `build/tool/runs/<run-id>/` 下保存结构化报告、事件流与各步骤的子进程日志：

- 使用 `--format json` 或 `--report PATH` 获取机器可读的执行报告。
- 命令失败时，优先查看对应失败步骤的 `stderr` 日志文件。
