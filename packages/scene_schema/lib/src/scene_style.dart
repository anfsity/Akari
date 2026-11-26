enum SceneAssetKind { image, svg }

enum ScenePrimitive { text, rectangle, circle }

enum SceneAssetFit { contain, cover, fill }

class SceneAsset {
  const SceneAsset({
    required this.path,
    this.kind = SceneAssetKind.image,
    this.fit = SceneAssetFit.contain,
    this.tint,
  });

  final String path;
  final SceneAssetKind kind;
  final SceneAssetFit fit;
  final int? tint;

  SceneAsset copyWith({
    String? path,
    SceneAssetFit? fit,
    Object? tint = _unset,
  }) => SceneAsset(
    path: path ?? this.path,
    kind: kind,
    fit: fit ?? this.fit,
    tint: identical(tint, _unset) ? this.tint : tint as int?,
  );

  @override
  bool operator ==(Object other) =>
      other is SceneAsset &&
      other.path == path &&
      other.kind == kind &&
      other.fit == fit &&
      other.tint == tint;

  @override
  int get hashCode => Object.hash(path, kind, fit, tint);
}

/// Named, reusable visual values shared by Studio and the compiled runtime.
class SceneStyle {
  const SceneStyle({
    this.fill = 0x00000000,
    this.gradientEnd,
    this.gradientAngle = 90,
    this.border = 0x00000000,
    this.borderWidth = 0,
    this.radius = 0,
    this.shadow = 0x66000000,
    this.shadowBlur = 0,
    this.shadowY = 4,
    this.backgroundBlur = 0,
    this.textColor,
    this.fontSize = 0,
    this.fontAsset,
    this.fontWeight = 0,
    this.letterSpacing,
    this.lineHeight,
    this.opacity = 1,
  });

  final int fill;
  final int? gradientEnd;
  final double gradientAngle;
  final int border;
  final double borderWidth;
  final double radius;
  final int shadow;
  final double shadowBlur;
  final double shadowY;
  final double backgroundBlur;
  final int? textColor;
  final double fontSize;
  final String? fontAsset;
  final int fontWeight;
  final double? letterSpacing;
  final double? lineHeight;
  final double opacity;

  SceneStyle copyWith({
    int? fill,
    Object? gradientEnd = _unset,
    double? gradientAngle,
    int? border,
    double? borderWidth,
    double? radius,
    int? shadow,
    double? shadowBlur,
    double? shadowY,
    double? backgroundBlur,
    Object? textColor = _unset,
    double? fontSize,
    Object? fontAsset = _unset,
    int? fontWeight,
    Object? letterSpacing = _unset,
    Object? lineHeight = _unset,
    double? opacity,
  }) => SceneStyle(
    fill: fill ?? this.fill,
    gradientEnd: identical(gradientEnd, _unset)
        ? this.gradientEnd
        : gradientEnd as int?,
    gradientAngle: gradientAngle ?? this.gradientAngle,
    border: border ?? this.border,
    borderWidth: borderWidth ?? this.borderWidth,
    radius: radius ?? this.radius,
    shadow: shadow ?? this.shadow,
    shadowBlur: shadowBlur ?? this.shadowBlur,
    shadowY: shadowY ?? this.shadowY,
    backgroundBlur: backgroundBlur ?? this.backgroundBlur,
    textColor: identical(textColor, _unset)
        ? this.textColor
        : textColor as int?,
    fontSize: fontSize ?? this.fontSize,
    fontAsset: identical(fontAsset, _unset)
        ? this.fontAsset
        : fontAsset as String?,
    fontWeight: fontWeight ?? this.fontWeight,
    letterSpacing: identical(letterSpacing, _unset)
        ? this.letterSpacing
        : letterSpacing as double?,
    lineHeight: identical(lineHeight, _unset)
        ? this.lineHeight
        : lineHeight as double?,
    opacity: opacity ?? this.opacity,
  );

  @override
  bool operator ==(Object other) =>
      other is SceneStyle &&
      other.fill == fill &&
      other.gradientEnd == gradientEnd &&
      other.gradientAngle == gradientAngle &&
      other.border == border &&
      other.borderWidth == borderWidth &&
      other.radius == radius &&
      other.shadow == shadow &&
      other.shadowBlur == shadowBlur &&
      other.shadowY == shadowY &&
      other.backgroundBlur == backgroundBlur &&
      other.textColor == textColor &&
      other.fontSize == fontSize &&
      other.fontAsset == fontAsset &&
      other.fontWeight == fontWeight &&
      other.letterSpacing == letterSpacing &&
      other.lineHeight == lineHeight &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(
    fill,
    gradientEnd,
    gradientAngle,
    border,
    borderWidth,
    radius,
    shadow,
    shadowBlur,
    shadowY,
    backgroundBlur,
    textColor,
    fontSize,
    fontAsset,
    fontWeight,
    letterSpacing,
    lineHeight,
    opacity,
  );
}

bool isSceneAssetPath(String path) =>
    !path.contains('..') &&
    !path.contains(r'\') &&
    !path.endsWith('/') &&
    (path.startsWith('assets/') || path.startsWith('packages/'));

const Object _unset = Object();
