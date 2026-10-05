---
title: 维护文档
description: 修改文档，在本地预览，再发布到 GitHub Pages。
---

## 内容与配置

`docs/` 下的 Markdown 是手册源文件。`docs/site/` 管理 Astro 配置、依赖锁文件、样式和构建命令。网站直接读取这些目录：

- `getting-started/`：安装工具并运行第一个预览。
- `guides/`：按具体任务编写的操作指南。
- `reference/`：接口、格式和命令参考。
- `architecture/`：模块关系、职责分工和设计说明。

所有已发布页面都在 `zh-cn/` 下提供对应的简体中文版本，分类和文件名保持一致。Astro 在网站根路径提供英文页面，在 `/zh-cn/` 路径下提供中文页面（语言标签为 `zh-CN`）。请使用相对 Markdown 链接，以便链接插件将目标解析到同一种语言。`docs/site/public/api/` 中生成的 API 参考仍共用一份，不单独翻译。

`internal/` 和 `proposals/` 保留为仓库文档，不加载到网站页面或搜索索引中。Studio 仍在开发时，其用户文档放在 `internal/`。

## 预览与构建

安装 Node.js 22.12 或更新版本及 Python 3。生成 API 还需要仓库指定的 Flutter/Dart 工具链。

```sh
cd docs/site
npm ci
npm run dev
```

本地网站的路径是 `/Akari/`，与 GitHub Pages 一致。先生成 API 页面，对应链接才能打开。完整构建步骤如下：

```sh
npm run api
npm run check
npm run build
npm run verify
npm run preview
```

`check` 校验 Astro 配置和组件。`verify` 检查生成手册中的本地链接、资源和片段目标，以及预期的 API 入口。依赖版本由锁文件固定；生成的 HTML 和搜索索引不提交到 Git。

## 添加页面

在对应目录中新建 Markdown 文件，在文件顶部的 frontmatter 中填写 `title` 和 `description`，再把页面路径加入 `astro.config.mjs` 的侧边栏配置。相对于仓库的 `.md` 链接在 GitHub 上仍可直接使用，并会由 Markdown 插件转换为网站路由。Mermaid 代码块会渲染为图表。

每新增一个已发布的英文页面，都要在 `docs/zh-cn/` 下的相同路径补充中文版本。侧边栏项目的 `translations` 映射使用 `zh-CN` 语言标签填写中文名称。`internal/` 和 `proposals/` 保持在内容加载器之外；它们属于仓库文档，不作为网站页面发布。

修改 API 时，要一起更新代码注释和相关指南。文档应解释怎么使用、有什么限制，以及为什么这样设计。公开 API 以导出的包入口为准；示例中不要导入 `lib/src/`。

## GitHub Pages

网站发布地址为 `https://anfsity.github.io/Akari/`。推送到 `gh-pages` 分支或手动运行工作流都会触发文档工作流。该工作流会构建手册和 Dart 参考、验证结果，然后通过 GitHub 官方部署 action 直接发布 Pages 构建产物。

GitHub Pages 将 **GitHub Actions** 设为发布来源。构建和部署逻辑位于 `main` 上的 `.github/workflows/docs.yml`。该工作流也支持传入明确 `source_ref` 的可复用调用。在 `main` 上手动运行 **Documentation** 时，会构建所选修订。main 分支推送和 pull request 不会自动启动此工作流。

`gh-pages` 分支只保留一个发布工作流和 README，不包含生成的 HTML、API 页面或搜索资源。推送该分支，或手动运行 **Publish documentation** 工作流，都会以 `source_ref: main` 调用 main 工作流，从而重新构建并部署最新的 main 源代码；它不会直接发布分支中的文件。main 和发布分支的运行共享同一个发布并发组。

分支历史保留了最初的静态快照以便恢复。之后的发布会将已验证的 `docs/site/dist/` 上传为 Pages 构建产物。不要提交 `dist/`、`public/api/` 或 `node_modules/`；源码仓库的忽略规则已排除这些目录。
