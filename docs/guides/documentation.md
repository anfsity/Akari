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

The local handbook is served under `/Mozais/`, matching GitHub Pages. The API
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

When changing an API contract, update its source comment and relevant guide in
the same change. Explain constraints and reasons rather than narrating the code.
The public API follows the exported package entrypoints; avoid importing `lib/src/`
from examples.

## GitHub Pages

The website is hosted at `https://anfsity.github.io/Mozais/`. Main-branch pushes
that change documentation or API source trigger the documentation workflow.
The workflow builds the handbook and Dart reference, verifies the output, and
publishes generated files to the dedicated `gh-pages` branch.

GitHub Pages uses `gh-pages` at `/` as its publishing source. This also allows
a first publication of a locally verified build without pushing unfinished
development history. Later main-branch builds update the same branch.
