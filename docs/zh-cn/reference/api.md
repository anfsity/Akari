---
title: API 参考
description: 查阅 Theme SDK、场景运行时和组件的 Dart API。
---

Dart API 参考文档由源码中的 `///` 文档注释自动生成，版本与当前手册保持同步。

## 公开包一览

| 包名 | API 文档链接 | 职责范围 |
| --- | --- | --- |
| `theme_sdk` | [浏览 API](/Akari/api/dart/theme_sdk/index.html) | `ThemeDefinition`、`GreeterHost`、状态插槽（Slots）与组件工厂接口 |
| `scene` | [浏览 API](/Akari/api/dart/scene/index.html) | `SceneRuntime`、`ThemeTokens`、背景渲染器与动效构建器 |
| `scene_schema` | [浏览 API](/Akari/api/dart/scene_schema/index.html) | `SceneDocument`、`ScenePredicate`、校验规则与 JSON 编解码器 |
| `greeter_components` | [浏览 API](/Akari/api/dart/greeter_components/index.html) | 可选的标准登录组件集（`StandardGreeterComponents`） |

关于具体用法与状态边界，请参阅[开发主题组件](../guides/components.md)和[代码导航](../architecture/code-map.md)。

## 注释编写约定

- 在公开符号的 `///` 注释中明确说明参数约束、返回值语义、资源生命周期归属以及简短示例。
- 跨模块流程与操作步骤写在手册指南中，并通过链接指向本 API 参考，避免在文档中手工维护重复的方法列表。

## 在本地生成 API 文档

```sh
cd docs/site
npm run api
```

`npm run api` 会使用仓库配置的 FVM SDK（或 `AKARI_FLUTTER_BIN` / `AKARI_DART_BIN` 覆盖路径）解析依赖、运行静态分析，并通过 `dart doc` 将静态页面输出到 `docs/site/public/api/dart/`（该目录已配置 Git 忽略）。

:::tip
如需在本地生成 Rust 后端的代码文档，请参阅[后端代码指南](../architecture/backend.md#本地代码参考)。
:::
