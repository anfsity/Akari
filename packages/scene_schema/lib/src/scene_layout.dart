enum SceneSizeMode { proportional, hug, fill }

enum SceneLayoutDirection { absolute, row, column }

enum SceneMainAlignment { start, center, end, spaceBetween }

enum SceneCrossAlignment { start, center, end, stretch }

/// Container spacing uses logical pixels. Child rectangles are relative to
/// this container; row/column containers own their children's positions.
class SceneLayout {
  const SceneLayout({
    this.direction = SceneLayoutDirection.absolute,
    this.padding = 0,
    this.gap = 0,
    this.mainAlignment = SceneMainAlignment.start,
    this.crossAlignment = SceneCrossAlignment.start,
    this.clip = false,
    this.wrap = false,
  });

  final SceneLayoutDirection direction;
  final double padding;
  final double gap;
  final SceneMainAlignment mainAlignment;
  final SceneCrossAlignment crossAlignment;
  final bool clip;
  final bool wrap;

  @override
  bool operator ==(Object other) =>
      other is SceneLayout &&
      other.direction == direction &&
      other.padding == padding &&
      other.gap == gap &&
      other.mainAlignment == mainAlignment &&
      other.crossAlignment == crossAlignment &&
      other.clip == clip &&
      other.wrap == wrap;

  @override
  int get hashCode => Object.hash(
    direction,
    padding,
    gap,
    mainAlignment,
    crossAlignment,
    clip,
    wrap,
  );
}

/// Fixed logical dimensions override proportional rectangle dimensions. In a
/// row/column, flex shares the remaining main-axis space with other flex items.
class SceneSizing {
  const SceneSizing({
    this.width,
    this.height,
    this.flex = 0,
    this.widthMode = SceneSizeMode.proportional,
    this.heightMode = SceneSizeMode.proportional,
    this.minWidth = 0,
    this.minHeight = 0,
    this.maxWidth,
    this.maxHeight,
  });

  final double? width;
  final double? height;
  final double flex;
  final SceneSizeMode widthMode;
  final SceneSizeMode heightMode;
  final double minWidth;
  final double minHeight;
  final double? maxWidth;
  final double? maxHeight;

  SceneSizing copyWith({
    Object? width = _unset,
    Object? height = _unset,
    double? flex,
    SceneSizeMode? widthMode,
    SceneSizeMode? heightMode,
    double? minWidth,
    double? minHeight,
    Object? maxWidth = _unset,
    Object? maxHeight = _unset,
  }) => SceneSizing(
    width: identical(width, _unset) ? this.width : width as double?,
    height: identical(height, _unset) ? this.height : height as double?,
    flex: flex ?? this.flex,
    widthMode: widthMode ?? this.widthMode,
    heightMode: heightMode ?? this.heightMode,
    minWidth: minWidth ?? this.minWidth,
    minHeight: minHeight ?? this.minHeight,
    maxWidth: identical(maxWidth, _unset) ? this.maxWidth : maxWidth as double?,
    maxHeight: identical(maxHeight, _unset)
        ? this.maxHeight
        : maxHeight as double?,
  );

  @override
  bool operator ==(Object other) =>
      other is SceneSizing &&
      other.width == width &&
      other.height == height &&
      other.flex == flex &&
      other.widthMode == widthMode &&
      other.heightMode == heightMode &&
      other.minWidth == minWidth &&
      other.minHeight == minHeight &&
      other.maxWidth == maxWidth &&
      other.maxHeight == maxHeight;

  @override
  int get hashCode => Object.hash(
    width,
    height,
    flex,
    widthMode,
    heightMode,
    minWidth,
    minHeight,
    maxWidth,
    maxHeight,
  );
}

/// The widest matching rule overrides base layout/sizing at logical viewport
/// widths. Rules affect presentation only and survive reparenting and export.
class SceneBreakpoint {
  const SceneBreakpoint({required this.minWidth, this.layout, this.sizing});

  final double minWidth;
  final SceneLayout? layout;
  final SceneSizing? sizing;

  @override
  bool operator ==(Object other) =>
      other is SceneBreakpoint &&
      other.minWidth == minWidth &&
      other.layout == layout &&
      other.sizing == sizing;

  @override
  int get hashCode => Object.hash(minWidth, layout, sizing);
}

/// Fractions of the available parent content area, independent of resolution.
/// Root nodes use the safe-area-adjusted canvas when that policy is enabled.
class SceneRect {
  const SceneRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  bool get isNormalized =>
      x >= 0 &&
      y >= 0 &&
      width > 0 &&
      height > 0 &&
      x + width <= 1 &&
      y + height <= 1;

  SceneRect copyWith({double? x, double? y, double? width, double? height}) {
    return SceneRect(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SceneRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);
}

/// Transform in node-local coordinates: translations use logical pixels,
/// rotations use degrees, and pivots use fractions of the node's laid-out size.
/// These units differ deliberately from [SceneRect]'s normalized canvas units.
class SceneTransform {
  const SceneTransform({
    this.translateX = 0,
    this.translateY = 0,
    this.scaleX = 1,
    this.scaleY = 1,
    this.rotationX = 0,
    this.rotationY = 0,
    this.rotationZ = 0,
    this.pivotX = 0.5,
    this.pivotY = 0.5,
    this.perspective = 0,
  });

  final double translateX;
  final double translateY;
  final double scaleX;
  final double scaleY;
  final double rotationX;
  final double rotationY;
  final double rotationZ;
  final double pivotX;
  final double pivotY;
  final double perspective;

  bool get isIdentity =>
      translateX == 0 &&
      translateY == 0 &&
      scaleX == 1 &&
      scaleY == 1 &&
      rotationX == 0 &&
      rotationY == 0 &&
      rotationZ == 0 &&
      perspective == 0;

  bool get isDefault => isIdentity && pivotX == 0.5 && pivotY == 0.5;

  SceneTransform copyWith({
    double? translateX,
    double? translateY,
    double? scaleX,
    double? scaleY,
    double? rotationX,
    double? rotationY,
    double? rotationZ,
    double? pivotX,
    double? pivotY,
    double? perspective,
  }) {
    return SceneTransform(
      translateX: translateX ?? this.translateX,
      translateY: translateY ?? this.translateY,
      scaleX: scaleX ?? this.scaleX,
      scaleY: scaleY ?? this.scaleY,
      rotationX: rotationX ?? this.rotationX,
      rotationY: rotationY ?? this.rotationY,
      rotationZ: rotationZ ?? this.rotationZ,
      pivotX: pivotX ?? this.pivotX,
      pivotY: pivotY ?? this.pivotY,
      perspective: perspective ?? this.perspective,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SceneTransform &&
      other.translateX == translateX &&
      other.translateY == translateY &&
      other.scaleX == scaleX &&
      other.scaleY == scaleY &&
      other.rotationX == rotationX &&
      other.rotationY == rotationY &&
      other.rotationZ == rotationZ &&
      other.pivotX == pivotX &&
      other.pivotY == pivotY &&
      other.perspective == perspective;

  @override
  int get hashCode => Object.hash(
    translateX,
    translateY,
    scaleX,
    scaleY,
    rotationX,
    rotationY,
    rotationZ,
    pivotX,
    pivotY,
    perspective,
  );
}

const Object _unset = Object();
