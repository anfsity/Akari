---
title: 场景格式
description: 版本 3 场景 JSON 的字段定义、容器布局、样式 Token 与动效规范。
---

场景 JSON 文件（`*.scene.json`）定义主题的画布、背景、节点层级、视觉样式、几何变换与可见性条件。构建时由 `packages/scene_schema` 校验 JSON 并生成类型化 Dart 代码（`*.scene.g.dart`），正式应用直接运行生成代码，无需在登录时解析 JSON。

:::note
当前场景格式版本为 `3`。解码器向下兼容版本 `1` 和 `2`，会自动规范化旧版 `kind`/`action` 字段并保留已有扁平布局行为。
:::

## 最小示例

```json
{
  "id": "ocean",
  "version": 3,
  "canvas": {
    "fit": "contain",
    "useSafeArea": true,
    "referenceWidth": 1920,
    "referenceHeight": 1080
  },
  "background": {
    "kind": "solid",
    "color": "#0d151a"
  },
  "nodes": [
    {
      "id": "clock",
      "component": "dateTime",
      "rect": { "x": 0.3, "y": 0.4, "width": 0.4, "height": 0.2 },
      "properties": { "variant": "time" }
    }
  ]
}
```

- 每个场景至少包含一个节点。
- 节点 `id` 在文档内必须唯一，`component` 标识符不能为空。

## 根级文档字段

| 字段 | 类型 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 必填 | 唯一场景标识符 |
| `version` | `1 \| 2 \| 3` | `3` | 场景格式版本 |
| `canvas` | Canvas 对象 | 必填 | 参考分辨率、视口缩放策略与安全区域设置 |
| `background` | Background 对象 | 必填 | 背景渲染器类型、资源、着色器或渲染参数 |
| `nodes` | `Array<SceneNode>` | 必填（非空） | 场景中的组件节点、容器 Frame、基础图元或资源图层 |
| `themeProperties` | `Record<string, string>` | `{}` | 主题级全局预设键值（如 `{"palette": "ocean", "motion": "gentle"}`），由主题的 `presetCatalog` 校验与解析 |
| `styleTokens` | `Record<string, SceneStyle>` | `{}` | 可复用的视觉样式定义表，供节点通过 `styleToken` 引用 |
| `guides` | `Array<SceneGuide>` | `[]` | Studio 标尺参考线（`{"axis": "vertical" \| "horizontal", "position": 0..1}`），随文档保存与编译，不在登录界面中绘制 |

## 画布（`canvas`）

| 字段 | 类型 / 可选值 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `fit` | `"cover"` \| `"contain"` \| `"reflow"` | 必填 | 画布相对屏幕视口的缩放适配策略 |
| `useSafeArea` | `boolean` | `true` | 是否在安全区域（Safe Area）内排布节点 |
| `referenceWidth` | `1..16384` | `1920` | 参考宽度（像素，供 Studio 像素换算与参考线定位使用） |
| `referenceHeight` | `1..16384` | `1080` | 参考高度（像素，供 Studio 像素换算与参考线定位使用） |

## 背景（`background`）

| 字段 | 类型 / 可选值 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `kind` | `"image"` \| `"solid"` \| `"video"` \| `"custom"` | 必填 | 背景渲染器类型 |
| `asset` | `string` | 不设置 | 打包图片或渲染资源路径（如 `packages/theme_ocean/assets/bg.jpg`） |
| `color` | `#RRGGBB` \| `#AARRGGBB` | `"#0d151a"` | 纯色填充或回退底色 |
| `scrimOpacity` | `0.0..1.0` | `0.35` | 遮罩层不透明度 |
| `blurSigma` | `>= 0` | `0` | 唤醒过渡期间应用的画布高斯模糊强度 |
| `rendererId` | `string` | 不设置 | 在 `ThemeBundle` 中注册的自定义渲染器标识符 |
| `parameters` | `Record<string, number>` | `{}` | 传给自定义背景渲染器的有限数值参数（主题通过 `BackgroundParameter` 声明范围后可在 Studio 中通过滑块实时调节，如 `theme_preset1` 的 `refraction`、`density`、`speed`、`dispersion`） |
| `shader` | Shader 对象 | 不设置 | 为 `custom` 背景配置的运行时便携式片元着色器 |

:::caution
内置渲染器原生支持 `image`、`solid` 以及附带 `shader` 定义的 `custom` 背景。其他 `video` 或 `custom` 背景需在主题的 `ThemeBundle` 中注册对应实现。资源路径不得包含 `..`。
:::

### 便携式片元着色器（`shader`）

当 `background.kind` 为 `"custom"` 时，可通过 `shader` 字段直接绑定 `.frag` 着色器与纹理，无需编写自定义 Dart 绘制代码：

```json
{
  "asset": "packages/theme_ocean/assets/background.frag",
  "uniforms": [
    {"name": "resolution.x", "source": "width"},
    {"name": "resolution.y", "source": "height"},
    {"name": "time", "source": "time", "scale": 0.5, "value": 0}
  ],
  "textures": [
    {"name": "image", "asset": "packages/theme_ocean/assets/texture.png"}
  ]
}
```

- **`asset`**：在 `pubspec.yaml` 的 `flutter.shaders` 下声明的 `.frag` 着色器资源路径。
- **`uniforms`**：按编译器反射顺序排列的浮点槽位绑定。每个槽位计算公式为 `source * scale + value`（默认 `scale: 1`、`value: 0`）。支持的 `source` 数据源：
  - `constant`（`source = 0`，直接取 `value` 常量）
  - `time`（运行秒数；在减少动效模式下固定为 `0`，在 Studio 时间轴拖动时按采样时间确定性求值）
  - `width`、`height`（逻辑视口宽高）
  - `pointerX`、`pointerY`（逻辑像素指针坐标）
  - `dormant`、`authError`（激活时为 `1.0`，否则为 `0.0`）
- **`textures`**：按顺序绑定的 `sampler2D` 纹理图片列表（`{"name": "...", "asset": "..."}`）。

## 节点（`nodes`）

| 字段 | 类型 / 可选值 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 必填 | 文档内唯一的节点 ID |
| `component` | `string` | 必填 | 交给主题组件工厂解析的组件标识符（容器 Frame 通常为 `"frame"`，资源图层为 `"sceneAsset"`） |
| `parentId` | `string` | 不设置 | 所属父容器 Frame 的节点 ID（目标节点必须声明了 `layout`） |
| `rect` | `{ x, y, width, height }` | 必填 | 相对画布或父容器内边距区域的归一化坐标（`0..1`） |
| `z` | `number` | `0` | 空间深度 |
| `renderOrder` | `integer` | `0` | 同一父级内的绘制顺序（与 `z` 和 `focusOrder` 相互独立） |
| `focusOrder` | `integer` | `0` | 键盘 Tab 焦点遍历顺序 |
| `motion` | `"none"` \| `"fade"` \| `"fadeSlide"` \| `"fadeScale"` \| `"hoverLift"` \| `"focusGlow"` | `"none"` | 进出场或交互动效预设 |
| `motionTiming` | `{ durationMs?, delayMs?, curve? }` | 继承主题 | 节点级动画时长（`0..60000`）、延迟（`0..60000`）与三次贝塞尔曲线 `[x1, y1, x2, y2]`（`0..1`） |
| `tracks` | `Array<ScenePropertyTrack>` | `[]` | 属性关键帧轨道（支持 `opacity`、`translateX`、`translateY`、`scale`、`rotation`） |
| `stateEffects` | `Record<ScenePredicate, "shake" \| "pulse">` | `{}` | 指定状态谓词变为真时触发的单次视觉反馈 |
| `transitions` | `Array<SceneTransitionEdge>` | `[]` | 显式声明 `from` -> `to` 条件跃迁的视觉效果（`"shake"` \| `"pulse"`） |
| `visibleWhen` | 条件对象 / 字符串 | 不设置 | 声明式显示条件（省略时始终显示） |
| `interactive` | `boolean` | `false` | 是否为可交互节点（强制启用最小点击热区 `minHitTarget` 与焦点遍历） |
| `properties` | `Record<string, string>` | `{}` | 由具体组件解析的字符串键值属性（文本图元读取 `properties.text`） |
| `styleToken` | `string` | 不设置 | 引用根级 `styleTokens` 中的样式名称 |
| `primitive` | `"text"` \| `"rectangle"` \| `"circle"` | 不设置 | 由运行时直接绘制的基础几何图元或文本（与 `asset`、`layout` 互斥） |
| `asset` | `{ path, kind?, fit?, tint? }` | 不设置 | 由运行时直接绘制的图片或 SVG 图层（与 `primitive`、`layout` 互斥） |
| `layout` | Frame 布局对象 | 不设置 | 将节点声明为容器 Frame（与 `primitive`、`asset` 互斥） |
| `sizing` | Sizing 对象 | 按比例 | 宽高模式（`proportional`、`fill`、`hug`）、固定像素尺寸、`min`/`max` 限制及 `flex` 权重 |
| `breakpoints` | `Array<SceneBreakpoint>` | `[]` | 按逻辑视口最小宽度（`minWidth`）覆盖 `layout` 与 `sizing` 的响应式断点列表 |
| `transform` | 变换对象 | 单位变换 | 节点局部的平移、缩放、旋转、轴心与透视 |

## 基础图元与资源图层（`primitive` & `asset`）

节点可直接由 `SceneRuntime` 渲染通用图形、文本或图片资源，无需在主题组件工厂中编写额外代码：

- **基础图元（`primitive`）**：支持 `"text"`、`"rectangle"` 和 `"circle"`。文本图元读取 `properties.text`，并应用 `styleToken` 中的文字与外观样式。
- **图片与 SVG 图层（`asset`）**：在节点上配置 `asset` 即可直接渲染位图或 SVG 矢量图（`component` 标识通常设为 `"sceneAsset"`）：

| 字段 | 类型 / 可选值 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `path` | `string` | 必填 | `assets/` 或 `packages/<包名>/` 下的打包资源路径（拒绝绝对路径、反斜杠与 `..`） |
| `kind` | `"image"` \| `"svg"` | `"image"` | 位图或 SVG 矢量图 |
| `fit` | `"contain"` \| `"cover"` \| `"fill"` | `"contain"` | 图像在节点矩形内的缩放填充方式 |
| `tint` | `#RRGGBB` \| `#AARRGGBB` | 不设置 | 保留原图透明度的着色覆盖值 |

```json
{
  "id": "logo",
  "component": "sceneAsset",
  "rect": { "x": 0.45, "y": 0.1, "width": 0.1, "height": 0.1 },
  "asset": {
    "path": "packages/theme_ocean/assets/logo.svg",
    "kind": "svg",
    "fit": "contain",
    "tint": "#ffffff"
  }
}
```

## 视觉样式与字体排版（`styleTokens`）

根字段 `styleTokens` 按名称保存 `SceneStyle` 样式定义，多个节点可共享同一个 `styleToken`：

| 字段 | 类型 / 可选值 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `fill` | `#RRGGBB` \| `#AARRGGBB` | 不设置 | 纯色填充或线性渐变起始色 |
| `gradientEnd` | `#RRGGBB` \| `#AARRGGBB` | 不设置 | 双色线性渐变结束色 |
| `gradientAngle` | `number`（角度） | `0` | 线性渐变角度 |
| `border` | `#RRGGBB` \| `#AARRGGBB` | 不设置 | 边框颜色 |
| `borderWidth` | `>= 0`（逻辑像素） | `0` | 边框宽度 |
| `radius` | `>= 0`（逻辑像素） | `0` | 圆角半径 |
| `shadow` | `#RRGGBB` \| `#AARRGGBB` | 不设置 | 投影颜色 |
| `shadowBlur` | `>= 0`（逻辑像素） | `0` | 投影模糊半径 |
| `shadowY` | `number`（逻辑像素） | `0` | 投影垂直偏移量 |
| `backgroundBlur` | `>= 0`（sigma） | `0` | 节点背后的局部背景模糊强度 |
| `opacity` | `0.0..1.0` | `1.0` | 图层不透明度乘数 |
| `textColor` | `#RRGGBB` \| `#AARRGGBB` | 继承 | 文字颜色覆盖 |
| `fontSize` | `>= 0`（逻辑像素） | `0`（继承） | 字号覆盖 |
| `fontAsset` | `string` | 不设置 | 打包字体资源路径（正式环境从 bundle 加载，Studio 从磁盘加载） |
| `fontWeight` | `0` 或 `100..900`（步长 100） | `0`（继承） | 字重覆盖 |
| `letterSpacing` | `number`（逻辑像素） | 不设置 | 字间距覆盖 |
| `lineHeight` | `> 0`（字号倍数） | 不设置 | 行高倍数覆盖 |

拥有显式文字样式的主题组件可通过 `getSceneTextStyle(context, fallback)` 接入 `styleToken` 的排版覆盖（默认主题的 Terrace 标签与时钟已接入）。

## 动效时序、关键帧轨道与状态转换

### 节点动效时序（`motionTiming`）

- `durationMs`（`0..60000` 整数毫秒，省略时继承主题默认时长）
- `delayMs`（`0..60000` 整数毫秒，默认 `0`）
- `curve`（`[x1, y1, x2, y2]`，控制点范围 `0..1`，省略时继承主题缓动曲线）

延迟与时长纳入同一个进出场控制器，动画中途反向切换时能沿当前进度平滑回退。系统与主题的减少动效（Reduced Motion）设置优先。

### 属性关键帧轨道（`tracks`）

每个节点可为 `opacity`、`translateX`、`translateY`、`scale` 或 `rotation`（角度）各声明至多一条关键帧轨道。关键帧按 `timeMs`（`0..60000`，相对 `delayMs` 偏移）严格递增，包含有限数值 `value`（`opacity` 为 `0..1`，其余为 `-100000..100000`）及作用于后续区间的 `curve`（默认 `"linear"`，可选 `"easeInOut"` 或 `"hold"`）：

```json
{
  "property": "opacity",
  "keyframes": [
    { "timeMs": 0, "value": 0 },
    { "timeMs": 800, "value": 1, "curve": "hold" }
  ]
}
```

### 状态效果与转换边（`stateEffects` & `transitions`）

- **`stateEffects`**：将状态谓词映射到 `"shake"` 或 `"pulse"`（如 `{"isAuthError": "shake"}`），在进入该状态时播放一次视觉反馈。
- **`transitions`**：定义带 `from` 与 `to` 条件（语法与 `visibleWhen` 相同）、`effect`（`"shake"` \| `"pulse"`）及可选 `timing` 的有向状态转换边。当前一帧满足 `from` 且当前帧新满足 `to` 时触发；显式 `transitions` 优先于 `stateEffects`。

## 容器 Frame、自动布局与响应式断点

为节点配置 `layout` 即可创建由运行时管理的容器 Frame（`"component": "frame"`）。子节点通过 `parentId` 指向容器 ID，容器的可见性、透明度与几何变换作用于整棵子树，`renderOrder` 在同一父容器内比较。

```json
{
  "id": "form",
  "component": "frame",
  "rect": { "x": 0.25, "y": 0.2, "width": 0.5, "height": 0.6 },
  "layout": {
    "direction": "column",
    "padding": 24,
    "gap": 12,
    "crossAlignment": "stretch"
  }
}
```

### 容器布局属性（`layout`）

| 字段 | 类型 / 可选值 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `direction` | `"absolute"` \| `"row"` \| `"column"` | `"absolute"` | 子节点排布方式（`row` 与 `column` 自动接管子节点位置） |
| `padding` | `>= 0`（逻辑像素） | `0` | 容器内边距 |
| `gap` | `>= 0`（逻辑像素） | `0` | 子节点之间及换行行间的间距 |
| `mainAlignment` | `"start"` \| `"center"` \| `"end"` \| `"spaceBetween"` | `"start"` | 主轴对齐与分布方式 |
| `crossAlignment` | `"start"` \| `"center"` \| `"end"` \| `"stretch"` | `"start"` | 交叉轴对齐方式 |
| `wrap` | `boolean` | `false` | `row`/`column` 子节点超出主轴时是否自动换行 |
| `clip` | `boolean` | `false` | 是否裁剪超出容器边界的子节点内容 |

在 `row` 和 `column` 自动布局中，因 `visibleWhen` 隐藏的子节点仍保留布局占位，避免认证状态切换时相邻控件发生跳动。

### 尺寸模式与约束（`sizing`）

- **`widthMode` / `heightMode`**：支持 `"proportional"`（默认，按 `rect` 比例）、`"fill"`（填充剩余空间）或 `"hug"`（按容器子项边界或文本图元实际字形尺寸自适应包裹）。
- **固定尺寸与上下限**：可选的正数 `width` / `height`（优先于比例与填充模式）、`minWidth` / `minHeight`（默认 `0`）以及 `maxWidth` / `maxHeight`（`>= min`）。可交互节点的 `minHitTarget` 优先于最大尺寸限制。
- **`flex`**：非负权重，用于在 `row`/`column` 主轴上分配剩余空间。

### 响应式断点（`breakpoints`）

节点可通过 `breakpoints: [{ "minWidth": 1280, "layout": {...}, "sizing": {...} }]` 声明按逻辑视口宽度触发的覆盖规则。`minWidth` 在 `0..16384` 内必须唯一，运行时自动匹配满足当前视口宽度的最大断点规则。

<a id="transforms"></a>

## 几何变换（`transform`）

节点 `rect` 使用画布归一化比例（`0..1`），而 `transform` 字段使用以下单位：

| 字段 | 单位 | 默认值 |
| --- | --- | --- |
| `translateX`、`translateY` | 逻辑像素 | `0` |
| `scaleX`、`scaleY` | 缩放倍率 | `1` |
| `rotationX`、`rotationY`、`rotationZ` | 角度（度） | `0` |
| `pivotX`、`pivotY` | 相对节点自身尺寸的比例（`0..1`） | `0.5` |
| `perspective` | 矩阵透视系数 | `0` |

## 显示条件（`visibleWhen`）

单个 `ScenePredicate` 名称本身即构成条件，也可通过 `all`、`any`、`not` 组合（每个条件对象仅包含一个运算符）：

```json
{
  "all": [
    { "not": "isDormant" },
    { "any": ["isAuthPrompting", "isAuthError"] }
  ]
}
```

完整谓词列表请查阅 [API 参考](api.md)中的 `ScenePredicate` 枚举。

:::tip[配合休眠状态使用]
按下 `Escape` 进入休眠状态（`isDormant`）不会中断正在进行的认证提示，因此 `isAuthPrompting` 等谓词可能与 `isDormant` 同时为真。若希望登录控件在休眠时隐藏，请在外层组合 `{ "not": "isDormant" }`。
:::
