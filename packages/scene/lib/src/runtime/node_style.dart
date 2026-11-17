import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:scene_schema/scene_schema.dart';

import 'scene_font.dart';

final ui.ImageFilter _noBlurFilter = ui.ImageFilter.blur();

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
  String? _fontFamily;
  int _fontRevision = 0;

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
    final revision = ++_fontRevision;
    final asset = widget.style.fontAsset;
    if (asset == null) {
      _fontFamily = null;
      return;
    }
    _fontFamily = null;
    unawaited(
      (widget.loadFont ?? loadBundledSceneFont)(asset).then(
        (family) {
          if (mounted && revision == _fontRevision && _fontFamily != family) {
            setState(() => _fontFamily = family);
          }
        },
        onError: (_) {},
      ),
    );
  }

  @override
  void reassemble() {
    super.reassemble();
    _loadFont();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final shape = widget.shape;
    final family = _fontFamily;

    final radius = BorderRadius.circular(style.radius);
    final angle = style.gradientAngle * math.pi / 180;
    Widget content = DefaultTextStyle.merge(
      style: getResolvedSceneTextStyle(style, fontFamily: family),
      child: widget.child,
    );
    content = BackdropFilter(
      enabled: style.backgroundBlur > 0,
      filter: style.backgroundBlur > 0
          ? ui.ImageFilter.blur(
              sigmaX: style.backgroundBlur,
              sigmaY: style.backgroundBlur,
            )
          : _noBlurFilter,
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
            color: style.gradientEnd == null && style.fill == 0
                ? null
                : Color(style.fill),
            gradient: style.gradientEnd == null
                ? null
                : LinearGradient(
                    begin: Alignment(-math.cos(angle), -math.sin(angle)),
                    end: Alignment(math.cos(angle), math.sin(angle)),
                    colors: [Color(style.fill), Color(style.gradientEnd!)],
                  ),
            border: style.borderWidth > 0
                ? Border.all(
                    color: Color(style.border),
                    width: style.borderWidth,
                  )
                : null,
            boxShadow: style.shadowBlur > 0
                ? [
                    BoxShadow(
                      color: Color(style.shadow),
                      blurRadius: style.shadowBlur,
                      offset: Offset(0, style.shadowY),
                    ),
                  ]
                : null,
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

TextStyle getResolvedSceneTextStyle(
  SceneStyle style, {
  String? fontFamily,
  double? defaultFontSize,
  FontWeight? defaultFontWeight,
}) => TextStyle(
  color: style.textColor == null ? null : Color(style.textColor!),
  fontSize: style.fontSize == 0 ? defaultFontSize : style.fontSize,
  fontFamily: fontFamily,
  fontWeight: style.fontWeight == 0
      ? defaultFontWeight
      : FontWeight.values[style.fontWeight ~/ 100 - 1],
  letterSpacing: style.letterSpacing,
  height: style.lineHeight,
);

/// Components with explicit typography can opt into authored text overrides.
TextStyle getSceneTextStyle(BuildContext context, TextStyle fallback) {
  final scope = context.dependOnInheritedWidgetOfExactType<SceneStyleScope>();
  final style = scope?.style;
  if (style == null) {
    return fallback.copyWith(fontFamily: scope?.fontFamily);
  }
  return fallback.merge(
    getResolvedSceneTextStyle(style, fontFamily: scope?.fontFamily),
  );
}
