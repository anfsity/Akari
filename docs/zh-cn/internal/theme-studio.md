# Theme Studio

> [!NOTE]
> Theme Studio 目前处于活跃开发阶段，部分控件、工作流与扩展能力正随场景运行时持续演进。

Theme Studio 是面向 Akari 编译主题的可视化场景编辑器。编辑器工作区基于 `shadcn_flutter` 构建，画布预览通过 `SceneRuntime` 实时渲染所选主题的自有组件、样式 Token、着色器与资源。

## 启动 Studio

```sh
akari run studio --theme themes/default

# 未安装 akari 启动器时：
fvm dart run packages/akari_cli/bin/akari.dart run studio --theme themes/default

# 加载仓库外的独立主题包：
fvm dart run packages/akari_cli/bin/akari.dart run studio --theme /path/to/theme --jobs 2
```

- `studio` 是 `akari run` 的子目标（可通过 `akari run studio --help` 查看选项）。
- Studio 固定以 `debug` 模式运行，使用模拟显示数据，不依赖后端或 D-Bus（不接受 `--mode` 或 `--backend`）。
- Studio 会将 `themes/` 下的所有内置主题与 `--theme` 指定的主题一并编译进宿主，方便在顶栏直接切换。
- 修改并保存 Dart 代码或资源后，预览会自动热重载，同时保留当前编辑文档与撤销历史；如需加载外部编辑器修改后的文件，请点击 **Reload from disk**。

> [!TIP]
> 如果终端尚未支持 `studio` 补全，请运行 `akari install cli --shell zsh`（或 `bash`）并重新加载环境脚本。

## 工作区与面板布局

- **工作区模式**：可在顶栏切换 **Design**（常规设计）、**Motion**（自动展开动效检查器与底部时间轴）与 **Focus**（隐藏两侧面板专注画布）。
- **面板折叠与浮动停靠**：支持快捷键折叠左侧栏（`Ctrl+B`）、折叠右侧检查器（`Ctrl+Shift+B`）或进入全屏沉浸预览（`Ctrl+Shift+P`，按 `Escape` 退出）。双击面板标题可折叠面板；点击浮动按钮可将面板拆分为独立浮窗（支持拖动标题栏、拖拽右下角缩放，或通过 **Dock left/right** 及边缘拖拽重新停靠为标签页组）。
- **布局偏好持久化**：面板停靠位置、宽度、浮窗尺寸与工作区模式会作为用户偏好自动保存，下次启动时恢复，且不会写入场景撤销历史。

## 场景编辑流程

1. **选择主题与场景**：在顶栏从 **Theme** 选择主题、从 **Scenes** 选择场景，点击 **New scene** 在当前主题下新建空白画板，或点击 **Load JSON** 打开磁盘上的任意 `*.scene.json`。
2. **装配与选择图层**：在左侧 **Compose** 面板开关布局插槽、切换主题预设或拖入基础图元；在 **Layers** 面板查看从前到后的完整图层树（含当前隐藏节点）；在 **Assets** 面板检索或导入资源。
3. **在检查器中定制属性**：在右侧检查器修改组件专属属性、视觉样式 Token、几何尺寸、Frame 自动布局及动效参数。
4. **应用与实时预览**：下拉选项与滑块会实时更新画布（松开滑块合并为一步撤销）；文本与数值输入框在按 `Enter`、移出焦点或点击 **Apply to preview** 时校验生效。若输入非法，检查器会高亮提示错误并保留上一次有效画面。
5. **撤销与保存**：使用 **Undo** / **Redo**（`Ctrl+Z` / `Ctrl+Shift+Z`）回退历史，点击 **Save scene**（`Ctrl+S`）以原子方式写入场景 JSON。

### 组件属性与视觉样式

- **组件可编辑属性（`componentCatalog`）**：主题可通过 [`componentCatalog`](../reference/theme-package.md#声明组件的可编辑属性) 声明类型化属性。Studio 会自动渲染作者定义的属性标签、文本框与下拉菜单（JSON 中省略时直接展示默认值）。未声明的自定义键值仍可在 **Advanced properties** 中编辑。
  - 默认主题开放的属性包括：标题与说明（`terraceLabel`）的 **Text** 与 **Text style**（`Regular` / `Large`）；日期与时间（`dateTime`）的 **Display**（`Date` / `Time`）；待机时钟（`terraceClock`）的 **Clock style**（`Wide display` / `Stacked digits` / `Compact`）。
- **视觉样式 Token（`styleTokens`）**：在检查器的 **Visual style** 中可配置纯色填充、双色线性渐变、边框、圆角、投影、局部背景模糊、不透明度以及字体排版（字体文件、字号、字重、字间距与行高）。首次修改会创建场景 `styleToken`，多个图层可复用同一 Token 并同步更新。

### 布局插槽装配与主题预设

- **基础组件库（图元与容器）**：通过 **Compose → Component library** 可重复添加通用 **Text**（`T`）、**Rectangle**（`U`）、**Circle** 与 **Frame**（`F`）图层，或水平拖拽至画布指定位置。双击画布上的文本图层即可原位编辑文字（`Enter` 提交，`Escape` 取消）。
- **声明式布局插槽**：对于声明了 [`ThemeLayoutDefinition`](../reference/theme-package.md#声明布局插槽) 的场景，**Compose** 面板提供可选组件复选框与 **Required controls** 清单，必需组件以锁图标标记：
  - 开启或关闭可选组件会按预设位置插入或移除节点（移除后可通过 **Undo** 恢复此前的自定义修改）。
  - 必需控件受删除保护；若打开的场景缺失必需插槽，侧栏顶部会提示 **Add required**，支持一键补齐全部缺失控件。
- **布局预设（Layout preset）**：在 **Compose → Layout preset** 中切换不同布局骨架（如默认主题的 `Terrace split` 分屏与 `Centered column` 居中列），在重排插槽几何位置的同时保留组件属性、已关闭的可选组件与自定义图层。
- **主题全局预设（Theme presets）**：在 **Compose → Theme presets** 中切换主题通过 [`presetCatalog`](../reference/theme-package.md#声明主题级全局预设) 声明的全局风格（保存在 `themeProperties`）。例如默认主题提供四种配色（壁纸取色、`Ocean`、`Rose`、`Violet`）、三种控件材质（通透下划线、磨砂胶囊、实色）与三种动效配置。

### 合成独立主题项目

点击 **Create theme**，输入小写主题名称与目标父目录后确认：

- Studio 会将当前有效设计（包括尚未保存的检查器修改）导出为独立的 `theme_<name>` 包，不会覆盖源主题。
- 场景文件、Dart 源码、资源、字体、着色器与许可证会被完整复制，跨包引用的图片资源会自动归档至新包 `assets/` 目录，且 SDK 路径依赖会自动重新定位。
- 新项目会保留在当前 Studio 的 **Theme** 选择器中；也可通过 CLI 独立打开、运行或构建：

```sh
akari run studio --theme /path/to/new_theme
akari run --theme /path/to/new_theme
akari build --theme /path/to/new_theme
```

### 图层树、容器 Frame 与响应式布局

- **多选、对齐与分组**：支持 `Shift` 点击多选、空白处拖拽框选与 `Ctrl+A` 全选。选中多个同级图层后，可通过上下文工具条执行边缘/中心对齐、等距分布，或按 `Ctrl+G` 组合为容器 Frame（普通绝对布局容器可通过 `Ctrl+Shift+G` 解组并保留子节点屏幕位置）。
- **拖拽重排与父子嵌套**：在 **Layers** 面板中上下拖动图层可调整同级绘制顺序，拖入 Frame 行中央可将其收为子节点，或选择 **Move to scene root** 移回根级。
- **Frame 自动布局**：在检查器的 **Frame layout** 中可切换 `absolute`、`row` 或 `column` 排布方向，并配置 `padding`、`gap`、主轴/交叉轴对齐、自动换行（`wrap`）与溢出裁剪（`clip`）。
- **尺寸模式与响应式断点**：支持 `Width mode` 与 `Height mode`（`proportional` 按比例、`fill` 填充剩余空间、`hug` 自适应内容尺寸）、固定像素宽高、`min`/`max` 尺寸限制（展开 **Size constraints**）以及 `flex` 权重。点击布局选择器旁的 **+** / **−** 可按逻辑视口 `minWidth` 添加或移除响应式断点规则。
- **响应式与多分辨率对比预览**：
  - 点击画布下方的 **Responsive** 可连续拖动预览视口宽高以检验断点效果，不会修改场景文档或历史（点击 **Authored size** 返回常规几何编辑）。
  - 使用底部分辨率选择器可一键切换 HD、Full HD、QHD、4K、竖屏、16:10 或带鱼屏参考尺寸；点击 **Compare** 可同屏对比 Full HD、4K、带鱼屏与竖屏四种输出效果（点击 **Single** 返回单画布）。

### 坐标单位换算

场景 JSON 始终保存 `[0, 1]` 归一化坐标，而检查器支持切换参考像素或百分比显示。以 `1920x1080` 参考画布为例，以下三种写法表示同一个矩形：

| 字段 | Scene JSON | 参考像素 | 百分比 |
| --- | --- | --- | --- |
| `X` | `0.25` | `480` | `25` |
| `Y` | `0.25` | `270` | `25` |
| `Width` | `0.5` | `960` | `50` |
| `Height` | `0.25` | `270` | `25` |

变换平移（`translateX`、`translateY`）始终使用逻辑像素，详见[场景格式](../reference/scene-format.md#transforms)。

## 动效、时间轴与状态流

- **交互预览与状态模拟**：点击 **Preview** 可播放主题动效并测试输入焦点、悬停反馈与下拉菜单（点击 **Edit canvas** 返回几何编辑）。通过 **State: Login / Dormant** 切换登录/休眠状态，或使用场景菜单模拟密码/用户名输入、提交中、凭据被拒、认证报错、账户/会话选择、连接中与服务不可用等状态。
- **状态流与转换边（State flow）**：打开 **State flow** 即可点击预览休眠、登录、提交、成功与报错状态，并为选中图层配置有向状态转换边（起始条件 `from`、目标条件 `to`、`Shake` / `Pulse` 动效及时长/延迟）。在 **Design → State rules → Edit compound condition** 中可通过可视化组合器编辑嵌套的 `all` / `any` / `not` 显示条件。
- **时间轴与属性关键帧（Timeline）**：打开 **Timeline** 可逐帧拖动或播放入场、唤醒、休眠及提交结果过渡。拖动图层色块可调整 `delayMs`，拖动右侧手柄可缩放 `durationMs`；支持为 `opacity`、`translateX`、`translateY`、`scale` 与 `rotation` 添加关键帧轨道，拖动菱形关键帧调整时间，或双击关键帧修改数值与区间缓动（`linear`、`easeInOut`、`hold`）。
- **节点级时序与错峰入场**：在 **Advanced layout → Motion** 中可单独设置节点的时长、延迟与三次贝塞尔曲线；多选图层后点击 **Stagger 100 ms** 可按绘制顺序一键生成依次递增的延迟。

## 背景特效与 Shader Playground

- **背景模糊与渲染参数（Effects）**：右侧 **Effects** 标签页可直接调节背景高斯模糊（`blurSigma`）与遮罩不透明度（`scrimOpacity`）。若当前背景渲染器声明了 `BackgroundParameter`（如 `themes/preset1` 的折射强度、雨滴密度、水流速度与色散），面板会自动展示对应的实时滑块。
- **Shader Playground**：打开 **Effects → Shader Playground** 可加载主题已有的 `.frag` 着色器或从模板开始编写：
  - 点击 **Compile and preview** 调用工作区 Flutter SDK 的 `impellerc` 实时编译，展示编译诊断信息，并自动反射出 `float`/向量 Uniform 槽位与 `sampler2D` 纹理槽位。
  - 可将每个浮点槽位绑定到常量、运行时间（`time`）、逻辑视口宽高（`width`/`height`）、指针坐标（`pointerX`/`pointerY`）、休眠状态（`dormant`）或认证错误（`authError`），并配置缩放倍率与偏移量；将纹理采样器绑定到主题内的图片资源。
  - 点击 **Apply as new shader** 会将着色器源码保存到主题包目录、自动登记到 `pubspec.yaml` 的 `flutter.shaders`，并在一步撤销内完成场景背景绑定。

## 画布工具、标尺与快捷键

- **标尺与参考线**：点击画布下方的标尺按钮显示顶部与左侧标尺。从顶部标尺向下拖出垂直参考线，从左侧标尺向右拖出水平参考线；拖动参考线可调整位置，双击即可删除。参考线随场景 JSON 保存，但不会在正式登录界面中绘制。
- **智能对齐与网格吸附**：移动或缩放节点时，会在 6 个屏幕像素阈值内自动吸附到可见组件边缘/中心、画布边界及标尺参考线，并实时标注相邻间距。可通过磁铁按钮开关智能参考线、按住 `Alt` 临时跳过吸附，或在 **Settings → Grid & snapping** 中配置网格吸附间距。

| 工具 | 快捷键 | 行为说明 |
| --- | --- | --- |
| **Move / Resize** | `V` | 拖动节点改变布局 `x`/`y`；拖动 8 个控制点调整 `width`/`height`（按住 `Shift` 或开启锁定图标保持宽高比）。 |
| **Hand** | `H` / `Space+拖动` | 平移画布视口，不改变节点选择或位置。 |
| **Scale** | `K` | 水平/垂直拖动调整 `scaleX`/`scaleY`（范围 `0.01..100`）。如文字被拉伸，可在 **Advanced layout -> Reset scale** 中重置为 `1`。 |
| **Rotate** | `R` | 水平拖动绕轴心调整平面旋转角（`rotationZ`）。 |
| **3D Rotate** | `Shift+R` | 水平/垂直拖动调整 3D 旋转角（`rotationY` / `rotationX`）。 |

### 键盘与鼠标快捷键

可在 **Settings → Shortcuts** 中自定义键盘快捷键、鼠标中键/右键平移手势及滚轮缩放修饰键：

| 快捷键 | 操作 |
| --- | --- |
| `Ctrl+鼠标滚轮` | 围绕鼠标指针缩放画布 |
| `Shift+1` | 缩放适配并重新居中画布 |
| `方向键` / `Shift+方向键` | 将选中节点微调 `1` / `10` 个参考像素 |
| `T` / `U` / `F` | 快速创建文本（Text）、矩形（Rectangle）或容器（Frame）图层 |
| `Ctrl+G` / `Ctrl+Shift+G` | 将选中同级图层组合为 Frame / 解组普通绝对布局 Frame |
| `Ctrl+D` | 复制布局插槽以外的节点（自动命名为 `<id>-copy`、`<id>-copy-2` 等） |
| `Delete` | 删除选中节点（必需插槽或场景最后一个节点禁用） |
| `Ctrl+B` / `Ctrl+Shift+B` | 折叠/展开左侧栏或右侧检查器 |
| `Ctrl+Shift+P` | 进入/退出全屏沉浸预览（`Escape` 退出） |
| `Ctrl+S` | 应用待处理字段并保存场景 JSON |

> [!NOTE]
> 可交互节点受编译主题的最小点击热区（`minHitTarget`，内置主题为 44 参考像素）保护，拖动控制点时无法缩小到该尺寸以下。

<a id="importing-assets"></a>

## 导入与管理资源（Importing assets）

- **检索与分类筛选**：在 **Assets** 面板中按路径搜索，或按图片、SVG 图标、字体、材质纹理、音频、着色器及其他文件分类过滤。
- **Import asset**：将外部文件复制到当前场景所属主题包的 `assets/` 目录，自动登记到 `pubspec.yaml`，并将 `packages/<theme>/assets/...` 引用路径复制到剪贴板。
- **Add to canvas**：将图片或 SVG 直接添加为独立的画布资源图层（`sceneAsset`），可在检查器中设置填充模式（`fit`）与着色覆盖（`tint`）。
- **Use image**：校验位图可正常解码后将其设为当前场景背景（需点击 **Save scene** 写入磁盘）。
- **字体预览与应用**：支持调整字号预览字体效果，点击 **Apply font** 即可将该字体绑定到选中图层的 `styleToken`。
- **外部 JSON 的资源归属**：通过 **Load JSON** 打开文件时，Studio 会向上查找最近的 `theme_*` 包目录作为资源归属包。若需加载未编译外部主题的自定义 Dart 组件，请使用 `--theme /path/to/theme_other` 重启 Studio。

## 检查代码与偏好设置

- **检查生成代码（Inspect code）**：将右侧面板从 **Design** 切到 **Inspect code**，即可按当前选中节点（**Selection**）或完整场景（**Scene**）查看并复制校验后的 **JSON** 或生成的 **Dart** 代码（此模式下编辑控件只读）。
- **偏好设置（Settings）**：按 **Canvas**（参考分辨率预设、宽高互换、`fit`、`useSafeArea`）、**Background**（背景图、底色、模糊与遮罩）、**Appearance**（浅色/深色/跟随系统与编辑器配色）、**Grid & snapping**（网格间距与吸附）以及 **Shortcuts**（键鼠绑定）分类管理。

## 常见问题排查

| 现象 | 解决方法 |
| --- | --- |
| 缩放后文字看起来被拉伸 | 执行 **Advanced layout -> Reset scale** 恢复缩放为 `1`，再使用 **Move**（`V`）控制点调整布局尺寸。 |
| 小型可交互节点无法继续缩小 | 已达到主题设置的最小点击热区（`minHitTarget`，内置主题为 44 像素）。 |
| 字段修改或画布拖动无法生效 | 先修正右侧检查器中高亮报错的无效字段。 |
| 打开外部主题 JSON 仍显示默认组件 | 使用 `--theme /path/to/theme` 重新启动 Studio，将该主题的组件工厂编译进宿主。 |
| 新导入的图片或 SVG 图层未显示 | 使用 **Add to canvas** 添加图层（资源图层与背景均直接从磁盘读取）；若主题自定义 Widget 通过 bundle 加载资源，则需重启 Studio。 |
| 保存时提示源文件已被外部修改 | 先记下需要的修改，再执行 **Reload from disk** 重新加载最新磁盘文件。 |

## 运行检查

`akari verify` 默认包含 Studio 的静态分析与测试。也可在 `packages/theme_studio` 目录下单独运行：

```sh
../../.fvm/flutter_sdk/bin/flutter analyze
../../.fvm/flutter_sdk/bin/flutter test
```
