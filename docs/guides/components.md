---
title: Develop theme components
description: Render typed host state without owning authentication.
---

Theme components are standard Flutter widgets that render display-safe state from `GreeterHost` and trigger semantic callbacks. They never manage PAM conversations or D-Bus connections directly.

## 1. Map scene nodes in the component factory

`ThemeDefinition.components` receives a `GreeterThemeContext` (providing `tokens` and `host`) and returns a `GreeterThemeComponents` factory. During rendering, the runtime calls `build(context, node)` to turn each scene node's `component` ID into a widget:

- **Reuse standard widgets**: Use `StandardGreeterComponents` and keep the component IDs from the fallback scene.
- **Custom component catalog**: Define your own component IDs in `*.scene.json` and handle them in your factory.
- **Custom node properties**: Read string key-value pairs from `node.properties` inside the component that owns them.

## 2. Subscribe to narrow state slots

Subscribe only to the slot listenable your widget needs so unrelated state changes do not trigger rebuilds:

```dart
import 'package:flutter/material.dart';
import 'package:theme_sdk/theme_sdk.dart';

class ServiceLabel extends StatelessWidget {
  const ServiceLabel({required this.host, super.key});

  final GreeterHost host;

  @override
  Widget build(BuildContext context) {
    return SceneRegion<ServiceSlots>(
      valueListenable: host.serviceSlots,
      builder: (context, slots) => Text(slots.mode.name),
    );
  }
}
```

:::tip
`SceneRuntime` automatically wraps each scene node in a `RepaintBoundary`. Only add nested `RepaintBoundary` widgets if profiling shows a complex subtree needs independent repainting.
:::

## 3. Dispatch semantic actions

Trigger user actions through `GreeterHost` callbacks while preserving native focus, keyboard navigation, and accessibility semantics:

| Callback | Purpose |
| --- | --- |
| `onSelectUser` | Switch the active login account |
| `onSelectSession` | Select the target desktop session |
| `onRespondToPrompt` | Submit the active credential response |
| `onStartSession` | Launch the authenticated desktop session |
| `onRequestPowerAction` | Trigger suspend, reboot, or power-off |

:::caution[Credential controller ownership]
Password and prompt fields borrow `host.credentialController` and `host.credentialFocusNode`. The application owns their lifecycle—**never** call `dispose()` on them in a theme widget, and never copy credential text into scene properties or logs.
:::

## 4. Respect node mount lifetime

- **Hidden nodes**: Exit animations or prewarming may keep a hidden node mounted briefly. Keep background timers idle when hidden and clean up widget-owned subscriptions in `dispose()`.
- **Motion builders**: `SceneMotionBuilder` receives an externally driven `Animation<double>` from `SceneRuntime`—do not create or dispose your own `AnimationController` for node presence transitions.

See the [API reference](../reference/api.md) for slot definitions and [Frontend architecture](../architecture/frontend.md) for runtime boundaries.
