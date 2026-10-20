---
title: Maintain the documentation
description: Preview, verify, and publish the Starlight handbook and API reference.
---

Markdown files under `docs/` are the source for the Akari handbook, while `docs/site/` owns the Astro/Starlight configuration, styles, and build scripts.

## Directory layout & locales

| Directory | Published to site? | Purpose |
| --- | --- | --- |
| `getting-started/` | Yes | Toolchain setup and first successful run |
| `guides/` | Yes | Task-oriented workflows for themes, displays, and testing |
| `reference/` | Yes | CLI options, JSON schemas, D-Bus specs, and Dart API links |
| `architecture/` | Yes | Module ownership, runtime boundaries, and code navigation |
| `internal/` | No (repo only) | In-progress tool documentation (such as Theme Studio notes) |
| `proposals/` | No (repo only) | Design proposals and hardware validation specs |

Every directory has a Simplified Chinese counterpart under `docs/zh-cn/` with matching filenames:
- Astro serves English at the site root (`/Akari/`) and Simplified Chinese under `/Akari/zh-cn/` (`zh-CN`).
- Use relative `.md` links in Markdown so links work both in GitHub and in localized site routes.
- Generated Dart API docs under `docs/site/public/api/` are shared across locales.

## Preview and verify locally

Requires Node.js `>= 22.12`, Python 3, and the repository's FVM Flutter/Dart toolchain.

```sh
cd docs/site
npm ci
npm run dev
```

To build the Dart API reference, compile the static site, and run link/fragment verification:

```sh
npm run api
npm run check
npm run build
npm run verify
npm run preview
```

- `npm run check`: Validates Astro configuration and component types.
- `npm run verify`: Checks all local links, assets, anchor fragments, API entrypoints, and ensures `internal/` and `proposals/` are excluded from the published bundle.

:::note
Generated directories (`docs/site/dist/`, `docs/site/public/api/`, and `docs/site/node_modules/`) are git-ignored and must never be committed.
:::

## Add or update a page

1. Create or edit the English Markdown file with `title` and `description` frontmatter.
2. Add or update the corresponding Simplified Chinese page under `docs/zh-cn/`.
3. If adding a new published page, register its slug and `translations: { 'zh-CN': '...' }` label in `docs/site/astro.config.mjs`.
4. When changing a public Dart API contract, update its `///` doc comment and relevant guide in the same commit. Always import package entrypoints (`package:theme_sdk/theme_sdk.dart`) in examples rather than `lib/src/`.

## GitHub Pages deployment

The handbook is published to `https://anfsity.github.io/Akari/` via GitHub Actions (`.github/workflows/docs.yml`):

- **Triggers**: Manual **Documentation** workflow dispatch on `main`, or pushing/dispatching on the `gh-pages` branch (which invokes the `main` workflow with `source_ref: main`).
- **Pipeline**: Builds the Starlight site and `dart doc` reference, runs `npm run verify`, and uploads `docs/site/dist/` directly as a GitHub Pages artifact.
