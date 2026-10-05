---
title: 主题包约定
---

Akari 主题是独立的 Dart/Flutter package。内置项目位于 `themes/default/` 和 `themes/fallback/`；第三方项目可以放在仓库外。`packages/` 则包含平台模块。

## 项目结构

```text
my_theme/
  pubspec.yaml                 # name: theme_<name>
  assets/
  lib/
    <name>.scene.json
    <name>.scene.g.dart        # 由 build_runner 生成
    theme.dart                # 导出 build<Name>Theme({Color? seed})
    components/
      ...                     # 主题自有 Flutter widget
  test/
```

目录名与 package 名称互不相关。Akari 从 `pubspec.yaml` 中读取名称。例如，名为 `theme_ocean` 的 package 会从 `lib/theme.dart` 导出 `buildOceanTheme`。

主题依赖 `theme_sdk` 和 `scene`，并通过 `build_runner` 使用 `scene_codegen`。它可以明确复用 `greeter_components`，但不得导入其他具体主题。当前开发 SDK 使用 path dependency；外部项目须将依赖指向其 Akari SDK checkout。

`theme.dart` 会返回一个 `ThemeDefinition`，其中包含生成的 `SceneDocument`、`ThemeBundle` 和组件工厂。组件 ID 只对该工厂有效。资源属于主题 package，并使用 Flutter package 路径，例如 `packages/theme_ocean/assets/wallpaper.jpg`。

## 构建与预览

```sh
# 为生产环境构建默认主题。
fvm dart run tool/akari.dart build

# 构建独立项目，也支持仓库外的项目。
fvm dart run tool/akari.dart build --theme /path/to/my_theme --mode release

# 用模拟登录状态启动 Linux 预览。
fvm dart run tool/akari.dart preview --theme themes/default

# 检查完整执行计划，不生成文件。
fvm dart run tool/akari.dart preview --theme /path/to/my_theme --dry-run
```

CLI 会解析所选主题的依赖、生成场景源文件，并在 `build/tool/hosts/<encoded-canonical-theme-path>/<demo-or-real>/` 下创建宿主项目。该项目包含共享登录应用源代码、Linux runner、manifest 和入口文件；入口直接导入所选主题的 builder。主题构建不会修改平台 manifest。

`build` 默认使用 release 模式，同时构建前端和生产版 Rust 后端。`run --theme PATH` 会在私有 D-Bus 会话中启动完整登录界面，默认使用 Rust 模拟后端；`--backend real` 可选择生产传输。前端始终使用 D-Bus。`run` 直接管理所选主题的 Flutter 会话。

`preview --theme PATH` 使用前端演示状态预览主题。两个命令默认运行在 debug 模式，并会在保存后重新加载 Dart 和资源变更。场景 JSON 修改会先执行增量代码生成；如果生成失败，会继续使用上一次可用主题。按 `r` 重新生成并加载，按 `R` 热重启，按 `q` 退出。profile/release 会话不支持热重载。两个命令都接受 `--jobs COUNT`。

Preview 直接在当前桌面中打开，不会启动嵌套合成器；默认使用可调整大小、无装饰的窗口。`run` 和构建后的登录程序默认以无装饰全屏模式启动。设置 `AKARI_WINDOW_MODE=fullscreen` 可令 preview 全屏，设置为 `windowed` 可令登录界面以窗口模式运行。在启动终端按 `q` 退出运行中的会话。

全屏登录界面会在每台已连接显示器上渲染相同主题，并使用该输出的逻辑尺寸和缩放。账户、会话、身份验证、休眠状态和凭据文本在各显示器间共享；键盘操作由获得焦点的窗口处理。连接或断开输出时，窗口会更新而无需重新启动身份验证。窗口模式的预览只打开一个窗口。

如需进行原生多显示器回归检查，请先构建演示预览程序包，再运行 `python3 test/support/multi_display_workflow_test.py --app PATH/greeter`。此可选检查需要 Sway、wtype 和 grim。它会在隔离的无头合成器中运行混合缩放，测试热插拔和两种窗口模式，并将截图和日志保留在输出的临时目录中。

## 仓库开发

`generate-scenes` 和 `verify` 会扫描 `themes/` 下的项目，不要求主题名称固定。性能命令一次选择一个项目。每个项目由自身的 manifest 和 builder 入口标识；仓库内 package 名称必须唯一。

根项目提供共享应用代码。仓库测试直接注入主题 builder，调试入口 `tool/dev_main.dart` 则明确选择默认主题。性能测试数据属于各自的主题项目。构建外部主题只需要所选项目。

宿主项目会在多次运行间保留 Flutter 和原生构建缓存。共享应用源代码会链接到宿主；只有发生更改时才同步 Linux runner 文件。运行目录保存日志和报告，不会额外创建另一套构建。

Rust 模拟版和生产版构建使用独立且稳定的目标目录：`backend/target/akari-mock/` 和 `backend/target/akari-real/`。相同主题的命令使用进程锁串行运行；不同主题可以并行构建。

<a id="performance-protocol"></a>

## 性能约定

主题负责性能入口、UI 交互、测量、基线、阈值和跟踪分析。Akari 不要求指定 UI selector 或指标字段。主题可在自己的 `pubspec.yaml` 中显式声明支持的操作：

```yaml
perf:
  version: 1
  verify: [dart, run, perf/verify.dart]
  trace: [dart, run, perf/trace.dart]
```

每个入口都是非空参数数组。命令会在主题项目中运行，不会通过隐式 shell 执行。以 `dart` 或 `flutter` 开头的命令使用仓库配置的 SDK；其他可执行文件按系统正常路径解析。未设置入口表示不支持相应操作；Akari 不会回退到其他主题的测试。

```sh
fvm dart run tool/akari.dart verify-perf --theme /path/to/theme -- --custom-option value
fvm dart run tool/akari.dart trace-perf --theme /path/to/theme
```

CLI 会将 `--` 后的参数原样转发，包括 `--help`，并通过 `AKARI_PERF_OUTPUT_DIR` 提供已存在的绝对输出目录。命令退出码决定测试是否成功：0 表示成功，非零表示失败。成功命令还必须在该目录中生成有效的 `result.json`。即使命令随后失败，也可以先发布结果，以保留已登记的诊断信息。

```json
{
  "version": 1,
  "artifacts": [
    {"name": "report", "path": "report.json"},
    {"name": "timeline", "path": "timeline.json"}
  ]
}
```

资源名称不得为空且必须唯一。路径必须相对于输出目录、目标文件必须存在，并且最终解析位置必须仍在该目录内，包括经过符号链接解析的情况。资源列表允许为空。CLI 会校验该结构，并在运行报告的 `theme_artifacts` 映射中记录路径。资源名称、格式和内容由主题决定，CLI 不会解释它们。版本不受支持、manifest 无效或成功时缺少 manifest，都会导致协议检查失败。

默认主题声明了两个命令，并在自己的 `perf/` 目录保留当前交互流程和基线。它的 runner 会准备包含所需测试依赖的可复用 Linux 测试宿主。fallback 主题尚未启用性能命令；它不会继承默认主题的性能流程或阈值。
