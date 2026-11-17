import 'collections.dart';
import 'scene_shader.dart';

enum SceneCanvasFit { cover, contain, reflow }

const currentSceneVersion = 3;
const maxSceneMotionTimeMs = 60000;
const maxSceneKeyframeMagnitude = 100000.0;

enum SceneSizeMode { proportional, hug, fill }

enum SceneLayoutDirection { absolute, row, column }

enum SceneMainAlignment { start, center, end, spaceBetween }

enum SceneCrossAlignment { start, center, end, stretch }

enum SceneGuideAxis { horizontal, vertical }

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

class SceneGuide {
  const SceneGuide({required this.axis, required this.position});
  final SceneGuideAxis axis;
  final double position;
  @override
  bool operator ==(Object other) =>
      other is SceneGuide && other.axis == axis && other.position == position;
  @override
  int get hashCode => Object.hash(axis, position);
}

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

SceneNode getSceneNodeForWidth(SceneNode node, double width) {
  SceneBreakpoint? match;
  for (final rule in node.breakpoints) {
    if (rule.minWidth <= width &&
        (match == null || rule.minWidth > match.minWidth)) {
      match = rule;
    }
  }
  return match == null
      ? node
      : node.copyWith(
          layout: match.layout ?? node.layout,
          sizing: match.sizing ?? node.sizing,
        );
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

/// Boolean questions about semantic greeter state used by [SceneCondition].
///
/// The vocabulary is closed so a theme or editor can only reference known
/// predicates; it never evaluates arbitrary expressions or backend values.
enum ScenePredicate {
  isDormant,
  isServiceStarting,
  isServiceReady,
  isServiceUnavailable,
  isUserSelection,
  isAuthPrompting,
  isAuthSubmitting,
  isSessionSelection,
  isHandingOff,
  isAuthError,
  hasSelectedUser,
  isSessionLoading,
  isSessionReady,
  isSessionEmpty,
  isSessionFailed,
  isPowerExecuting,
  hasPowerError,
}

/// Declarative presence condition over [ScenePredicate] values.
sealed class SceneCondition {
  const SceneCondition();
}

final class ScenePredicateCondition extends SceneCondition {
  const ScenePredicateCondition(this.predicate);

  final ScenePredicate predicate;

  @override
  bool operator ==(Object other) =>
      other is ScenePredicateCondition && other.predicate == predicate;

  @override
  int get hashCode => predicate.hashCode;
}

final class SceneAll extends SceneCondition {
  const SceneAll(this.conditions);

  final List<SceneCondition> conditions;

  @override
  bool operator ==(Object other) =>
      other is SceneAll && listEquals(other.conditions, conditions);

  @override
  int get hashCode => Object.hash(SceneAll, Object.hashAll(conditions));
}

final class SceneAny extends SceneCondition {
  const SceneAny(this.conditions);

  final List<SceneCondition> conditions;

  @override
  bool operator ==(Object other) =>
      other is SceneAny && listEquals(other.conditions, conditions);

  @override
  int get hashCode => Object.hash(SceneAny, Object.hashAll(conditions));
}

final class SceneNot extends SceneCondition {
  const SceneNot(this.condition);

  final SceneCondition condition;

  @override
  bool operator ==(Object other) =>
      other is SceneNot && other.condition == condition;

  @override
  int get hashCode => Object.hash(SceneNot, condition);
}

/// Evaluates [condition] against the predicates currently true for the scene.
bool evaluateSceneCondition(
  SceneCondition condition,
  Set<ScenePredicate> activePredicates,
) {
  return switch (condition) {
    ScenePredicateCondition(:final predicate) => activePredicates.contains(
      predicate,
    ),
    SceneAll(:final conditions) => conditions.every(
      (condition) => evaluateSceneCondition(condition, activePredicates),
    ),
    SceneAny(:final conditions) => conditions.any(
      (condition) => evaluateSceneCondition(condition, activePredicates),
    ),
    SceneNot(:final condition) => !evaluateSceneCondition(
      condition,
      activePredicates,
    ),
  };
}

enum SceneMotionPreset {
  none,
  fade,
  fadeSlide,
  fadeScale,
  hoverLift,
  focusGlow,
}

enum SceneStateEffect { shake, pulse }

/// Shared sign-in/recovery visibility rule used by the primary action slot.
const SceneCondition primaryActionVisibilityCondition = SceneAll([
  SceneNot(ScenePredicateCondition(ScenePredicate.isDormant)),
  SceneAny([
    ScenePredicateCondition(ScenePredicate.isAuthPrompting),
    ScenePredicateCondition(ScenePredicate.isAuthSubmitting),
    ScenePredicateCondition(ScenePredicate.isSessionSelection),
    ScenePredicateCondition(ScenePredicate.isAuthError),
    ScenePredicateCondition(ScenePredicate.isServiceUnavailable),
  ]),
]);

class SceneStateTransition {
  const SceneStateTransition({
    required this.source,
    required this.target,
    required this.effect,
    this.timing = const SceneMotionTiming(),
  });
  final SceneCondition source;
  final SceneCondition target;
  final SceneStateEffect effect;
  final SceneMotionTiming timing;

  @override
  bool operator ==(Object other) =>
      other is SceneStateTransition &&
      other.source == source &&
      other.target == target &&
      other.effect == effect &&
      other.timing == timing;

  @override
  int get hashCode => Object.hash(source, target, effect, timing);
}

/// State-entry responses and authored edges use one crossing evaluator.
/// Explicit edges take precedence, in authoring order, over simple entries.
SceneStateTransition? findSceneStateTransition(
  SceneNode node,
  Set<ScenePredicate> previous,
  Set<ScenePredicate> current,
) {
  SceneStateTransition? match;
  for (final rule in [
    for (final entry in node.stateEffects.entries)
      SceneStateTransition(
        source: SceneNot(ScenePredicateCondition(entry.key)),
        target: ScenePredicateCondition(entry.key),
        effect: entry.value,
      ),
    ...node.transitions,
  ]) {
    if (evaluateSceneCondition(rule.source, previous) &&
        !evaluateSceneCondition(rule.target, previous) &&
        evaluateSceneCondition(rule.target, current)) {
      match = rule;
    }
  }
  return match;
}

class SceneCubicBezier {
  const SceneCubicBezier(this.x1, this.y1, this.x2, this.y2);
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  @override
  bool operator ==(Object other) =>
      other is SceneCubicBezier &&
      other.x1 == x1 &&
      other.y1 == y1 &&
      other.x2 == x2 &&
      other.y2 == y2;

  @override
  int get hashCode => Object.hash(x1, y1, x2, y2);
}

class SceneMotionTiming {
  const SceneMotionTiming({this.durationMs, this.delayMs = 0, this.curve});
  final int? durationMs;
  final int delayMs;
  final SceneCubicBezier? curve;
  bool get isDefault => durationMs == null && delayMs == 0 && curve == null;

  @override
  bool operator ==(Object other) =>
      other is SceneMotionTiming &&
      other.durationMs == durationMs &&
      other.delayMs == delayMs &&
      other.curve == curve;

  @override
  int get hashCode => Object.hash(durationMs, delayMs, curve);
}

enum SceneMotionProperty { opacity, translateX, translateY, scale, rotation }

enum SceneKeyframeCurve { linear, easeInOut, hold }

class SceneKeyframe {
  const SceneKeyframe({
    required this.timeMs,
    required this.value,
    this.curve = SceneKeyframeCurve.linear,
  });
  final int timeMs;
  final double value;

  /// Easing from this frame to the next frame.
  final SceneKeyframeCurve curve;

  @override
  bool operator ==(Object other) =>
      other is SceneKeyframe &&
      other.timeMs == timeMs &&
      other.value == value &&
      other.curve == curve;

  @override
  int get hashCode => Object.hash(timeMs, value, curve);
}

class SceneMotionTrack {
  const SceneMotionTrack({required this.property, required this.keyframes});
  final SceneMotionProperty property;
  final List<SceneKeyframe> keyframes;

  @override
  bool operator ==(Object other) =>
      other is SceneMotionTrack &&
      other.property == property &&
      listEquals(other.keyframes, keyframes);

  @override
  int get hashCode => Object.hash(property, Object.hashAll(keyframes));
}

enum SceneBackgroundKind { image, solid, video, custom }

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

class SceneCanvas {
  const SceneCanvas({
    this.fit = SceneCanvasFit.cover,
    this.useSafeArea = true,
    this.referenceWidth = 1920,
    this.referenceHeight = 1080,
  });

  final SceneCanvasFit fit;
  final bool useSafeArea;
  final int referenceWidth;
  final int referenceHeight;

  SceneCanvas copyWith({
    SceneCanvasFit? fit,
    bool? useSafeArea,
    int? referenceWidth,
    int? referenceHeight,
  }) {
    return SceneCanvas(
      fit: fit ?? this.fit,
      useSafeArea: useSafeArea ?? this.useSafeArea,
      referenceWidth: referenceWidth ?? this.referenceWidth,
      referenceHeight: referenceHeight ?? this.referenceHeight,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SceneCanvas &&
      other.fit == fit &&
      other.useSafeArea == useSafeArea &&
      other.referenceWidth == referenceWidth &&
      other.referenceHeight == referenceHeight;

  @override
  int get hashCode =>
      Object.hash(fit, useSafeArea, referenceWidth, referenceHeight);
}

class SceneBackground {
  const SceneBackground({
    required this.kind,
    this.asset,
    this.color = 0xff0d151a,
    this.scrimOpacity = 0.35,
    this.blurSigma = 0,
    this.rendererId,
    this.parameters = const {},
    this.shader,
  });

  final SceneBackgroundKind kind;
  final String? asset;

  /// Background fill as a 32-bit ARGB value, matching `Color.value`.
  final int color;

  final double scrimOpacity;

  /// Static Gaussian blur applied to the background layer.
  ///
  /// A non-zero value frosts the whole canvas so foreground surfaces stay
  /// legible; the blur is cached with the background repaint boundary.
  final double blurSigma;
  final String? rendererId;
  final Map<String, double> parameters;
  final SceneShader? shader;

  SceneBackground copyWith({
    SceneBackgroundKind? kind,
    Object? asset = _unset,
    int? color,
    double? scrimOpacity,
    double? blurSigma,
    Object? rendererId = _unset,
    Map<String, double>? parameters,
    Object? shader = _unset,
  }) {
    return SceneBackground(
      kind: kind ?? this.kind,
      asset: identical(asset, _unset) ? this.asset : asset as String?,
      color: color ?? this.color,
      scrimOpacity: scrimOpacity ?? this.scrimOpacity,
      blurSigma: blurSigma ?? this.blurSigma,
      rendererId: identical(rendererId, _unset)
          ? this.rendererId
          : rendererId as String?,
      parameters: parameters ?? this.parameters,
      shader: identical(shader, _unset) ? this.shader : shader as SceneShader?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SceneBackground &&
      other.kind == kind &&
      other.asset == asset &&
      other.color == color &&
      other.scrimOpacity == scrimOpacity &&
      other.blurSigma == blurSigma &&
      other.rendererId == rendererId &&
      _mapEquals(other.parameters, parameters) &&
      other.shader == shader;

  @override
  int get hashCode => Object.hash(
    kind,
    asset,
    color,
    scrimOpacity,
    blurSigma,
    rendererId,
    _hashMap(parameters),
    shader,
  );
}

/// Authored layout and component identity, without executable business logic.
/// [componentId] is resolved by the selected theme's component factory; string
/// properties configure that component rather than invoking backend commands.
class SceneNode {
  const SceneNode({
    required this.id,
    required this.componentId,
    required this.rect,
    this.parentId,
    this.layout,
    this.sizing = const SceneSizing(),
    this.breakpoints = const [],
    this.styleToken,
    this.asset,
    this.primitive,
    this.transform = const SceneTransform(),
    this.z = 0,
    this.renderOrder = 0,
    this.focusOrder = 0,
    this.motion = SceneMotionPreset.none,
    this.motionTiming = const SceneMotionTiming(),
    this.tracks = const [],
    this.stateEffects = const {},
    this.transitions = const [],
    this.visibleWhen,
    this.interactive = false,
    this.properties = const <String, String>{},
  });

  final String id;
  final String componentId;
  final SceneRect rect;
  final String? parentId;

  /// Non-null marks a runtime-owned frame, independent of theme components.
  final SceneLayout? layout;
  final SceneSizing sizing;
  final List<SceneBreakpoint> breakpoints;
  final String? styleToken;
  final SceneAsset? asset;
  final ScenePrimitive? primitive;
  final SceneTransform transform;
  final int z;
  final int renderOrder;
  final int focusOrder;
  final SceneMotionPreset motion;
  final SceneMotionTiming motionTiming;
  final List<SceneMotionTrack> tracks;
  final Map<ScenePredicate, SceneStateEffect> stateEffects;
  final List<SceneStateTransition> transitions;

  /// Condition controlling whether the node is present; null means always.
  final SceneCondition? visibleWhen;

  final bool interactive;
  final Map<String, String> properties;

  SceneNode copyWith({
    String? id,
    String? componentId,
    SceneRect? rect,
    Object? parentId = _unset,
    Object? layout = _unset,
    SceneSizing? sizing,
    List<SceneBreakpoint>? breakpoints,
    Object? styleToken = _unset,
    Object? asset = _unset,
    Object? primitive = _unset,
    SceneTransform? transform,
    int? z,
    int? renderOrder,
    int? focusOrder,
    SceneMotionPreset? motion,
    SceneMotionTiming? motionTiming,
    List<SceneMotionTrack>? tracks,
    Map<ScenePredicate, SceneStateEffect>? stateEffects,
    List<SceneStateTransition>? transitions,
    Object? visibleWhen = _unset,
    bool? interactive,
    Map<String, String>? properties,
  }) {
    return SceneNode(
      id: id ?? this.id,
      componentId: componentId ?? this.componentId,
      rect: rect ?? this.rect,
      parentId: identical(parentId, _unset)
          ? this.parentId
          : parentId as String?,
      layout: identical(layout, _unset) ? this.layout : layout as SceneLayout?,
      sizing: sizing ?? this.sizing,
      breakpoints: breakpoints ?? this.breakpoints,
      styleToken: identical(styleToken, _unset)
          ? this.styleToken
          : styleToken as String?,
      asset: identical(asset, _unset) ? this.asset : asset as SceneAsset?,
      primitive: identical(primitive, _unset)
          ? this.primitive
          : primitive as ScenePrimitive?,
      transform: transform ?? this.transform,
      z: z ?? this.z,
      renderOrder: renderOrder ?? this.renderOrder,
      focusOrder: focusOrder ?? this.focusOrder,
      motion: motion ?? this.motion,
      motionTiming: motionTiming ?? this.motionTiming,
      tracks: tracks ?? this.tracks,
      stateEffects: stateEffects ?? this.stateEffects,
      transitions: transitions ?? this.transitions,
      visibleWhen: identical(visibleWhen, _unset)
          ? this.visibleWhen
          : visibleWhen as SceneCondition?,
      interactive: interactive ?? this.interactive,
      properties: properties ?? this.properties,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SceneNode &&
      other.id == id &&
      other.componentId == componentId &&
      other.rect == rect &&
      other.parentId == parentId &&
      other.layout == layout &&
      other.sizing == sizing &&
      listEquals(other.breakpoints, breakpoints) &&
      other.styleToken == styleToken &&
      other.asset == asset &&
      other.primitive == primitive &&
      other.transform == transform &&
      other.z == z &&
      other.renderOrder == renderOrder &&
      other.focusOrder == focusOrder &&
      other.motion == motion &&
      other.motionTiming == motionTiming &&
      listEquals(other.tracks, tracks) &&
      _mapEquals(other.stateEffects, stateEffects) &&
      listEquals(other.transitions, transitions) &&
      other.visibleWhen == visibleWhen &&
      other.interactive == interactive &&
      _mapEquals(other.properties, properties);

  @override
  int get hashCode => Object.hashAll([
    id,
    componentId,
    rect,
    parentId,
    layout,
    sizing,
    Object.hashAll(breakpoints),
    styleToken,
    asset,
    primitive,
    transform,
    z,
    renderOrder,
    focusOrder,
    motion,
    motionTiming,
    Object.hashAll(tracks),
    _hashMap(stateEffects),
    Object.hashAll(transitions),
    visibleWhen,
    interactive,
    _hashMap(properties),
  ]);
}

class SceneDocument {
  const SceneDocument({
    required this.id,
    required this.version,
    required this.canvas,
    required this.background,
    required this.nodes,
    this.themeProperties = const {},
    this.styleTokens = const {},
    this.guides = const [],
  });

  final String id;
  final int version;
  final SceneCanvas canvas;
  final SceneBackground background;
  final List<SceneNode> nodes;

  /// Theme-owned preset selections, compiled with the scene so Studio and the
  /// greeter resolve the same layout, palette, material and motion choices.
  final Map<String, String> themeProperties;
  final Map<String, SceneStyle> styleTokens;
  final List<SceneGuide> guides;

  /// Draw order uses renderOrder first and z as its tie-breaker. Focus order is
  /// independent. Sorting a copy preserves the original authoring order.
  List<SceneNode> get paintOrder {
    return [...nodes]..sort((left, right) {
      final byRenderOrder = left.renderOrder.compareTo(right.renderOrder);
      if (byRenderOrder != 0) {
        return byRenderOrder;
      }
      return left.z.compareTo(right.z);
    });
  }

  List<SceneNode> getChildren(String? parentId) =>
      paintOrder.where((node) => node.parentId == parentId).toList();

  /// Depth-first authoring order keeps descendants beside their owning frame.
  List<SceneNode> get layerOrder {
    final result = <SceneNode>[];
    void append(String? parentId) {
      for (final node in getChildren(parentId).reversed) {
        result.add(node);
        append(node.id);
      }
    }

    append(null);
    return result;
  }

  SceneDocument copyWith({
    String? id,
    int? version,
    SceneCanvas? canvas,
    SceneBackground? background,
    List<SceneNode>? nodes,
    Map<String, String>? themeProperties,
    Map<String, SceneStyle>? styleTokens,
    List<SceneGuide>? guides,
  }) {
    return SceneDocument(
      id: id ?? this.id,
      version: version ?? this.version,
      canvas: canvas ?? this.canvas,
      background: background ?? this.background,
      nodes: nodes ?? this.nodes,
      themeProperties: themeProperties ?? this.themeProperties,
      styleTokens: styleTokens ?? this.styleTokens,
      guides: guides ?? this.guides,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SceneDocument &&
      other.id == id &&
      other.version == version &&
      other.canvas == canvas &&
      other.background == background &&
      listEquals(other.nodes, nodes) &&
      _mapEquals(other.themeProperties, themeProperties) &&
      _mapEquals(other.styleTokens, styleTokens) &&
      listEquals(other.guides, guides);

  @override
  int get hashCode => Object.hash(
    id,
    version,
    canvas,
    background,
    Object.hashAll(nodes),
    _hashMap(themeProperties),
    _hashMap(styleTokens),
    Object.hashAll(guides),
  );
}

bool isSceneAssetPath(String path) =>
    !path.contains('..') &&
    !path.contains(r'\') &&
    !path.endsWith('/') &&
    (path.startsWith('assets/') || path.startsWith('packages/'));

double clampSceneKeyframeValue(SceneMotionProperty property, double value) =>
    property == SceneMotionProperty.opacity
    ? value.clamp(0.0, 1.0)
    : value.clamp(-maxSceneKeyframeMagnitude, maxSceneKeyframeMagnitude);

Set<String> getReferencedSceneAssets(SceneDocument document) => {
  if (document.background.asset != null) document.background.asset!,
  if (document.background.shader case final shader?) ...[
    shader.asset,
    for (final texture in shader.textures) texture.asset,
  ],
  for (final value in document.themeProperties.values)
    if (isSceneAssetPath(value)) value,
  for (final style in document.styleTokens.values)
    if (style.fontAsset != null) style.fontAsset!,
  for (final node in document.nodes) ...[
    for (final value in node.properties.values)
      if (isSceneAssetPath(value)) value,
    if (node.asset != null) node.asset!.path,
  ],
};

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

int _hashMap<K, V>(Map<K, V> map) => Object.hashAllUnordered([
  for (final entry in map.entries) Object.hash(entry.key, entry.value),
]);

/// Sentinel for [SceneNode.copyWith] nullable fields that may be cleared.
const Object _unset = Object();
