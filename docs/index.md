---
title: Mozais
description: Compile-time Flutter themes for a Linux greeter.
template: splash
hero:
  tagline: A Linux greeter with a theme you own. Compose Flutter components, author scenes, and build one native executable.
  actions:
    - text: Start here
      link: /Mozais/getting-started/quick-start/
      icon: right-arrow
    - text: Develop a theme
      link: /Mozais/guides/themes/
      variant: minimal
---

## Choose your path

| Goal | Read |
| --- | --- |
| Prepare a development machine | [Environment setup](getting-started/installation.md) |
| Preview the existing themes | [Quick start](getting-started/quick-start.md) |
| Create your own theme | [Theme development](guides/themes.md) |
| Check several displays or standalone scale | [Display testing](guides/display-testing.md) |
| Look up types and methods | [API reference](reference/api.md) |
| Understand the implementation | [Code map](architecture/code-map.md) |

## How Mozais fits together

The Flutter frontend owns presentation and interaction. A Rust bridge owns the
greetd/PAM conversation and system operations. A theme receives typed display
state and semantic actions through the Theme SDK, without owning authentication.

Scenes describe layout, visibility, and motion. The build generates Dart from
scene JSON and compiles the selected theme and its assets into the executable.

These docs follow the code in the repository. Start with a desktop preview or
the mock backend; the [standalone greetd harness](guides/greetd-testing.md) is a
separate development testing workflow.
