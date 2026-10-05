---
title: API 参考
description: 公开主题和场景 package 的 Dart 生成参考。
---

这些页面与手册使用同一修订的源代码及文档注释生成。请从负责当前任务的 package 开始：

| Package | 参考 | 职责 |
| --- | --- | --- |
| `theme_sdk` | [浏览 API](/Akari/api/dart/theme_sdk/index.html) | 主题定义、语义宿主、插槽和组件工厂 |
| `scene` | [浏览 API](/Akari/api/dart/scene/index.html) | 运行时、视觉 token、渲染器和动效 |
| `scene_schema` | [浏览 API](/Akari/api/dart/scene_schema/index.html) | 文档模型、条件、校验和 JSON 编解码器 |
| `greeter_components` | [浏览 API](/Akari/api/dart/greeter_components/index.html) | 可选的标准视觉组件集 |

生成的参考页面有自己的导航和符号搜索。组件示例见[组件指南](../guides/components.md)，跨模块关系见[代码导航](../architecture/code-map.md)。

## 文档归属

在公开声明旁边的 `///` 注释中说明参数约定、返回语义、资源所有权和简短示例。仅生成的函数签名无法解释约定。手写指南用于说明工作流，并链接到此参考，而不是复制类型或成员目录。

## 本地生成

```sh
cd docs/site
npm run api
```

此命令会解析所选 package 的依赖、运行分析器，并使用 `dart doc` 生成静态 HTML。它使用仓库的 FVM SDK，或显式指定的 `AKARI_FLUTTER_BIN` 和 `AKARI_DART_BIN` 路径。输出位于 `docs/site/public/api/dart/`，并已被 Git 忽略。

后端代码参考可单独使用 rustdoc 生成，详情见[后端代码指南](../architecture/backend.md)。
