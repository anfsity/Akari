---
title: 前端架构
---

## 1. 目标

本文定义 Akari 登录界面的前端边界。身份验证协议仍由 Rust 后端和 D-Bus 接口约定负责；Flutter 前端负责呈现、输入和本地交互状态。

前端由四个协作部分组成：

```text
Feature
  业务状态、类型化插槽、命令、恢复流程、D-Bus 端口
        |
        v
GreeterSceneAdapter
  将语义状态映射为场景谓词和 UI 操作
        |
        v
ThemeDefinition
  主题标识、创作场景、组件组装
        |
        v
ThemeBundle
  视觉 token、背景渲染器、动效预设
        |
        v
SceneRuntime
  文档布局、图层、变换、动效生命周期
```

`Feature` 不感知主题、背景渲染器、模糊、动效预设或显示几何。`Theme` 不管理身份验证或 D-Bus 行为。`SceneRuntime` 不会直接访问后端。

## 2. 运行时边界

完整运行时的结构如下：

```text
Flutter Feature
    |
    | 私有/会话 D-Bus
    v
Rust 后端桥接层
    |                         \
    | greetd Unix socket       \ system D-Bus
    v                           v
greetd / PAM                systemd-logind
```

后端负责 greetd、PAM、会话校验、 电源操作、尝试序号和过期事件防护。Flutter 发送类型化命令，并接收适合显示的类型化 slot。

密钥、OTP 值、PAM 帧和后端传输对象不得进入 `SceneDocument`、`ThemeBundle`、视觉上下文或日志。

## 3. 主题与场景文档

主题是一个独立 Dart package。内置项目位于 `themes/`；CLI 也可以构建仓库外的项目。项目包含：

- `*.scene.json`：创作布局和可见性条件。
- 生成的 `*.scene.g.dart`：由 build_runner 输出的类型化 Dart 代码。
- `theme.dart`：编译期组装 token 和主题自有组件。
- `assets/`：package 自有图片及其他打包资源。

创作文档带有版本号，结构如下：

```text
SceneDocument
  id
  version
  canvas: 适配方式、安全区域策略
  background: 渲染器类型及可信资源/配置引用
  nodes[]

SceneNode
  id
  componentId
  归一化矩形
  transform: 平移、缩放、旋转、轴心
  z
  renderOrder
  focusOrder
  动效预设
  visibleWhen: 对语义谓词求值的布尔条件
  interactive
  properties
```

`z` 表示空间深度，`renderOrder` 表示绘制顺序，`focusOrder` 表示键盘遍历顺序。它们是不同字段，不得根据 widget 插入顺序推断。

`visibleWhen` 是一种简单布尔条件（`all`、`any`、`not`），其输入来自封闭的语义谓词集合，例如 `isDormant` 或 `isAuthPrompting`。条件为 null 表示节点始终存在。谓词是对登录语义状态的枚举；场景约定不包括任意表达式、脚本、运行时加载的 Dart、后端类型或不可信资源路径。仓库资源使用 `assets/...`；主题 Flutter package 自有资源使用 `packages/<package>/assets/...`。

生产代码使用生成的 Dart。应用路径不会解析运行时 JSON。

场景代码分层后，工具可以复用 schema 而无需引入 Flutter：

```text
packages/scene_schema   不依赖 Flutter 的模型、条件求值器、JSON 编解码器
packages/scene          运行时、主题 bundle、背景与动效注册表
packages/scene_codegen  build_runner 生成器：解码 JSON 并生成 Dart
packages/greeter_components 可选的可复用语义组件集
```

`scene` 会重新导出 schema，因此应用代码只需一次导入。场景构建工具使用 schema 的编解码器和校验逻辑，作为解析场景文档的权威实现。

## 4. ThemeDefinition 与主题选择

`ThemeDefinition` 是主题 package 中一个主题的所有者，负责主题标识、生成的场景文档、组件组装和视觉运行时 bundle：

```text
ThemeDefinition
  id
  SceneDocument
  GreeterThemeComponents factory
  ThemeBundle
    ThemeTokens
    BackgroundRenderer registry
    SceneMotionBuilder registry
```

`ThemeBundle` 只包含视觉 token 和渲染器注册。主题定义公开 `buildScene`，将该主题的创作文档、视觉 bundle 和组件工厂组合为通用的 `SceneRuntime`。登录适配器提供语义状态、宿主能力和唤醒进度，但不负责组装场景运行时。每个主题都会同时声明自己的组件工厂与场景。当行为和呈现相同时，主题可以明确复用现有组件实现；当前 fallback 主题就是如此。

可复用语义 API 位于 `theme_sdk`。它通过 `GreeterHost` 暴露适合显示的 slot listenable 和语义回调，但不会让主题访问 Feature 状态所有者、D-Bus 或后端对象。登录适配器将该 Host API 提供给编译后选中的主题。

应用宿主接收 `ThemeBuilder`，而不自行选择主题。可执行文件入口选择 builder；宿主会初始化主题，并在有背景 seed 时用采样结果重新构建主题。背景 seed 提取属于 `ThemeDefinition`，因此不需要主题 catalog。

CLI 使用 `--theme PATH` 选择一个项目，并生成单独的宿主，直接导入其 builder 并注入 `MyApp`。主题发现根据项目元数据运行，不依赖固定主题名称。仓库测试直接注入 builder；`tool/dev_main.dart` 在调试时显式选择默认主题。fallback 主题是可独立选择的精简静态主题，没有模糊或持续动画。

`preview --theme PATH` 会为同一宿主提供演示登录状态并启动它。每个主题项目管理自己的场景、组件组装、token 和资源。主题可以依赖 SDK 或明确共享的组件 package，但不能导入另一个主题 package。主题 Dart/Flutter 代码会编译进应用；不支持运行时加载新的 Dart 或 Flutter 代码。

## 5. SceneRuntime

`SceneRuntime` 负责：

- 归一化布局转换和安全区域处理。
- 图层排序和 2.5D 变换。
- 焦点顺序元数据。
- 背景渲染器选择及回退。
- 动效组件生命周期，包括进入和退出过渡。
- 为每个场景节点设置一个重绘边界，使创作的视觉组件能够独立于场景其他部分绘制。

主题组件通过 `SceneRegion` 或本地 `ListenableBuilder` 订阅负责其内容的类型化 slot。`ValueListenableBuilder` 限制需要重建的组件子树；节点 `RepaintBoundary` 限制需要重绘的场景节点。场景谓词通知由各节点宿主处理，因此可见性变化不会重建整个场景树。

一个场景节点中的 widget 共用该节点的绘制边界。只有性能分析显示复杂子组件需要独立重绘时，才添加嵌套边界。

节点的 `visibleWhen` 变为 false 时，会一直保持挂载，直至退出过渡结束，随后卸载；因此时钟计时器等有状态内容也会停止。正在退出的节点不接收指针或焦点输入。

可交互节点可以使用变换，但运行时仍会强制以下约束：

- 命中目标最小尺寸。
- 安全区域回退。
- 确定性的键盘遍历。

节点可以使用支持的完整变换范围。完整 3D 网格、光照和任意相机不在范围内。

## 6. 背景与动效

背景渲染器是编译期实现：

```text
image    带明确裁剪和遮罩策略的打包图像
solid    确定性的回退方案
video    未来可遵循相同约定扩展
custom   未来由主题注册的编译期渲染器
```

首个实现提供 `image` 和 `solid`。在有实际实现前，video 和 custom 只作为扩展点。

动效由主题选择、运行时执行。主题声明 `none`、`fade`、`fadeSlide`、`fadeScale`、`hoverLift` 和 `focusGlow` 等预设。每个 `SceneMotionBuilder` 用外部驱动的 `Animation<double>` 包装子组件，不拥有控制器。运行时组件拥有控制器、中断处理、减少动效支持和资源释放，并在节点挂载时正向驱动同一个动画、退出时反向驱动。动效组件只作用于自己的节点；不允许使用全局 `AnimatedSwitcher` 或全屏动画遮罩。

模糊是一种静态背景处理或局部表面效果。背景可以声明 `blurSigma`，令整个画布仅模糊一次，并与背景重绘边界一起缓存。玻璃面板可以使用范围受限的 `BackdropFilter`；低功耗或减少动效模式下会回退到半透明纯色。全屏动态模糊不在支持范围内。

## 7. 登录适配器与 Slot

`GreeterFeature` 暴露类型化区域 slot 和命令。`GreeterSceneAdapter` 将显示状态映射为场景谓词，创建精简的 `GreeterHost`，并让所选 `ThemeDefinition` 构建场景。主题组件无法访问 `GreeterFeature` 状态所有者。主题组件集会将场景节点映射到普通 Flutter widget，并保留原生输入、焦点、键盘和无障碍行为。

Feature 投影不包含 `BackgroundSlots`。需要视觉氛围时，由适配器或主题自行推导。凭据响应会保留在应用共享的文本控制器中，直到作为命令发送。

Linux runner 会在单个 engine 中为每台显示器创建一个全屏 `FlView`。`MyApp` 通过 `ViewAnchor` 和 `ViewCollection` 渲染同级视图，让它们共享一个 `GreeterFeature` 和凭据控制器。每个适配器管理各自显示器的焦点节点和动画；只有当前激活的显示器处理全局键盘输入。GTK 通过 `akari/displays` 上报原生视图焦点，避免在窗口间切换时重复提交响应，或让非活动显示器抢占凭据焦点。隐式视图拥有应用根节点；显示器移除时，它会转移到剩余输出上，或保持隐藏直至输出重新连接。由于 Studio 是单视图应用，它会请求 `AKARI_DISPLAY_MODE=single`。

改变焦点或附加视图不会创建新的 Feature 或后端对话。账户、会话、身份验证、休眠状态和凭据文本与应用同生命周期；焦点和唤醒动画与各自适配器同生命周期。多显示器 Flutter 测试检查共享状态及单次响应分发；[原生显示检查](../guides/testing.md#native-display-regressions)则检查 GTK 视图和显示器生命周期。

按 Escape 回到休眠背景时，会保留身份验证尝试及其提示。唤醒后继续同一对话。隐藏时适配器会清除本地凭据文本，唤醒后恢复焦点；它不会提交或取消提示。显式取消和客户端断开仍会释放后端事务，因此 UI 可见性变化不会被计作 PAM 登录失败。

## 8. 测试策略

测试优先覆盖逻辑、交互和性能，而不是视觉布局。

单元测试覆盖：

- Feature reducer、命令、恢复、尝试隔离和密钥处理。
- 场景文档校验、主题选择、注册回退和生成代码约定。

交互测试覆盖：

- 账户和会话选择。
- 根据上下文变化的箭头操作。
- 提示焦点、响应提交、取消、重试和电源操作。
- 键盘遍历及语义可访问性。

运行时测试覆盖：

- 安全区域回退、绘制/焦点顺序、减少动效和背景失败回退。

测试不得断言像素坐标或精确视觉位置。少量可用性不变量可以检查可达性、焦点顺序、命中区域尺寸和内容不溢出。

每个主题拥有自己的性能测试和阈值。CLI 会通过[主题性能协议](../reference/theme-package.md#performance-protocol)运行声明的命令。默认主题通过 Linux/Wayland profile 集成运行验证性能。报告按交互阶段记录构建、光栅、vsync 开销和总帧时间的 p50/p95 与最大值，统计超过 16.67 ms 预算的帧，验证阶段匹配和样本是否充足，并检查静止的背景在稳定后是否仍重复安排平台唤醒。以下结果会使检查失败：阶段匹配样本少于 5 个；未匹配帧超过 20%；报告测量周期少于 3 次；任一交互阶段或汇总阶段的 p95 总跨度超过两个 16.67 ms 帧预算；构建或光栅 p50/p95 相对基线回归超过 20%；或者多数独立周期中超过 20% 的交互帧超出 16.67 ms 预算。

每次交互还会单独记录首个响应帧及后续动画帧。每个测量周期中，UI 线程的构建/布局/绘制工作都必须低于 5 ms；光栅、vsync 调度和正常过渡仍由上述帧指标覆盖。

运行 `fvm dart run tool/akari.dart trace-perf` 可在单独的 profile 运行中采集 widget 构建、布局和绘制事件；这些耗时只用于诊断，不参与性能门槛。设置 `AKARI_FLUTTER_BIN` 可指定 Flutter SDK；对应的 Dart 二进制取自同一个 SDK 目录。
