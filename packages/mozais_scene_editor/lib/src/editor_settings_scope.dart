import 'package:flutter/widgets.dart';

import 'editor_settings_controller.dart';

/// Exposes the [EditorSettingsController] to the editor subtree.
class EditorSettingsScope extends InheritedNotifier<EditorSettingsController> {
  const EditorSettingsScope({
    required EditorSettingsController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static EditorSettingsController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<EditorSettingsScope>();
    assert(scope != null, 'No EditorSettingsScope found in the widget tree.');
    return scope!.notifier!;
  }
}
