---
title: 主题包约定
description: Akari 主题包的目录结构、构建规则与性能测试协议。
---

Akari 主题是独立的 Dart/Flutter 包。内置主题位于 `themes/`（`themes/default/` 与 `themes/fallback/`），第三方主题也可以存放在仓库外部。

## 项目结构

```text
my_theme/
  pubspec.yaml                 # name: theme_<name>
  assets/
  lib/
    <name>.scene.json          # 场景布局与可见性条件源文件
    <name>.scene.g.dart        # 由 build_runner 自动生成
    theme.dart                 # 导出 build<Name>Theme({Color? seed})
    components/                # 主题自有 Flutter 组件
  test/
```

### 命名与依赖规则

| 规则项 | 约定要求 |
| --- | --- |
| 包名与 Builder 命名 | 从 `pubspec.yaml` 读取（与目录名无关）。例如 `theme_ocean` 必须在 `lib/theme.dart` 中导出 `buildOceanTheme`。 |
| 必需依赖 | `dependencies` 包含 `theme_sdk` 与 `scene`；`dev_dependencies` 包含 `scene_codegen` 与 `build_runner`。 |
| 组件复用边界 | 可显式依赖 `greeter_components`，但**不得**直接导入另一个具体主题包。 |
| 资源引用路径 | 统一使用 Flutter 包路径格式（如 `packages/theme_ocean/assets/wallpaper.jpg`）。 |
| 返回值契约 | `build<Name>Theme` 返回 `ThemeDefinition`，内含生成的 `SceneDocument`、`ThemeBundle` 与组件工厂。 |

:::note
存放在仓库外部的主题项目，需将 `pubspec.yaml` 中的 SDK 路径依赖指向本地 Akari 仓库对应目录。
:::

## 构建与预览机制

```sh
# 以生产模式构建默认主题
fvm dart run tool/akari.dart build

# 构建外部独立主题包
fvm dart run tool/akari.dart build --theme /path/to/my_theme --mode release

# 在单窗口中自动演示登录 UI 流程
fvm dart run tool/akari.dart preview --theme themes/default

# 仅输出执行计划，不生成文件
fvm dart run tool/akari.dart preview --theme /path/to/my_theme --dry-run
```

CLI 构建与运行主题的流程：

1. 解析所选主题的依赖，并将场景 JSON 生成为 `*.scene.g.dart`。
2. 在 `build/tool/hosts/<encoded-canonical-theme-path>/<demo-or-real>/` 下生成可复用的 Flutter 宿主项目，链接共享应用源码并直接导入所选主题的 Builder。
3. 将主题代码与资源静态编译进 Linux 可执行文件（不支持在运行时动态加载未编译的 Dart 代码）。

| 命令 | 默认模式与通信 | 行为说明 |
| --- | --- | --- |
| `build` | Release 模式 + 正式版 Rust 后端 | 构建完成后更新 `build/out/<theme>` 与 `build/out/backend` 符号链接。 |
| `run` | Debug 模式 + 私有 D-Bus 与模拟后端（`--backend real` 切换正式通信） | 支持保存后热重载（`r`）、热重启（`R`）与退出（`q`）。默认全屏，设置 `AKARI_WINDOW_MODE=windowed` 切换窗口模式。 |
| `preview` | Debug 模式，无后端、无热重载 | 在单窗口中依次自动演示 `face-success` 与 `password-fallback`（可通过 `--scenario` 单选），完成后自动退出。 |
| `run splash` | 独立窗口 | 单独预览原生启动加载动画，直至手动关闭。 |

### 缓存与并发锁

- 宿主项目在多次运行之间保留 Flutter 与原生 CMake/Ninja 编译缓存。
- Rust 模拟后端与正式后端分别使用独立的目标目录：`backend/target/akari-mock/` 与 `backend/target/akari-real/`。
- 针对同一主题的命令通过进程锁串行执行；不同主题之间可并行构建。

<a id="performance-protocol"></a>

## 性能约定

每个主题包独立维护自身的性能测试入口、交互流程、测量指标与通过标准。在主题的 `pubspec.yaml` 中添加 `perf` 配置即可接入 `verify-perf` 与 `trace-perf`：

```yaml
perf:
  version: 1
  verify: [dart, run, perf/verify.dart]
  trace: [dart, run, perf/trace.dart]
```

### 执行协议

```sh
fvm dart run tool/akari.dart verify-perf --theme /path/to/theme -- --custom-option value
fvm dart run tool/akari.dart trace-perf --theme /path/to/theme
```

- **工作目录与 SDK**：命令在主题项目根目录直接执行（不经过 shell）。以 `dart` 或 `flutter` 开头的命令自动使用仓库配置的 SDK。
- **透传参数**：`--` 之后的所有参数会原样转发给主题性能脚本。
- **输出目录**：CLI 通过环境变量 `AKARI_PERF_OUTPUT_DIR` 传入已创建的绝对输出目录。
- **结果清单（`result.json`）**：退出码 `0` 表示通过，且必须在 `AKARI_PERF_OUTPUT_DIR` 下生成合法的 `result.json`：

  ```json
  {
    "version": 1,
    "artifacts": [
      {"name": "report", "path": "report.json"},
      {"name": "timeline", "path": "timeline.json"}
    ]
  }
  ```

  产物名称必须唯一，路径必须位于输出目录内部。CLI 校验通过后会将路径记录到运行报告的 `theme_artifacts` 字段中。

:::tip
`themes/default` 在 `themes/default/perf/` 下实现了完整的 `verify` 与 `trace` 脚本；`themes/fallback` 未配置 `perf:`，也不会继承其他主题的性能阈值。
:::
