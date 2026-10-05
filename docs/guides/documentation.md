---
title: Maintain the documentation
description: Preview, verify, and publish the Starlight handbook and API reference.
---

## Content and configuration

Markdown under `docs/` is the handbook's source. `docs/site/` owns the Astro
configuration, dependency lockfile, styles, and build commands. The content
loader reads these categories directly:

- `getting-started/`: environment setup and the first successful run.
- `guides/`: task-oriented workflows.
- `reference/`: exact external contracts and lookup pages.
- `architecture/`: module relationships, ownership, and design reasoning.

Published pages have a Simplified Chinese counterpart under `zh-cn/`, using the
same category and filename. Astro serves English at the site root and Chinese
under `/zh-cn/` (`zh-CN`). Keep Markdown links relative so the link plugin
resolves each page within its own locale. The generated API under
`docs/site/public/api/` remains a shared, untranslated reference.

`internal/` and `proposals/` remain repository documents. They are excluded from
the site's loader, page generation, and search index. Studio user documentation
stays in `internal/` while the editor is in development.

## Preview and build

Install Node.js 22.12 or newer and Python 3. API generation also needs the
repository's Flutter/Dart toolchain.

```sh
cd docs/site
npm ci
npm run dev
```

The local handbook is served under `/Akari/`, matching GitHub Pages. The API
links become available after generation. For a complete build:

```sh
npm run api
npm run check
npm run build
npm run verify
npm run preview
```

`check` validates the Astro configuration and components. `verify` checks local
links, assets, and fragment targets in the generated handbook, plus the expected
API entrypoints. Dependencies are locked; generated HTML and search indexes are
not committed.

## Add a page

Add a Markdown file to the appropriate category with `title` and `description`
frontmatter. Add its slug to the explicit sidebar in `astro.config.mjs`.
Repository-relative `.md` links remain readable on GitHub and are converted to
website routes by the Markdown plugin. Mermaid fences render as diagrams.

For every published English page, add a translation at the matching path below
`docs/zh-cn/`. Translate the sidebar label in the item's `translations` map using
the `zh-CN` language tag. Keep `internal/` and `proposals/` outside the loader;
they are repository documents rather than published pages.

When changing an API contract, update its source comment and relevant guide in
the same change. Explain constraints and reasons rather than narrating the code.
The public API follows the exported package entrypoints; avoid importing `lib/src/`
from examples.

## GitHub Pages

The website is hosted at `https://anfsity.github.io/Akari/`. Pushes to `gh-pages`
or manual workflow runs trigger the documentation workflow.
The workflow builds the handbook and Dart reference, verifies the output, and
deploys a Pages artifact directly using GitHub's official deployment actions.

GitHub Pages uses **GitHub Actions** as its publishing source. The build and
deployment implementation lives in `.github/workflows/docs.yml` on `main`.
It also accepts reusable workflow calls with an explicit `source_ref`.
Manual **Documentation** runs on `main` build their selected revision.
Main-branch pushes and pull requests do not automatically start this workflow.

The `gh-pages` branch contains a small publication workflow and a README,
without generated HTML, API pages, or search assets. Pushing that branch or
running its **Publish documentation** workflow manually calls the main workflow
with `source_ref: main`, rebuilding and deploying the latest main source. It
does not publish files directly from the branch. Main and publication-branch
runs share one publication concurrency group.

The initial static snapshot remains in the branch's history for recovery.
Subsequent publications upload the verified `docs/site/dist/` directory as a
Pages artifact. Keep `dist/`, `public/api/`, and `node_modules/` out of commits;
the source checkout's ignore rules already exclude them.
