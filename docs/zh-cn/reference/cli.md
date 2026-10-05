---
title: CLI 与开发工具
description: 命令目标、可用选项、显示配置和执行报告。
---

<a id="commands-and-targets"></a>

## 命令与目标

在仓库根目录运行 `fvm dart run tool/akari.dart COMMAND`。安装[启动器](#shell-launcher-and-completion)后，也可以运行 `akari COMMAND`。

| 命令 | 用途 | 命令专属选项 |
| --- | --- | --- |
| `build` | 构建所选主题和生产后端 | `--theme`、`--jobs`、`--mode`、`--platform` |
| `preview` | 使用演示登录状态预览主题 | `--theme`、`--jobs`、`--mode` |
| `run` | 使用私有 D-Bus 和后端运行登录界面 | `--theme`、`--jobs`、`--mode`、`--backend` |
| `run sway` | 在嵌套或无头 Sway 中运行登录界面 | `run` 选项，以及 `--display-profile`、`--resolution`、`--scale`、`--sway-backend` |
| `run studio` | 使用已编译主题编辑场景 | `--theme`、`--jobs` |
| `verify` | 检查共享代码、后端和主题项目 | `--theme` |
| `generate-scenes` | 从场景 JSON 生成类型化 Dart | `--theme` |
| `verify-perf` / `perf` | 运行主题声明的性能检查 | `--theme`、`--` 后的参数 |
| `trace-perf` / `trace` | 运行主题声明的性能跟踪 | `--theme`、`--` 后的参数 |
| `install` | 安装绑定到当前仓库的启动器和补全脚本 | `--shell`、`--prefix`、`--rc` |
| `completion` | 输出命令补全脚本 | `--shell` |
| `greetd-test` | 管理独立登录测试 | [各操作的选项](../guides/greetd-testing.md) |

构建、预览、运行目标、验证、场景生成和性能命令还接受 `--format text|json`、`--report PATH` 和 `--dry-run`。所有命令都接受 `--help`（`-h`）。`install`、`completion` 和 `greetd-test` 命令组有各自的输出和选项约定。

`run sway` 和 `run studio` 是 `run` 的目标；使用 `akari run TARGET --help` 查看它们支持的选项。Studio 始终以 debug 模式运行且不启动后端，不接受 `--mode` 或 `--backend`。它的开发用户指南暂存于仓库的 [Studio 说明](https://github.com/anfsity/Akari/blob/main/docs/internal/theme-studio.md)。

通过 Dart 工具入口运行项目检查：

```sh
fvm dart run tool/akari.dart build
fvm dart run tool/akari.dart verify
fvm dart run tool/akari.dart verify-perf
fvm dart run tool/akari.dart generate-scenes
fvm dart run tool/akari.dart trace-perf
```

`-t`、`-m`、`-j` 分别是 `--theme`、`--mode`、`--jobs` 的短选项。`perf` 是 `verify-perf` 的别名，`trace` 是 `trace-perf` 的别名。长选项也接受 `--name=value`。同一选项混用短写和长写仍会被视为重复。`COMMAND --help` 只列出该命令接受的选项。仅性能命令接受 `--` 后的参数；这些参数会原样传给主题 runner。

```sh
fvm dart run tool/akari.dart build -t themes/default -m release -j 4
fvm dart run tool/akari.dart perf -t themes/default -- --cycles 5
```

<a id="shell-launcher-and-completion"></a>

## Shell 启动器与补全

在用户级目录中安装绑定到仓库的 `akari` 命令和 Shell 补全：

```sh
fvm dart run tool/akari.dart install --shell zsh
# 或使用 bash：
fvm dart run tool/akari.dart install --shell bash
```

启动器写入 `~/.local/bin/akari`，补全支持写入 `~/.local/share/akari/`。安装过程会向 `.zshrc`（遵循 `ZDOTDIR`）或 `.bashrc` 追加一行 source 命令；重复安装不会重复添加。打开新 Shell，或加载输出的环境脚本以启用它。该启动器可以从任意目录运行，会保留相对参数路径，并使用当前仓库的 SDK 及 `AKARI_*_BIN` 覆盖项。安装后须保留仓库在原路径可用；移动仓库后请重新安装。`install --prefix PATH --rc PATH` 用于选择安装目录和启动文件。

补全覆盖命令和别名、命令专属长短选项、枚举值及路径。遇到 `--` 后便会停止补全，因为之后的参数属于主题。解析器、帮助文本和生成脚本共用 `tool/src/cli_definition.dart`。修改该定义后需重新安装，刷新已安装的补全脚本。手动注册时，运行 `akari completion --shell zsh` 或 `--shell bash` 会输出对应脚本。

独立登录测试使用 `akari greetd-test install`、`start`、`restore`、`status` 和 `logs`。此命令组直接调用已安装的测试生命周期脚本，将诊断信息保存在仓库运行报告之外。只有安装操作需要仓库构建产物；状态/日志查询和服务控制不会获取主题锁，也不会创建开发运行目录。`akari` 启动器本身仍需要仓库和 SDK。紧急恢复命令 `sudo /opt/akari-test/restore.sh` 可独立于二者运行。操作选项和前置条件见[独立 greetd 测试](../guides/greetd-testing.md)。

## 构建、预览和运行

`build` 通过 `--theme PATH` 接受主题项目，默认值为 `themes/default`。它会解析项目依赖、生成场景源文件，并在 `build/tool/hosts/` 下创建可复用宿主。宿主只导入所选主题；项目可以位于 Akari 仓库外。详情见[主题项目约定](theme-package.md)。

使用 `run --theme PATH` 在私有 D-Bus 会话中启动完整登录界面。默认会编译并启动 Rust 模拟后端；`--backend real` 则选择生产传输。前端始终使用 D-Bus。`run` 会直接管理所选主题的 Flutter 会话。

使用 `preview --theme PATH` 和前端演示状态预览主题。两个命令默认使用 debug 模式，并在保存后重新加载 Dart 和资源变更。场景 JSON 修改会先执行增量代码生成；生成失败时仍保留上次可用主题。按 `r` 重新生成并加载，按 `R` 重启，按 `q` 退出。profile/release 会话不支持热重载。两个命令都接受 `--jobs COUNT`。

Preview 直接在当前桌面打开，不使用嵌套合成器；默认使用可调整大小、无装饰的窗口。`run` 和构建后的登录程序默认以无装饰全屏模式运行。可设置 `AKARI_WINDOW_MODE=fullscreen` 令 preview 全屏，或设为 `windowed` 令登录界面使用窗口模式。在启动终端按 `q` 退出运行中的会话。

全屏登录界面会在每台已连接显示器上呈现相同主题，并使用各自输出的逻辑尺寸和缩放。账户、会话、身份验证、休眠状态及凭据文本会共享；键盘操作由获得焦点的窗口处理。连接或断开输出会更新对应窗口，不会重启身份验证。窗口模式的预览只打开一个窗口。

要进行原生多显示器回归检查，请构建演示预览程序包并运行 `python3 test/support/multi_display_workflow_test.py --app PATH/greeter`。此可选检查需要 Sway、wtype 和 grim。它会使用混合输出缩放启动隔离的无头合成器，检查热插拔及两种窗口模式，并将截图和日志保存在输出的临时目录中。

<a id="sway-sessions-and-display-profiles"></a>

## Sway 会话与显示配置

步骤说明和故障排查见[显示测试](../guides/display-testing.md)。

Hyprland 上的 preview 会继承所在输出的缩放。使用 `run sway` 可在嵌套合成器中应用独立登录界面的缩放：

```sh
akari run sway
akari run sway --display-profile reference
akari run sway --display-profile login
akari run sway --resolution 1920x1080 --scale 1.6
akari run sway --display-profile reference --sway-backend headless
```

所选主题、构建模式、构建任务数、模拟/真实后端以及重载按键与 `run` 相同。`scripts/debug-sway.sh` 会转发到相同 CLI 入口。该会话需要 Python 3、Sway、swaymsg 和 grim。默认 Wayland 后端会在当前 Wayland 桌面中打开虚拟输出；无头模式不需要桌面。两个模式都不会切换显示管理器。会话管理自己的私有 D-Bus、后端、合成器、前端进程组和临时运行目录；退出或失败时会清理这些资源并保留日志。

`--display-profile` 接受 `auto`（默认值）、`login` 和 `reference`。`auto` 会从 `/opt/akari-test/current-run/greeter/session-*/` 导入最新的完整、已标记 DRM 登录快照；如果已有更新的已保存登录配置，则继续使用它。若没有快照，则使用 `config/sway/reference.json`：单输出、1920×1080 像素、缩放 1、逻辑视口 1920×1080。没有有效登录配置时，`login` 会报错；`reference` 跳过登录发现和导入，可用于团队间保持一致的对比。重新安装 greetd 测试工具以生成带标记的快照；旧版未标记 `outputs.json` 仍可用于诊断。

导入的配置保存在 `${XDG_STATE_HOME:-~/.local/state}/akari/display-profiles/login.json`，以原子替换写入且仅文件所有者可访问。它会保留模式（包括刷新率）、缩放、变换、逻辑矩形、显示器身份、捕获时间、原始快照路径和测试/会话来源。失败、部分或损坏的快照，以及嵌套/无头输出，都不能替换有效登录记录。原始登录日志仍保留在原始路径；删除日志后，已保存的配置仍可使用。dry-run 会解析默认值，但不会导入文件或创建运行目录。

分辨率和缩放先取自一个基础配置，再应用显式覆盖。`--resolution WIDTHxHEIGHT` 表示参考输出像素；`--scale NUMBER` 是期望的独立登录缩放，且必须为正数。无头输出会强制使用该分辨率：例如 1920×1080、缩放 1.6 时，逻辑视口为 1200×675。在 Hyprland 上，外层合成器决定实际输出尺寸。任一选项都可以覆盖单输出配置中的对应值，同时保留另一个基础值；完整目标会标记为自定义。多输出配置不接受这些全局覆盖；如果要覆盖单输出，请选择 `reference`。

多个登录显示器会按从上到下、再从左到右的顺序映射到 `WL-1`、`WL-2`、… 或 `HEADLESS-1`、`HEADLESS-2`、…，并保留各显示器的参考模式、缩放、变换和逻辑位置。报告中仍会保留原始显示器名称。

启动时会打印来源、完整目标、实际输出以及日志/截图位置。`--format json` 会在运行报告的 `display` 字段中包含这些信息。Sway 资源位于 `build/tool/runs/<run-id>/sway/`：包括 `display-report.json`、原始 `outputs.json`、`sway.log`、`flutter.log`、生成的配置和 `screenshots/<virtual-output>.png`。所有登录窗口出现后，会在 Sway 内部为每个输出按其像素缩放截图。虚拟后端会自行选择刷新率；报告将物理刷新率保留为来源信息。固定几何模式会校验模式尺寸、缩放、变换和矩形；Hyprland 几何模式则校验下文描述的设置。

在 Hyprland 上，窗口遵循桌面的常规平铺和全屏管理。会话会读取自己窗口所在的显示器，并使用 `inner scale = selected standalone scale / Hyprland monitor scale` 补偿。例如 TTY 缩放为 1、显示器 Hyprland 缩放为 1.6 时，内层缩放为 0.625。在同一显示器及物理模式下全屏，逻辑视口和内容尺寸将与独立 TTY Sway 一致。全屏尺寸取自显示器，而不是配置中的参考分辨率。使用 Hyprland 常用全屏快捷键与 TTY 对比。

调整窗口大小或进入/退出全屏都会更新视口，不会停止主题。将窗口移到另一显示器时会重新计算缩放。会话只读取 Hyprland IPC 并修改自身的内层 Sway 输出；不需要浮动规则、固定窗口尺寸或桌面配置更改。报告会保留原始 `target`、补偿后的 `effective_target`（包括宿主显示器和缩放）以及 `actual`。对于由合成器管理的几何，`matched` 会比较有效输出设置。内层截图使用采用的输出缩放和尺寸，因此即使显示内容大小相同，像素尺寸也可能与 TTY 截图不同。

无头会话采用固定配置校验，输出偏差会使其失败。其他外层合成器仍需要能接受所请求配置尺寸的窗口。固定分辨率截图请使用无头模式。嵌套/无头测试不能替代 DRM 硬件测试或独立 TTY 测试。

对已构建的登录界面和模拟后端运行原生嵌套回归矩阵：

```sh
python3 test/support/sway_native_workflow_test.py \
  --app build/out/default/greeter \
  --backend backend/target/akari-mock/debug/backend
```

它会启动隔离的无头外层 Sway，使用 1 和 1.6 两种缩放，并测试内层缩放为 1 和 1.6 的情况。它会保留目标/实际输出报告，并检查所有四种组合下 1920×1080 的内层截图。此测试不会改动开发者桌面配置，也不能验证 Hyprland 特有的窗口定位。

## 验证与生成宿主

生产 `build` 默认使用 release 模式，同时编译前端和 Rust 后端。

`verify` 会分析共享代码、后端和 `themes/` 下发现的全部项目。指定 `--theme PATH` 时，只检查所选主题以及共享代码和后端。主题专属 UI 测试放在对应主题 package 中。如果主题项目的 `test/` 下包含 `*_test.dart`，验证也会运行该项目的 Flutter 测试。

根项目包含共享应用代码和仓库测试。CLI 会为所选主题生成可执行入口。仓库调试使用显式注入默认主题的 `tool/dev_main.dart`；CLI 和 Sway 包装脚本使用所选主题的生成宿主。生成场景后，如需直接使用演示登录状态运行仓库入口：

```sh
fvm flutter run -d linux --target tool/dev_main.dart
```

构建、运行、验证、场景生成和性能工作流请使用 CLI。安装启动器后可运行 `akari build`、`akari run`、`akari verify`、`akari generate-scenes`、`akari perf` 和 `akari trace`。Shell 脚本负责工具链安装/检查、独立后端启动以及私有 D-Bus、Sway 等 Linux 会话工作。`scripts/debug-dbus.sh` 可接收要在私有总线上运行的后端命令；未提供命令时会直接调用 CLI 的 `run` 命令。

## 报告与构建输出

使用 `--format json` 将机器可读报告输出到 stdout。每次运行还会在 `build/tool/runs/<run-id>/` 下写入报告和事件日志。每个命令步骤分别保存 stdout 和 stderr 日志。使用 `--report PATH` 可将报告写入指定路径。

采用此报告约定的命令，在 `--dry-run` 时会输出 JSON 执行计划（包括资源路径），但不会运行构建或会话步骤，也不会写入报告或预留运行目录。Sway 计划会解析所选显示配置但不导入，因此尚无实际输出或截图，因为合成器还未启动。

构建报告列出生成的宿主项目、构建目录和 Linux 可执行文件。即使所选主题项目位于仓库之外，SDK 命令仍使用仓库配置的 Flutter SDK。可通过 `AKARI_FLUTTER_BIN` 和 `AKARI_DART_BIN` 覆盖二进制路径。

Linux 构建成功后，会创建相对符号链接 `build/out/<theme-name>`（指向完整前端程序包）和 `build/out/backend`（指向生产后端）。例如运行 `build/out/default/greeter` 或 `build/out/backend`。报告记录 `bundle_link` 和 `backend_link`，文本输出则打印这些短路径。只有两个构建都成功后，链接才会更新。它们指向构建缓存；重新构建可能改变内容，清理缓存会使链接失效，且不会保留上次成功构建的内容。后端链接指向最近一次成功构建。不同项目如使用相同主题名，不能共用同一个前端链接；切换项目时须明确删除旧链接。主题名 `backend` 保留给后端输出链接。

运行报告使用 schema 版本 1，包括命令、运行状态和耗时、生成资源路径，以及按顺序列出的命令步骤、参数、工作目录、退出码、耗时和日志路径。`events.jsonl` 记录运行及步骤的开始和完成事件。子命令输出保存在各步骤日志中，以便 JSON stdout 始终可解析。

## 主题性能命令

`verify-perf` 和 `trace-perf` 通过 `--theme PATH` 选择一个主题，默认使用 `themes/default`。它们会解析依赖并生成场景，然后执行该主题显式声明的性能命令。CLI 不提供交互脚本、指标 schema、基线或通过阈值。详情见[主题性能约定](theme-package.md#performance-protocol)。

`--` 之后的参数会原样传给主题命令。默认主题可用下面的命令请求五个测量周期：

```sh
fvm dart run tool/akari.dart verify-perf --theme themes/default -- --cycles 5
```

默认主题在 `themes/default/perf/` 下自行管理 Linux profile 集成 fixture、测量和 trace 工具及基线。其检查器默认使用三个周期、至少要求三个周期，并接受 `--` 后的 `--baseline PATH`。fallback 主题当前没有声明性能命令。

每个性能命令都会收到绝对路径 `AKARI_PERF_OUTPUT_DIR`，指向 `build/tool/runs/<run-id>/perf/`。成功命令必须生成 `result.json`；运行报告会在不解析资源内容的情况下，将校验后的资源路径记录在 `theme_artifacts` 中。失败命令也可以生成诊断资源。非零退出码会保留，缺失的失败 manifest 不会掩盖命令失败。协议错误会令运行失败，但日志和报告仍会保留。JSON 控制台输出仍只有一份 CLI 报告。

## 缓存与并行工作

宿主项目会在多次运行间保留 Flutter 和原生构建缓存。共享应用源代码会链接到宿主；Linux runner 文件只有发生更改时才同步。CLI 进程内部执行宿主同步和构建链接发布，避免额外启动 Dart VM。计划/报告仍会列出等价的独立命令，并标记 `in_process: true`；失败时仍会记录步骤日志并停止依赖该步骤的后续流程。

宿主依赖解析完成后，构建和会话会向 Flutter 传入 `--no-pub`，避免重复检查。为减少启动开销，重载控制器只加载 SDK 解析和会话相关代码。

生产构建也会编译 Rust 后端。后端编译与主题准备并行运行。`build --jobs COUNT` 会通过 CMake Ninja pool 限制 Cargo 任务数和原生 C++ 编译/链接任务数。未指定时，各工具使用自身的多核默认值；它不会设置 Dart 编译器线程数。

Rust 模拟版和生产版构建使用独立且稳定的目标目录：`backend/target/akari-mock/` 和 `backend/target/akari-real/`。相同主题的命令通过进程锁串行执行；不同主题可以并行构建。
