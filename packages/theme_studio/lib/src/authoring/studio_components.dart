import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

enum StudioComponent {
  text('Text', LucideIcons.type, ScenePrimitive.text),
  rectangle('Rectangle', LucideIcons.square, ScenePrimitive.rectangle),
  circle('Circle', LucideIcons.circle, ScenePrimitive.circle),
  frame('Frame', LucideIcons.frame, null);

  const StudioComponent(this.label, this.icon, this.primitive);
  final String label;
  final IconData icon;
  final ScenePrimitive? primitive;
}
