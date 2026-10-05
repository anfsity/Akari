---
title: 场景格式
description: 场景 JSON 的字段、示例和校验规则，当前版本为 2。
---

场景的数据模型和编解码器定义在 `packages/scene_schema`。构建主题时，工具先校验 JSON，再生成 Dart 代码。正式应用直接使用生成的代码，登录时无需读取场景 JSON。

## 最小文档

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

示例使用 `StandardGreeterComponents` 支持的标识符。自定义工厂可定义自己的标识符。场景至少包含一个节点；节点 ID 必须唯一，组件标识符不能为空。

## 画布

| 字段 | 可选值/默认值 | 含义 |
| --- | --- | --- |
| `fit` | `cover`、`contain`、`reflow`；必填 | 画布适配策略 |
| `useSafeArea` | `true` | 是否遵循安全区域调整后的画布 |
| `referenceWidth` | `1920` | 参考宽度（像素）；1–16384 |
| `referenceHeight` | `1080` | 参考高度（像素）；1–16384 |

布局位置和尺寸按画布比例填写。例如，宽度 `0.5` 表示画布可用宽度的一半。

## 背景

| 字段 | 默认值 | 含义 |
| --- | --- | --- |
| `kind` | 必填 | `image`、`solid`、`video` 或 `custom` |
| `asset` | 不设置 | 打包图像或渲染器配置引用 |
| `color` | `#0d151a` | 背景填充色 |
| `scrimOpacity` | `0.35` | 遮罩不透明度，范围 [0, 1] |
| `blurSigma` | `0` | 非负的模糊强度 |
| `rendererId` | 不设置 | 可选自定义渲染器标识符 |

内置渲染器实现 `image` 和 `solid`。其他类型需要由编译进主题的实现注册。资源引用不得包含 `..`；图像资源使用 `assets/` 或 Flutter `packages/` 路径。主题自有资源通常使用 `packages/<package-name>/assets/...`。

颜色接受六位 RGB 或八位 ARGB 十六进制字符串，通常写作 `#RRGGBB` 或 `#AARRGGBB`。

## 节点

| 字段 | 默认值 | 含义 |
| --- | --- | --- |
| `id` | 必填 | 唯一节点标识符 |
| `component` | 必填 | 由主题组件工厂处理的标识符 |
| `rect` | 必填 | 归一化的 `x`、`y`、`width` 和 `height` |
| `z` | `0` | 空间深度 |
| `renderOrder` | `0` | 绘制顺序 |
| `focusOrder` | `0` | 键盘遍历顺序 |
| `motion` | `none` | 动效预设 |
| `visibleWhen` | 不设置 | 控制节点何时显示的条件 |
| `interactive` | `false` | 节点是否可交互 |
| `properties` | `{}` | 由组件解释的字符串键值配置 |
| `transform` | 单位变换 | 节点局部的平移、缩放、旋转和轴心 |

矩形的 X/Y 必须非负，宽和高必须为正，右边和下边不能超出 1。深度、绘制顺序和键盘顺序含义不同；不要根据其中一个推断另一个。

动效名称为 `none`、`fade`、`fadeSlide`、`fadeScale`、`hoverLift` 和 `focusGlow`。主题注册 builder 和视觉时间参数；运行时负责动画生命周期。

<a id="transforms"></a>

## 变换

| 字段 | 单位/默认值 |
| --- | --- |
| `translateX`、`translateY` | 逻辑像素；0 |
| `scaleX`、`scaleY` | 倍率；1 |
| `rotationX`、`rotationY`、`rotationZ` | 度；0 |
| `pivotX`、`pivotY` | 相对布局节点尺寸的比例；0.5 |
| `perspective` | 矩阵透视系数；0 |

变换字段使用上表中的单位；节点矩形的位置和尺寸仍按画布比例填写。

## 显示条件

谓词名称本身就是一个条件；可使用 `all`、`any` 或 `not` 组合。每个条件对象只能包含一个运算符，`all` 和 `any` 接受非空条件列表。

```json
{
  "all": [
    { "not": "isDormant" },
    { "any": ["isAuthPrompting", "isAuthError"] }
  ]
}
```

[API 参考](api.md)中的 `ScenePredicate` 枚举列出完整谓词。条件不会执行任意表达式或脚本。登录适配器会将语义状态投影为谓词；主题不会根据后端传输对象推导条件。

休眠状态不会结束身份验证提示，因此身份验证谓词和 `isDormant` 可能同时生效。如果登录控件需要在按下 Escape 后隐藏，请添加 `{ "not": "isDormant" }`。默认主题的确认箭头在提示、提交和身份验证错误状态下都使用这个显示条件。

## 版本

当前版本为 2。解码器也接受版本 1，并会将旧版 `kind` 和 `action` 词汇规范化为当前组件/交互模型。编码始终写入当前文档格式。新文档请使用版本 2。
