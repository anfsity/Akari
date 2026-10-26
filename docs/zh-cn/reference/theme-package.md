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

## 声明组件的可编辑属性

主题通过可选的 `ThemeDefinition.componentCatalog` 开放可视化编辑能力。
属性声明由主题包维护；Studio 不会从节点当前的 JSON 猜测支持的属性，也不规定全局组件名称。

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

构造主题时传入 `componentCatalog: catalog`。组件通过
`headingStyle.getValue(node.properties)` 和 `headingText.getValue(node.properties)`
读取配置，让运行时与编辑器共享默认值和可选项。枚举选项以枚举名称保存，与界面标签无关；
作者应保持名称稳定，并将默认值包含在 `choices` 中。文本沿用场景的非空字符串约定。

主题应在载入场景的边界调用 `catalog.validateDocument(document)`，然后再进行渲染。
Studio 在接收场景和编辑结果时使用同一校验。缺失属性使用声明的默认值，不会因此改写 JSON；
无效选项会抛出包含节点和属性名称的 `FormatException`。
未声明的组件和属性原样保留。该声明不改变场景格式、认证流程或组件工厂。

## 声明布局插槽

可选的 `ThemeDefinition.layout` 描述一个 `sceneId` 对应的组件装配规则。
每个 `ThemeLayoutSlot` 包含显示名称、完整的 `defaultNode` 添加模板，以及
`isRequired` 必需标记。模板中稳定的节点 ID 标识该插槽，其他组件不能占用这个 ID。
布局中的节点 ID 必须唯一。

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
);
```

构造主题时传入 `layout: layout`，并在载入场景时与属性校验一起调用
`layout.validateDocument(document)`。其他场景 ID 不受该布局约束。
模板应满足场景格式和组件属性声明，并包含正确的焦点、显隐和交互配置。
添加模板应独立于可编辑场景维护，避免保存或移除节点后，重新构建就失去再次添加它的能力。

模板只在添加插槽时使用。已有节点的位置和属性、布局外的节点继续属于场景创作数据。
Studio 禁止移除已存在的必需插槽；通过 `findMissingRequiredSlots(document)`
查询导入场景中缺失的必需项，供界面修复。缺失项不会导致载入失败。
该标记只约束组件是否存在，不验证完整的认证流程。

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
`themes/default` 在 `themes/default/perf/` 下实现了完整的 `verify` 与 `trace` 脚本；`themes/fallback` 未配置 `perf:`，也不会继承其他主题的性能阈值。
:::
