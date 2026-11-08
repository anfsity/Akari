---
title: 主题包约定
description: Akari 主题包的目录结构、可视化定制契约、构建规则与性能测试协议。
---

Akari 主题是独立的 Dart/Flutter 包。内置主题位于 `themes/`（`themes/default/`、`themes/fallback/` 与 `themes/preset1/`），第三方主题或由 Studio 合成的主题也可以存放在仓库外部。

## 项目结构

```text
my_theme/
  pubspec.yaml                 # name: theme_<name>
  assets/
  lib/
    <name>.scene.json          # 场景布局与可见性条件源文件
    <name>.scene.g.dart        # 由 build_runner 自动生成
    theme.dart                 # 导出 build<Name>Theme({Color? seed, SceneDocument? document})
    components/                # 主题自有 Flutter 组件
  test/
```

### 命名与依赖规则

| 规则项 | 约定要求 |
| --- | --- |
| 包名与 Builder 命名 | 从 `pubspec.yaml` 读取（与目录名无关）。例如 `theme_ocean` 必须在 `lib/theme.dart` 中导出 `buildOceanTheme`。 |
| 必需依赖 | `dependencies` 包含 `theme_sdk` 与 `scene`；`dev_dependencies` 包含 `scene_codegen` 与 `build_runner: ^2.16.2`。 |
| 组件复用边界 | 可显式依赖 `greeter_components`，但**不得**直接导入另一个具体主题包。 |
| 资源引用路径 | 统一使用 Flutter 包路径格式（如 `packages/theme_ocean/assets/wallpaper.jpg`）。 |
| 返回值契约 | `build<Name>Theme` 返回 `ThemeDefinition`，内含 `SceneDocument`、`ThemeBundle`、组件工厂及可选的编辑器声明目录。 |

:::note
存放在仓库外部的主题项目，需将 `pubspec.yaml` 中的 SDK 路径依赖指向本地 Akari 仓库对应目录。
:::

### 主场景配置与 Builder 参数

当主题包内包含多个 `*.scene.json` 文件时，可在 `pubspec.yaml` 中显式指定默认打开的主场景：

```yaml
akari:
  scene: lib/composition.scene.json
```

该路径必须位于 `lib/` 下。Studio 与 CLI 会将其排在场景列表首位（合成主题也通过此字段默认打开编辑后的场景）；未配置时按文件名字母顺序排列。

导出的 Builder 函数接受可选的 `SceneDocument? document` 参数：
- **正式运行**：不传入 `document`，Builder 默认使用 `*.scene.g.dart` 中生成的 `<name>SceneDocument`。
- **Theme Studio 编辑**：Studio 传入当前正在编辑的 `SceneDocument`（含 `themeProperties`），使画布预览与生产环境共用完全相同的样式与组件解析逻辑。

## 声明组件的可编辑属性

主题可通过 `ThemeDefinition.componentCatalog` 向 Theme Studio 开放类型化的组件属性控件。每个组件可声明一组文本属性（`ThemeTextProperty`）或枚举单选属性（`ThemeChoiceProperty<Enum>`）：

```dart
enum HeadingStyle { regular, large }

const headingStyle = ThemeChoiceProperty(
  name: 'variant',
  label: 'Text style',
  defaultValue: HeadingStyle.regular,
  choices: {HeadingStyle.regular: 'Regular', HeadingStyle.large: 'Large'},
);
const headingText = ThemeTextProperty(
  name: 'text',
  label: 'Text',
  defaultValue: 'Welcome',
);
const catalog = ThemeComponentCatalog(
  components: {
    'heading': ThemeComponentDefinition(
      label: 'Heading',
      properties: [headingText, headingStyle],
    ),
  },
);
```

- **共享默认值与读取**：构造 `ThemeDefinition` 时传入 `componentCatalog: catalog`，并在组件内部通过 `headingStyle.getValue(node.properties)` 和 `headingText.getValue(node.properties)` 读取属性值。
- **枚举名称持久化**：枚举属性将枚举成员的 `.name` 字符串写入 `node.properties`（与界面显示标签解耦）。请保持枚举名称稳定，并确保 `defaultValue` 包含在 `choices` 映射中。
- **边界校验**：在主题 Builder 入口调用 `catalog.validateDocument(document)`。未填写的属性自动回退至默认值而不会改写 JSON；非法枚举值则会抛出带节点与属性名称的 `FormatException`。未在目录中声明的组件与额外属性均原样保留。

## 声明主题级全局预设

主题可通过 `ThemeDefinition.presetCatalog` 声明全局外观选项（如配色方案、控件材质或动效风格）：

```dart
enum OceanPalette { deep, coral }

const oceanPalette = ThemeChoiceProperty(
  name: 'palette',
  label: 'Palette',
  defaultValue: OceanPalette.deep,
  choices: {OceanPalette.deep: 'Deep sea', OceanPalette.coral: 'Coral'},
);
const presets = ThemePresetCatalog(properties: [oceanPalette]);
```

- 构造 `ThemeDefinition` 时传入 `presetCatalog: presets`，并在主题 Builder 入口调用 `presets.validateDocument(document)`。
- 选中的预设值以字符串形式保存在场景根级的 `themeProperties` 中（通过 `oceanPalette.getValue(document.themeProperties)` 读取），并在 Theme Studio 的 **Compose → Theme presets** 面板中自动生成选择控件。

## 声明布局插槽

`ThemeDefinition.layout` 可为指定的 `sceneId` 定义组件装配插槽（`slots`）以及可切换的多套预设布局（`presets`）：

```dart
const layout = ThemeLayoutDefinition(
  sceneId: 'ocean',
  label: 'Ocean',
  slots: [
    ThemeLayoutSlot(
      label: 'Sign-in caption',
      defaultNode: SceneNode(
        id: 'caption',
        componentId: 'heading',
        rect: SceneRect(x: 0.1, y: 0.2, width: 0.4, height: 0.1),
        properties: {'text': 'Welcome'},
      ),
    ),
  ],
  presets: {
    'split': ThemeLayoutPreset(label: 'Split view'),
    'centered': ThemeLayoutPreset(
      label: 'Centered column',
      rects: {
        'caption': SceneRect(x: 0.3, y: 0.2, width: 0.4, height: 0.1),
      },
    ),
  },
);
```

- **插槽标识与插入模板**：每个 `ThemeLayoutSlot` 通过唯一的 `defaultNode.id` 绑定固定的 `componentId`。当用户在 Studio 的 **Compose** 面板中开启某个可选组件时，编辑器会按 `defaultNode` 模板插入完整节点（含默认位置、属性、动效、焦点与显隐条件）。模板保存在主题 Dart 代码中，因此即使从 JSON 中移除节点并重新构建，依然可以随时重新添加。
- **必需控件保护（`isRequired: true`）**：Studio 禁止删除已存在的必需插槽；若打开的外部场景缺少必需插槽，可通过 `layout.findMissingRequiredSlots(document)` 检测并在侧栏顶部提供一键补齐（**Add required**）。
- **多套布局预设（`presets`）**：每个 `ThemeLayoutPreset` 按插槽节点 ID 提供替代的 `SceneRect` 位置（未列出的插槽沿用基础位置）。在 Studio 中切换布局预设会更新插槽几何位置并补齐缺失的必需控件，同时保留用户已修改的组件属性、已关闭的可选插槽与自定义图层。
- **边界校验**：在主题 Builder 入口调用 `layout.validateDocument(document)`；其他 `sceneId` 的场景不受该布局约束。

## 构建与预览机制

```sh
# 以生产模式构建默认主题
akari build

# 构建外部独立主题包
akari build --theme /path/to/my_theme --mode release

# 在单窗口中自动演示登录 UI 流程
akari preview --theme themes/default

# 仅输出执行计划，不生成文件
akari preview --theme /path/to/my_theme --dry-run
```

CLI 构建与运行主题的流程：

1. 解析所选主题的依赖，并将场景 JSON 生成为 `*.scene.g.dart`。
2. 在 `build/tool/hosts/<encoded-canonical-theme-path>/<real|demo|studio>/` 下生成可复用的 Flutter 宿主项目，链接共享应用源码并直接导入所选主题的 Builder。
3. 将主题代码与资源静态编译进 Linux 可执行文件（不支持在运行时动态加载未编译的 Dart 代码）。

| 命令 | 默认模式与通信 | 行为说明 |
| --- | --- | --- |
| `build` | Release 模式 + 正式版后端 + 原生 Splash | 构建完成后更新 `build/out/<theme>`、`build/out/backend` 与 `build/out/akari-splash` 符号链接。 |
| `run` | Debug 模式 + 私有 D-Bus 与模拟后端（`--backend real` 切换正式通信） | 支持保存后热重载（`r`）、热重启（`R`）与退出（`q`）。默认全屏，设置 `AKARI_WINDOW_MODE=windowed` 切换窗口模式。 |
| `preview` | Debug 模式，无后端、无热重载 | 在单窗口中依次自动演示 `face-success` 与 `password-fallback`（可通过 `--scenario` 单选），完成后自动退出。 |
| `run splash` | 独立窗口 | 单独预览原生启动加载动画，直至手动关闭。 |

### 缓存与并发锁

- 宿主项目在多次运行之间保留 Flutter 与原生 CMake/Ninja 编译缓存。
- Rust 模拟后端与正式后端分别使用独立的目标目录：`crates/target/akari-mock/` 与 `crates/target/akari-real/`。
- 针对同一主题的命令通过进程锁串行执行；不同主题之间可并行构建。

<a id="performance-protocol"></a>

## 性能约定

每个主题包独立维护自身的性能测试入口、交互流程、测量指标与通过标准。在主题的 `pubspec.yaml` 中添加 `perf` 配置即可接入 `verify-perf` 与 `trace-perf`：

```yaml
perf:
  version: 1
  verify: [dart, run, perf/run.dart, verify]
  trace: [dart, run, perf/run.dart, trace]
```

### 执行协议

```sh
akari verify-perf --theme /path/to/theme -- --custom-option value
akari trace-perf --theme /path/to/theme
```

- **工作目录与 SDK**：命令在主题项目根目录直接执行（不经过 shell）。以 `dart` 或 `flutter` 开头的命令自动使用仓库配置的 SDK。
- **参数原样转发**：`--` 之后的所有参数会原样转发给主题性能脚本。
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
`themes/default` 在 `themes/default/perf/` 下同时实现了 `verify` 与 `trace`，`themes/preset1` 在 `themes/preset1/perf/` 下实现了 `verify`；`themes/fallback` 未配置 `perf:`，也不会继承其他主题的性能阈值。
:::
