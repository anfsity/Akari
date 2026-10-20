---
title: Develop and test
description: Choose unit, mock integration, compositor, and performance checks.
---

Akari separates fast repository verification from live compositor, multi-monitor, and hardware login tests.

## Repository verification

Run static analysis, Rust checks, and unit/widget test suites across shared packages and themes:

```sh
# Check the entire repository and all built-in themes
fvm dart run tool/akari.dart verify

# Scope theme checks to a single theme while keeping shared + backend checks
fvm dart run tool/akari.dart verify --theme themes/fallback
```

What to focus on when writing tests:
- **Test behavior and invariants**: Scene validation, state transitions, attempt isolation, slot notifications, focus/keyboard traversal, resource disposal, and frame budgets.
- **Avoid brittle layout assertions**: Do not assert hardcoded pixel coordinates; check reachability, minimum hit target sizes, focus order, and absence of overflow instead.

:::note
`test/login_cli_test.dart` also invokes `test/support/login_workflow_test.py` to test deployment, rollback, and recovery in simulated systemd environments without touching your host display manager.
:::

## Mock D-Bus & UI walkthroughs

| Workflow | Command | When to use |
| --- | --- | --- |
| Automated UI walkthrough | `fvm dart run tool/akari.dart preview --theme themes/fallback` | Run `face-success` and `password-fallback` journeys in one window and exit |
| Interactive mock session | `fvm dart run tool/akari.dart run --theme themes/fallback` | Exercise the full Flutter + D-Bus + Rust mock backend path with hot reload |
| Nested or headless Sway | `fvm dart run tool/akari.dart run sway --display-profile reference` | Test compositor scaling and fixed-resolution screenshots ([guide](display-testing.md)) |
| Real TTY login | `akari greetd-test ...` | Test actual PAM, DRM/KMS splash, and session launch ([guide](greetd-testing.md)) |

## Native display regressions

Opt-in Python regression suites launch real Flutter windows inside isolated headless Sway compositors. They require `sway`, `swaymsg`, `grim`, and `wtype`.

### Multi-monitor & hotplug regression

Build a demo bundle from `tool/dev_main.dart` (do not use `preview` binaries, which exit after their test journey) and run the workflow script:

```sh
fvm dart run tool/akari.dart generate-scenes --theme themes/default
fvm flutter build linux --release --target tool/dev_main.dart --dart-define=AKARI_BACKEND=demo
python3 test/support/multi_display_workflow_test.py \
  --app build/linux/x64/release/bundle/greeter
```

This verifies mixed DPI scales, pointer focus switching across views, monitor hotplug (including removing all monitors and reconnecting), and single-window mode.

### Nested scale matrix regression

1. Build the default theme and mock backend by starting a headless Sway session once:

   ```sh
   fvm dart run tool/akari.dart run sway --theme themes/default \
     --display-profile reference --sway-backend headless \
     --report build/tool/native-sway.json
   ```

2. Press `q` after startup, read `artifacts.executable` and `artifacts.backend_executable` from `build/tool/native-sway.json`, and run:

   ```sh
   python3 test/support/sway_native_workflow_test.py \
     --app /path/to/greeter/bundle/greeter \
     --backend /path/to/mock/backend
   ```

This tests all four combinations of outer and inner scales (`1.0` and `1.6`) and verifies `1920x1080` inner screenshots.

## Performance gates

Execute a theme's declared performance gate or timeline trace:

```sh
fvm dart run tool/akari.dart verify-perf --theme themes/default
fvm dart run tool/akari.dart trace-perf --theme themes/default
```

Each theme declares its own runner and thresholds in `pubspec.yaml` (see the [Performance protocol](../reference/theme-package.md#performance-protocol)).

## Diagnose failures

Every CLI run writes structured logs and reports under `build/tool/runs/<run-id>/`:

- Pass `--format json` or `--report PATH` to inspect step metadata and artifact paths.
- Check the failing step's `stderr` log file first.
