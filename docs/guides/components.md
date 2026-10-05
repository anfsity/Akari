---
title: Develop theme components
description: Render typed host state without owning authentication.
---

## The component factory

`ThemeDefinition.components` receives a `GreeterThemeContext`, which contains the
theme's tokens and `GreeterHost`. Its returned `GreeterThemeComponents` maps
scene component identifiers to Flutter widgets through `build(context, node)`.
Identifiers are private to this factory; the Scene runtime does not prescribe
a universal widget catalog.

When using `StandardGreeterComponents`, keep its supported identifiers from the
fallback scene. When writing your own factory, make the scene and factory agree
on each identifier. Node `properties` are string-valued authoring data owned by
that component; parse them where the component owns their meaning.

## Subscribe to one region

Use a typed slot for the content a widget displays. For example, a small service
status widget can subscribe only to `serviceSlots`:

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

This keeps unrelated account, session, or power updates from rebuilding the label.
`SceneRuntime` already places a repaint boundary around each scene node. Add an
extra boundary only when profiling demonstrates a need.

## Dispatch semantic actions

Components call host callbacks such as `onSelectUser`, `onSelectSession`,
`onRespondToPrompt`, and `onRequestPowerAction`. Enable controls using the
appropriate slots and preserve native keyboard, focus, and accessibility behavior.
Authentication state, transport objects, and D-Bus calls belong to the greeter
feature and backend.

Credential widgets borrow `credentialController` and `credentialFocusNode`.
Their owner disposes them; theme widgets must not dispose them. Do not copy
credential text into scene properties, visual configuration, or logs.

## Respect mount lifetime

Presence animations and prewarming can keep a hidden node mounted. Keep hidden
subscriptions and timers inexpensive, and dispose component-owned resources
when the widget unmounts. Motion builders borrow runtime-driven animations;
they do not own an animation controller.

Use the [API reference](../reference/api.md) for exact types and the
[frontend architecture](../architecture/frontend.md) for ownership details.
