---
title: API 参考
description: 查阅 Theme SDK、场景运行时和组件的 Dart API。
---

API 页面根据与手册相同版本的代码和注释生成。按需要查看对应的包：

| 包 | 参考 | 职责 |
| --- | --- | --- |
| `theme_sdk` | [浏览 API](/Akari/api/dart/theme_sdk/index.html) | 主题定义、登录宿主、插槽和组件工厂 |
| `scene` | [浏览 API](/Akari/api/dart/scene/index.html) | 运行时、样式参数、渲染器和动效 |
| `scene_schema` | [浏览 API](/Akari/api/dart/scene_schema/index.html) | 文档模型、条件、校验和 JSON 编解码器 |
| `greeter_components` | [浏览 API](/Akari/api/dart/greeter_components/index.html) | 可选的标准视觉组件集 |

生成的参考页面有自己的导航和符号搜索。组件示例见[组件指南](../guides/components.md)，跨模块关系见[代码导航](../architecture/code-map.md)。

## API 注释怎么写

在公开声明的 `///` 注释中说明参数含义、返回值、资源由谁管理，并提供简短示例。函数签名只能列出类型，无法解释使用规则。操作步骤和跨模块流程写在指南里，再链接到 API 页面。

## 本地生成

```sh
cd docs/site
npm run api
```

此命令会解析选定的包的依赖、运行分析器，并使用 `dart doc` 生成静态 HTML。它使用仓库的 FVM SDK，或指定的 `AKARI_FLUTTER_BIN` 和 `AKARI_DART_BIN` 路径。输出位于 `docs/site/public/api/dart/`，并已被 Git 忽略。

后端代码参考可单独使用 rustdoc 生成，详情见[后端代码指南](../architecture/backend.md)。
