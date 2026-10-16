---
title: Develop and test
description: Choose unit, mock integration, compositor, and performance checks.
---

## Repository verification

```sh
fvm dart run tool/akari.dart verify
fvm dart run tool/akari.dart verify --theme themes/fallback
```

Verification checks shared code and the Rust backend, and runs tests for
discovered theme projects. Selecting a theme narrows theme checks while retaining
the shared checks, including Studio analysis and tests. Themes own their UI tests;
runtime and schema packages own their contracts.

Test behavior that matters: scene validation, state transitions, attempt isolation,
slot notifications, focus and keyboard interaction, resource lifetime, and
performance. Avoid tests that encode exact visual placement.

`test/login_cli_test.dart` also runs `test/support/login_workflow_test.py`.
These checks simulate systemd and account boundaries while exercising deployment,
failed switches, restoration, rollback, permissions and greeter child cleanup.
They do not change the host's display manager or replace manual DRM/PAM testing.

## Mock integration

```sh
fvm dart run tool/akari.dart run --theme themes/fallback
```

Use this for the complete frontend/D-Bus path without system PAM calls. Use
`preview` to automatically demonstrate face success and password fallback once
in one window; `--scenario` selects a single journey. It exits automatically and
does not exercise a camera or PAM.

## Compositor and real login

```sh
fvm dart run tool/akari.dart run sway --display-profile reference
fvm dart run tool/akari.dart run sway --display-profile reference --sway-backend headless
```

The nested/headless session owns a private backend, bus, compositor, and frontend.
Follow [display testing](display-testing.md) for shared-state checks, scale
comparisons, and screenshots. The [CLI reference](../reference/cli.md#sway-sessions-and-display-profiles)
defines display profiles and actual-output verification.

Real greetd testing is a separate [standalone workflow](greetd-testing.md), with
its own installation, TTY preflight, and recovery lifecycle.

## Native display regressions

These opt-in scripts start real Flutter windows in isolated compositors. They
are separate from `akari verify` and retain logs and screenshots in the printed
temporary directory. Install Sway, `swaymsg`, and grim; the multi-display script
also needs wtype.

For monitor lifetime and focus checks, build an ordinary default-theme demo
bundle. Automated `preview` executables contain a test entrypoint and cannot be
used for persistent multi-monitor checks.

```sh
fvm dart run tool/akari.dart generate-scenes --theme themes/default
fvm flutter build linux --release --target tool/dev_main.dart --dart-define=AKARI_BACKEND=demo
python3 test/support/multi_display_workflow_test.py \
  --app build/linux/x64/release/bundle/greeter
```

This checks mixed output scales, pointer focus across views, display addition,
removal of the primary view's monitor, removal of every monitor, reconnection,
and single-window modes. Shared credentials and one-response keyboard dispatch
are covered by `test/multi_display_test.dart` in the normal Flutter test suite.

For the nested output matrix, prepare a greeter with its mock D-Bus backend:

```sh
fvm dart run tool/akari.dart run sway --theme themes/default \
  --display-profile reference --sway-backend headless \
  --report build/tool/native-sway.json
```

Quit after startup, then read `artifacts.executable` and
`artifacts.backend_executable` from the report. Replace both paths below with
those artifacts; this script requires the mock backend built by `run sway`.

```sh
python3 test/support/sway_native_workflow_test.py \
  --app /path/to/greeter/bundle/greeter \
  --backend /path/to/mock/backend
```

The test owns a headless outer Sway and exercises outer and inner scales 1 and
1.6 in four combinations, checking output reports and 1920×1080 inner images.
It does not verify Hyprland-specific placement, DRM, real PAM authentication,
or display-manager recovery; use the manual display and standalone workflows
for those behaviors.

## Performance

```sh
fvm dart run tool/akari.dart verify-perf --theme themes/default
fvm dart run tool/akari.dart trace-perf --theme themes/default
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
