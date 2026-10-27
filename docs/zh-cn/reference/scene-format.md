---
title: 场景格式
description: 场景 JSON 的字段、示例和校验规则，当前版本为 3。
---

场景 JSON 文件（`*.scene.json`）定义主题的画布、背景、节点、几何变换与可见性条件。构建时由 `packages/scene_schema` 校验 JSON 并生成类型化 Dart 代码（`*.scene.g.dart`），正式应用直接运行生成代码，无需在登录时解析 JSON。

:::note
当前场景格式版本为 `3`。解码器兼容版本 `1` 和 `2`，自动规范化旧版 `kind`/`action`，并保留已有扁平布局的行为。
:::

## 可复用视觉样式

根字段 `styleTokens` 按名称保存样式，节点通过 `styleToken` 引用；不存在的引用
会被拒绝。支持 `fill`、可选 `gradientEnd`、`gradientAngle`、`border`、
`borderWidth`、`radius`、`shadow`、`shadowBlur`、`shadowY`、`backgroundBlur`、
可选 `textColor`、`fontSize`（0 表示继承）和 `opacity`（0..1）。颜色采用 ARGB，
尺寸采用逻辑像素。多个节点可共享一个 token。组件的显式文字样式可以通过
`getSceneTextStyle(context, fallback)` 接入覆盖值；Terrace 标签与时钟已接入。

## 动效时序

`stateEffects` 可声明进入状态时的视觉响应，例如 `{"isAuthError": "shake"}`。
支持 `shake` 和 `pulse`，使用节点时序；无关状态通知不会重播，减少动画策略仍生效。
多个规则同时触发时，最后声明的规则优先。认证状态转移由认证模块负责。

节点可通过 `motionTiming` 保存 `durationMs`、`delayMs` 与
`curve: [x1,y1,x2,y2]`。时长与延迟为 0..60000 的整数毫秒，贝塞尔控制点为
0..1。省略时长或曲线会继承主题设置。延迟纳入同一控制器，反向切换沿当前进度
连续播放；Studio 时间轴采样与实际 Greeter 使用相同计算。系统和主题的减少动画
策略优先。

## 容器与自动布局

背景可通过 `parameters` 保存渲染器定义的有限数值参数。渲染器通过
`BackgroundParameter` 声明标签、范围和默认值，Studio 显示对应滑块。
Preset1 支持 refraction（0..3）、density（0..2）、speed（0.1..4）、
dispersion（0..4）；省略参数保留原始效果。参数随 JSON 保存并生成生产 Dart。

节点声明 `layout` 后成为运行时管理的 Frame，不调用主题组件工厂。
子节点通过 `parentId` 引用容器，`rect` 相对父容器的内边距区域。
容器的变换与可见性作用于整棵子树，绘制顺序在同一父容器内比较。
解码器拒绝不存在的父节点、非容器父节点和循环引用。

`layout.direction` 支持 `absolute`、`row`、`column`；`padding`、`gap`
采用非负逻辑像素。`mainAlignment` 支持 `start`、`center`、`end`、
`spaceBetween`，`crossAlignment` 支持 `start`、`center`、`end`、`stretch`。
`clip: true` 裁剪溢出内容。

子节点可通过 `sizing.width/height` 设置正数固定逻辑尺寸，通过 `sizing.flex`
分配主轴剩余空间。Row/Column 接管子节点的位置。隐藏节点保留布局占位，
避免认证状态切换时邻近控件跳动。固定尺寸在小容器中可能溢出，裁剪策略显式配置。

## 最小示例

```json
{
  "id": "ocean",
  "version": 2,
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

## 主题预设配置

可选的根字段 `themeProperties` 保存由主题解释的字符串配置，例如
`{"palette": "nord", "motion": "gentle"}`。支持的配置项与选项由主题声明。
场景编辑会保留这些值，代码生成也会将它们和节点一起编译到 Dart 中；它们不属于
Studio 自身的外观偏好。省略此字段时使用主题的默认配置。

## 画布（`canvas`）

| 字段 | 类型 / 可选值 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `fit` | `"cover"` \| `"contain"` \| `"reflow"` | 必填 | 画布相对屏幕视口的缩放适配策略 |
| `useSafeArea` | `boolean` | `true` | 是否在安全区域（Safe Area）内排布节点 |
| `referenceWidth` | `1..16384` | `1920` | 参考宽度（像素，供 Studio 像素模式换算使用） |
| `referenceHeight` | `1..16384` | `1080` | 参考高度（像素，供 Studio 像素模式换算使用） |

## 背景（`background`）

| 字段 | 类型 / 可选值 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `kind` | `"image"` \| `"solid"` \| `"video"` \| `"custom"` | 必填 | 背景渲染器类型 |
| `asset` | `string` | 不设置 | 打包图片或渲染配置路径（如 `packages/theme_ocean/assets/bg.jpg`） |
| `color` | `#RRGGBB` \| `#AARRGGBB` | `"#0d151a"` | 纯色填充或回退底色 |
| `scrimOpacity` | `0.0..1.0` | `0.35` | 遮罩层不透明度 |
| `blurSigma` | `>= 0` | `0` | 静态画布高斯模糊强度 |
| `rendererId` | `string` | 不设置 | 在 `ThemeBundle` 中注册的自定义渲染器标识符 |

:::caution
内置渲染器默认支持 `image` 和 `solid`。若使用 `video` 或 `custom`，需在主题的 `ThemeBundle` 中注册对应实现。资源路径不得包含 `..`。
:::

## 节点（`nodes`）

| 字段 | 类型 / 可选值 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 必填 | 唯一节点 ID |
| `component` | `string` | 必填 | 交给主题组件工厂解析的组件标识符 |
| `rect` | `{ x, y, width, height }` | 必填 | 归一化画布坐标（`x >= 0`、`y >= 0`、`width > 0`、`height > 0`，且右/下边界 `<= 1`） |
| `z` | `number` | `0` | 空间深度 |
| `renderOrder` | `integer` | `0` | 绘制顺序（与 `z` 和 `focusOrder` 相互独立） |
| `focusOrder` | `integer` | `0` | 键盘 Tab 焦点遍历顺序 |
| `motion` | `"none"` \| `"fade"` \| `"fadeSlide"` \| `"fadeScale"` \| `"hoverLift"` \| `"focusGlow"` | `"none"` | 进出场或交互动效预设 |
| `visibleWhen` | 条件对象 / 字符串 | 不设置 | 声明式显示条件（省略时始终显示） |
| `interactive` | `boolean` | `false` | 是否为可交互节点（启用最小命中热区与焦点遍历） |
| `properties` | `Record<string, string>` | `{}` | 由具体组件解析的字符串键值属性 |
| `transform` | 变换对象 | 单位变换 | 节点局部的平移、缩放、旋转与轴心 |

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
