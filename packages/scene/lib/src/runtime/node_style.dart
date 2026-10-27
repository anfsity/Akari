import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:scene_schema/scene_schema.dart';

import 'scene_font.dart';

class SceneStyleView extends StatefulWidget {
  const SceneStyleView({
    required this.style,
    required this.child,
    this.shape = BoxShape.rectangle,
    this.loadFont,
    super.key,
  });
  final SceneStyle style;
  final Widget child;
  final BoxShape shape;

  final SceneFontLoader? loadFont;
  @override
  State<SceneStyleView> createState() => _SceneStyleViewState();
}

class _SceneStyleViewState extends State<SceneStyleView> {
  Future<String>? _font;
  @override
  void initState() {
    super.initState();
    _loadFont();
  }

  @override
  void didUpdateWidget(SceneStyleView old) {
    super.didUpdateWidget(old);
    if (old.style.fontAsset != widget.style.fontAsset ||
        old.loadFont != widget.loadFont) {
      _loadFont();
    }
  }

  void _loadFont() {
    final asset = widget.style.fontAsset;
    _font = asset == null
        ? null
        : (widget.loadFont ?? loadBundledSceneFont)(asset);
  }

  @override
  void reassemble() {
    super.reassemble();
    _loadFont();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _font,
    builder: (context, snapshot) => _buildStyle(context, snapshot.data),
  );

  Widget _buildStyle(BuildContext context, String? family) {
    final style = widget.style;
    final shape = widget.shape;

    final radius = BorderRadius.circular(style.radius);
    final angle = style.gradientAngle * math.pi / 180;
    Widget content = DefaultTextStyle.merge(
      style: TextStyle(
        color: style.textColor == null ? null : Color(style.textColor!),
        fontSize: style.fontSize == 0 ? null : style.fontSize,
        fontFamily: family,
        fontWeight: style.fontWeight == 0
            ? null
            : FontWeight.values[style.fontWeight ~/ 100 - 1],
        letterSpacing: style.letterSpacing,
        height: style.lineHeight,
      ),
      child: widget.child,
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
      fontFamily: family,
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
  const SceneStyleScope({
    required this.style,
    required super.child,
    this.fontFamily,
    super.key,
  });
  final SceneStyle style;
  final String? fontFamily;
  @override
  bool updateShouldNotify(SceneStyleScope oldWidget) =>
      oldWidget.style != style || oldWidget.fontFamily != fontFamily;
}

/// Components with explicit typography can opt into authored text overrides.
TextStyle getSceneTextStyle(BuildContext context, TextStyle fallback) {
  final scope = context.dependOnInheritedWidgetOfExactType<SceneStyleScope>();
  final style = scope?.style;
  return fallback.copyWith(
    color: style?.textColor == null ? null : Color(style!.textColor!),
    fontSize: style == null || style.fontSize == 0 ? null : style.fontSize,
    fontFamily: scope?.fontFamily,
    fontWeight: style == null || style.fontWeight == 0
        ? null
        : FontWeight.values[style.fontWeight ~/ 100 - 1],
    letterSpacing: style?.letterSpacing,
    height: style?.lineHeight,
  );
}
