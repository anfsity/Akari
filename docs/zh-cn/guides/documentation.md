---
title: 维护文档
description: 修改文档，在本地预览，再发布到 GitHub Pages。
---

`docs/` 目录下的 Markdown 文件是手册源文件，`docs/site/` 则管理 Astro/Starlight 配置、样式与构建脚本。

## 目录结构与多语言约定

| 目录 | 是否发布到站点 | 用途 |
| --- | --- | --- |
| `getting-started/` | 是 | 环境准备与首次预览构建 |
| `guides/` | 是 | 按任务组织的操作指南（主题、多屏、测试等） |
| `reference/` | 是 | CLI 参数、JSON 格式、D-Bus 规范与 Dart API 入口 |
| `architecture/` | 是 | 模块边界、职责划分与代码导航 |
| `internal/` | 否（仅仓库内） | 仍在开发中的内部工具文档（如 Theme Studio 说明） |
| `proposals/` | 否（仅仓库内） | 架构提案与实机验收规范 |

所有目录在 `docs/zh-cn/` 下均有路径和文件名完全一致的简体中文版本：
- 英文页面发布在站点根路径（`/Akari/`），简体中文页面发布在 `/Akari/zh-cn/`（语言标签 `zh-CN`）。
- 请在文档中使用相对 `.md` 链接，这样既能在 GitHub 上直接跳转，也能由构建插件自动解析为对应语言的网页路由。
- `docs/site/public/api/` 下生成的 Dart API 参考由中英文页面共用。

## 本地预览与构建校验

需要安装 Node.js `>= 22.12`、Python 3，以及仓库配置的 FVM Flutter/Dart 工具链。

```sh
cd docs/site
npm ci
npm run dev
```

执行完整构建（含生成 Dart API 文档、类型检查、构建静态站点与死链校验）：

```sh
npm run api
npm run check
npm run build
npm run verify
npm run preview
```

- `npm run check`：校验 Astro 配置与组件类型。
- `npm run verify`：检查生成站点中的所有本地链接、静态资源、锚点片段（`#fragment`）与四个公开包的 API 入口，并确认 `internal/` 和 `proposals/` 未被错误发布。

:::note
生成的构建目录（`docs/site/dist/`、`docs/site/public/api/` 和 `docs/site/node_modules/`）均已配置 Git 忽略，请勿提交到仓库。
:::

## 新增或更新页面

1. 在对应分类目录下新建或修改英文 Markdown 文件，并在顶部 frontmatter 中填写 `title` 与 `description`。
2. 在 `docs/zh-cn/` 下的相同相对路径同步新增或更新中文版本。
3. 若新增的是已发布页面，将其 slug 与 `translations: { 'zh-CN': '...' }` 侧边栏标题加入 `docs/site/astro.config.mjs`。
4. 修改公开 Dart API 时，应在同一提交中同步更新源码 `///` 注释与相关指南。示例代码只导入公开包入口（如 `package:theme_sdk/theme_sdk.dart`），不要导入 `lib/src/`。

## 发布到 GitHub Pages

文档站点托管于 `https://anfsity.github.io/Akari/`，使用 GitHub Actions（`.github/workflows/docs.yml`）构建并部署：

- **触发方式**：在 `main` 分支手动运行 **Documentation** 工作流，或推送/手动触发 `gh-pages` 分支上的发布工作流（会以 `source_ref: main` 调用主工作流）。
- **构建流程**：自动构建 Starlight 手册与 `dart doc` API 参考，通过 `npm run verify` 校验后，将 `docs/site/dist/` 直接作为 GitHub Pages 产物发布。
