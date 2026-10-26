# Theme Studio

> [!NOTE]
> Theme Studio 目前仍处于活跃开发阶段，部分功能、交互与扩展接口仍在快速演进中。

Theme Studio 是面向 Akari 编译主题的可视化场景编辑器。编辑器界面基于 `shadcn_flutter` 构建，画布预览通过 `SceneRuntime` 实时渲染所选主题的自有组件、样式配置（Tokens）与资源。

## 启动 Studio

```sh
akari run studio --theme themes/default

# 未安装 akari 启动器时：
fvm dart run tool/akari.dart run studio --theme themes/default

# 加载仓库外的独立主题包：
fvm dart run tool/akari.dart run studio --theme /path/to/theme --jobs 2
```

- `studio` 是 `akari run` 的子目标（可通过 `akari run studio --help` 查看选项）。
- Studio 固定以 `debug` 模式运行，使用模拟显示状态，不依赖后端或 D-Bus（不接受 `--mode` 或 `--backend`）。
- 修改并保存 Dart 代码或资源后，预览会自动热重载，同时保留当前编辑文档与撤销历史；如需加载外部编辑器修改后的文件，请点击 **Reload from disk**。

> [!TIP]
> 如果终端尚未支持 `studio` 补全，请运行 `akari install cli --shell zsh`（或 `bash`）并重新加载环境脚本。

## 场景编辑流程

1. **选择主题与场景**：在顶部从 **THEME** 选择主题、从 **Scenes** 选择场景，或点击 **Load JSON** 打开磁盘上的任意 `*.scene.json`。
2. **选中节点**：在画布上点击节点，或在左侧 **Layers** 标签页中选择（包含当前预览状态下隐藏的节点，按从前到后排序）。画布选择会自动滚动到对应图层；**Assets** 独占一个完整高度的标签页，显示资源缩略图与选中文件的操作。
3. **修改布局与属性**：在右侧检查器中调整位置/尺寸（支持参考像素或百分比）、深度（`z`）、绘制顺序（`renderOrder`）、焦点顺序（`focusOrder`）、几何变换、动效（`motion`）或组件属性（`properties`）。
4. **应用到预览**：按 `Enter`、移出输入框或点击 **Apply to preview** 即可校验并应用修改。若输入无效，检查器会提示错误并保留上一次有效画面。
5. **撤销与保存**：使用 **Undo** / **Redo**（`Ctrl+Z` / `Ctrl+Shift+Z`）回退历史，点击 **Save scene**（`Ctrl+S`）以原子方式写入场景 JSON。

### 组件定制

主题可以通过 [`componentCatalog`](../reference/theme-package.md#声明组件的可编辑属性) 声明可编辑属性。Studio 会展示作者定义的组件标签、属性名称、输入框与选项菜单，并直接呈现场景 JSON 中未指定时的默认值。仅查看默认值不会修改文件或产生未保存的草稿。

默认主题目前开放：

| 组件 | 可编辑控件 |
| --- | --- |
| 标题与说明（`terraceLabel`） | **Text** 文本、**Text style: Regular / Large** 文字样式 |
| 日期与时间（`dateTime`） | **Display: Date / Time** 显示内容 |

选项修改后立即在画布生效；文本修改在按 `Enter`、失去焦点或点击 **Apply to preview** 时生效。两者均完全支持撤销重做（`Ctrl+Z` / `Ctrl+Shift+Z`）与快捷键保存（`Ctrl+S`）。若输入了未声明的无效选项（例如在高级属性中手动修改），该值无法替换当前工作预览或写入历史记录；此时可通过选项菜单重新选取有效值来修复草稿。

已声明组件的其他未声明属性仍可在 **Advanced properties** 中查看和编辑，修改可视化控件时会原样保留这些额外字段。未声明组件则沿用原有的原始属性编辑方式。切换主题会自动同步对应的属性声明定义。保存代码触发热重载时会保留当前草稿与撤销历史；若代码修改破坏了当前场景或历史状态，Studio 会保留先前主题并展示错误提示。

### 坐标单位换算

场景 JSON 始终保存 `[0, 1]` 归一化坐标，而检查器支持切换参考像素或百分比显示。以 `1920x1080` 参考画布为例，以下三种写法表示同一个矩形：

| 字段 | Scene JSON | 参考像素 | 百分比 |
| --- | --- | --- | --- |
| `X` | `0.25` | `480` | `25` |
| `Y` | `0.25` | `270` | `25` |
| `Width` | `0.5` | `960` | `50` |
| `Height` | `0.25` | `270` | `25` |

变换平移（`translateX`、`translateY`）始终使用逻辑像素，详见[场景格式](../reference/scene-format.md#transforms)。

## 画布工具与快捷键

通过 **State: Login / Dormant** 切换模拟登录/休眠状态，使用 **− / +**、**100%** 或 **Fit** 调整画布视野，并切换画布交互工具：

| 工具 | 快捷键 | 行为说明 |
| --- | --- | --- |
| **Move / Resize** | `V` | 拖动节点改变布局 `x`/`y`；拖动 8 个控制点调整 `width`/`height`（按住 `Shift` 或开启锁定图标保持宽高比）。 |
| **Hand** | `H` / `Space+拖动` | 平移画布视口，不改变节点选择或位置。 |
| **Scale** | `K` | 水平/垂直拖动调整 `scaleX`/`scaleY`（范围 `0.01..100`）。如文字被拉伸，可在 **Advanced layout -> Reset scale** 中重置为 `1`。 |
| **Rotate** | `R` | 水平拖动绕轴心调整平面旋转角（`rotationZ`）。 |
| **3D Rotate** | `Shift+R` | 水平/垂直拖动调整 3D 旋转角（`rotationY` / `rotationX`）。 |

### 常用键盘快捷键

| 快捷键 | 操作 |
| --- | --- |
| `Ctrl+鼠标滚轮` | 围绕鼠标指针缩放画布 |
| `Shift+1` | 缩放适配并重新居中画布 |
| `方向键` / `Shift+方向键` | 将选中节点微调 `1` / `10` 个参考像素 |
| `Ctrl+D` | 复制选中节点（自动命名为 `<id>-copy`、`<id>-copy-2` 等） |
| `Delete` | 删除选中节点（场景仅剩最后一个节点时禁用） |
| `Ctrl+S` | 应用待处理字段并保存场景 JSON |

> [!NOTE]
> 可交互节点受编译主题的最小点击热区（`minHitTarget`，内置主题为 44 参考像素）保护，拖动控制点时无法缩小到该尺寸以下。

## 预设项目、代码检查与偏好设置

- **预设与外部项目**：Studio 会一并编译 `themes/` 下的所有内置主题与 `--theme` 指定的主题。在 **THEME** 中切换主题（或加载已注册主题的 JSON）会同步切换组件工厂、Tokens、背景渲染器与资源列表。
- **检查生成代码（Inspect code）**：将右侧面板切到 **Inspect code**，即可按当前选中节点（**Selection**）或完整场景（**Scene**）查看并复制校验后的 **JSON** 或生成的 **Dart** 代码。
- **设置（Settings）**：按 **Canvas**、**Background**、**Appearance**、**Grid & snapping** 分类，切换分类时保留草稿；校验失败会打开需要修正的分类。
  - **Canvas** 提供 HD、Full HD、QHD、4K UHD、竖屏预设、自定义宽高、交换宽高、`fit` 和 `useSafeArea`。
  - **Background** 提供图片/颜色预览、主题资源选择、十六进制颜色输入、模糊与遮罩透明度。
  - **Appearance** 可预览浅色/深色/跟随系统及主题色；**Grid & snapping** 提供常用间距预设及 `4..512` 像素自定义间距。两个编辑器分类均可恢复默认值。
  - **Apply settings** 一次应用所有分类。画布/背景修改合并为一步撤销，需 **Save scene** 写入磁盘；编辑器偏好在应用时独立保存。**Cancel** 丢弃对话框草稿。

<a id="importing-assets"></a>

## 导入资源（Importing assets）

- **Import asset**（位于 **Assets** 标签页）：将文件复制到当前场景所属主题包的 `assets/` 目录，自动登记到 `pubspec.yaml`，并将 `packages/<theme>/assets/...` 引用路径复制到剪贴板。
- **Use image**：先选中资源缩略图，再使用列表下方的操作。校验导入图片可正常解码后，将其设为场景背景（需点击 **Save scene** 写入磁盘）。
- **外部 JSON 的资源归属**：通过 **Load JSON** 打开文件时，Studio 会向上查找最近的 `theme_*` 包目录作为资源归属包。若打开的是尚未编译的外部主题包，请使用 `--theme /path/to/theme_other` 重启 Studio 以编译其自定义组件与资源。

## 常见问题排查

| 现象 | 解决方法 |
| --- | --- |
| 缩放后文字看起来被拉伸 | 执行 **Advanced layout -> Reset scale** 恢复缩放为 `1`，再使用 **Move**（`V`）控制点调整布局尺寸。 |
| 小型可交互节点无法继续缩小 | 已达到主题设置的最小点击热区（`minHitTarget`，内置主题为 44 像素）。 |
| 字段修改或画布拖动无法生效 | 先修正右侧检查器中高亮报错的无效字段。 |
| 打开外部主题 JSON 仍显示默认组件 | 使用 `--theme /path/to/theme` 重新启动 Studio，将该主题的组件工厂编译进宿主。 |
| 新导入的图片设为背景生效，但组件内不显示 | 背景图直接从磁盘读取；组件引用的 bundle 资源需重启 Studio 后生效。 |
| 保存时提示源文件已被外部修改 | 先记下需要的修改，再执行 **Reload from disk** 重新加载最新磁盘文件。 |

## 运行检查

`akari verify` 默认包含 Studio 的静态分析与测试。也可在 `packages/theme_studio` 目录下单独运行：

```sh
../../.fvm/flutter_sdk/bin/flutter analyze
../../.fvm/flutter_sdk/bin/flutter test
```
