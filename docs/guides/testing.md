---
title: Develop and test
description: Choose unit, mock integration, compositor, and performance checks.
---

## Repository verification

```sh
fvm dart run tool/mozais.dart verify
fvm dart run tool/mozais.dart verify --theme themes/fallback
```

Verification checks shared code and the Rust backend, and runs tests for
discovered theme projects. Selecting a theme narrows theme checks while retaining
the shared checks. Themes own their UI tests; runtime and schema packages own
their contracts.

Test behavior that matters: scene validation, state transitions, attempt isolation,
slot notifications, focus and keyboard interaction, resource lifetime, and
performance. Avoid tests that encode exact visual placement.

## Mock integration

```sh
fvm dart run tool/mozais.dart run --theme themes/fallback
```

Use this for the complete frontend/D-Bus path without system PAM calls. Use
`preview` when only the theme's rendering and local behavior matter.

## Compositor and real login

```sh
fvm dart run tool/mozais.dart run sway --display-profile reference
fvm dart run tool/mozais.dart run sway --display-profile reference --sway-backend headless
```

The nested/headless session owns a private backend, bus, compositor, and frontend.
The [CLI reference](../reference/cli.md) explains scale compensation, login display
profiles, retained screenshots, and native regression commands.

Real greetd testing is a separate [standalone workflow](greetd-testing.md), with
its own installation, TTY preflight, and recovery lifecycle.

## Performance

```sh
fvm dart run tool/mozais.dart verify-perf --theme themes/default
fvm dart run tool/mozais.dart trace-perf --theme themes/default
```

Themes opt into these commands through their own manifest. Their runner owns
interaction journeys, metrics, thresholds, and artifact formats. The fallback
theme has no performance runner. See the
[performance protocol](../reference/theme-package.md#performance-protocol).

## Diagnose a failed command

Use `--format json` or `--report PATH` for structured reports. Development runs
retain a report, event log, and child-process logs beneath `build/tool/runs/`.
Start with the failed step's stderr log. Standalone greetd diagnostics use the
separate paths described in that guide.
