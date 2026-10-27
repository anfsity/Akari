import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:scene_schema/scene_schema.dart';

class SceneStyleView extends StatelessWidget {
  const SceneStyleView({
    required this.style,
    required this.child,
    this.shape = BoxShape.rectangle,
    super.key,
  });
  final SceneStyle style;
  final Widget child;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(style.radius);
    final angle = style.gradientAngle * math.pi / 180;
    Widget content = DefaultTextStyle.merge(
      style: TextStyle(
        color: style.textColor == null ? null : Color(style.textColor!),
        fontSize: style.fontSize == 0 ? null : style.fontSize,
      ),
      child: child,
    );
    content = BackdropFilter(
      enabled: style.backgroundBlur > 0,
      filter: ui.ImageFilter.blur(
        sigmaX: style.backgroundBlur,
        sigmaY: style.backgroundBlur,
      ),
      child: content,
    );
    return SceneStyleScope(
      style: style,
      child: Opacity(
        opacity: style.opacity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: shape,
            borderRadius: shape == BoxShape.circle ? null : radius,
            color: Color(style.fill),
            gradient: style.gradientEnd == null
                ? null
                : LinearGradient(
                    begin: Alignment(-math.cos(angle), -math.sin(angle)),
                    end: Alignment(math.cos(angle), math.sin(angle)),
                    colors: [Color(style.fill), Color(style.gradientEnd!)],
                  ),
            border: Border.all(
              color: Color(style.border),
              width: style.borderWidth,
            ),
            boxShadow: [
              if (style.shadowBlur > 0)
                BoxShadow(
                  color: Color(style.shadow),
                  blurRadius: style.shadowBlur,
                  offset: Offset(0, style.shadowY),
                ),
            ],
          ),
          child: shape == BoxShape.circle
              ? ClipOval(child: content)
              : ClipRRect(
                  borderRadius: radius,
                  clipBehavior: style.radius > 0 || style.backgroundBlur > 0
                      ? Clip.antiAlias
                      : Clip.none,
                  child: content,
                ),
        ),
      ),
    );
  }
}

class SceneStyleScope extends InheritedWidget {
  const SceneStyleScope({required this.style, required super.child, super.key});
  final SceneStyle style;
  @override
  bool updateShouldNotify(SceneStyleScope oldWidget) =>
      oldWidget.style != style;
}

/// Components with explicit typography can opt into authored text overrides.
TextStyle getSceneTextStyle(BuildContext context, TextStyle fallback) {
  final style = context
      .dependOnInheritedWidgetOfExactType<SceneStyleScope>()
      ?.style;
  return fallback.copyWith(
    color: style?.textColor == null ? null : Color(style!.textColor!),
    fontSize: style == null || style.fontSize == 0 ? null : style.fontSize,
  );
}
