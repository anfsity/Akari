---
title: 维护文档
description: 预览、验证并发布 Starlight 手册和 API 参考。
---

## 内容与配置

`docs/` 下的 Markdown 是手册源文件。`docs/site/` 管理 Astro 配置、依赖锁文件、样式和构建命令。内容加载器直接读取以下类别：

- `getting-started/`：环境配置和首次成功运行。
- `guides/`：按任务组织的工作流。
- `reference/`：外部约定和查询页面。
- `architecture/`：模块关系、所有权和设计说明。

所有已发布页面都在 `zh-cn/` 下提供对应的简体中文版本，分类和文件名保持一致。Astro 在网站根路径提供英文页面，在 `/zh-cn/` 路径下提供中文页面（语言标签为 `zh-CN`）。请使用相对 Markdown 链接，以便链接插件将目标解析到同一种语言。`docs/site/public/api/` 中生成的 API 参考仍共用一份，不单独翻译。

`internal/` 和 `proposals/` 保留为仓库文档，不加载到网站页面或搜索索引中。Studio 仍在开发时，其用户文档放在 `internal/`。

## 预览与构建

安装 Node.js 22.12 或更新版本及 Python 3。生成 API 还需要仓库指定的 Flutter/Dart 工具链。

```sh
cd docs/site
npm ci
npm run dev
```

本地手册挂载在 `/Akari/` 下，与 GitHub Pages 一致。API 页面需生成后链接才可用。完整构建流程如下：

```sh
npm run api
npm run check
npm run build
npm run verify
npm run preview
```

`check` 校验 Astro 配置和组件。`verify` 检查生成手册中的本地链接、资源和片段目标，以及预期的 API 入口。依赖版本由锁文件固定；生成的 HTML 和搜索索引不提交到 Git。

## 添加页面

在对应类别中新增 Markdown 文件，并设置 `title` 和 `description` frontmatter。然后在 `astro.config.mjs` 的显式侧边栏中加入其 slug。相对于仓库的 `.md` 链接在 GitHub 上仍可直接使用，并会由 Markdown 插件转换为网站路由。Mermaid 代码块会渲染为图表。

每新增一个已发布的英文页面，都要在 `docs/zh-cn/` 下的相同路径补充中文版本。侧边栏项目的 `translations` 映射使用 `zh-CN` 语言标签填写中文名称。`internal/` 和 `proposals/` 保持在内容加载器之外；它们属于仓库文档，不作为网站页面发布。

更改 API 约定时，请在同一改动中更新源代码注释和相关指南。应说明限制和原因，而不是逐行描述代码。公开 API 以导出的 package 入口为准；示例中不要导入 `lib/src/`。

## GitHub Pages

网站发布地址为 `https://anfsity.github.io/Akari/`。推送到 `gh-pages` 分支或手动运行工作流都会触发文档工作流。该工作流会构建手册和 Dart 参考、验证结果，然后通过 GitHub 官方部署 action 直接发布 Pages 构建产物。

GitHub Pages 将 **GitHub Actions** 设为发布来源。构建和部署逻辑位于 `main` 上的 `.github/workflows/docs.yml`。该工作流也支持传入明确 `source_ref` 的可复用调用。在 `main` 上手动运行 **Documentation** 时，会构建所选修订。main 分支推送和 pull request 不会自动启动此工作流。

`gh-pages` 分支只保留一个发布工作流和 README，不包含生成的 HTML、API 页面或搜索资源。推送该分支，或手动运行 **Publish documentation** 工作流，都会以 `source_ref: main` 调用 main 工作流，从而重新构建并部署最新的 main 源代码；它不会直接发布分支中的文件。main 和发布分支的运行共享同一个发布并发组。

分支历史保留了最初的静态快照以便恢复。之后的发布会将已验证的 `docs/site/dist/` 上传为 Pages 构建产物。不要提交 `dist/`、`public/api/` 或 `node_modules/`；源码 checkout 的忽略规则已排除这些目录。
