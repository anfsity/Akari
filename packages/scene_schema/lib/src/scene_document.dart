import 'collections.dart';
import 'scene_condition.dart';
import 'scene_layout.dart';
import 'scene_motion.dart';
import 'scene_shader.dart';
import 'scene_style.dart';

enum SceneCanvasFit { cover, contain, reflow }

const currentSceneVersion = 3;

enum SceneGuideAxis { horizontal, vertical }

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

enum SceneBackgroundKind { image, solid, video, custom }

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
      mapEquals(other.parameters, parameters) &&
      other.shader == shader;

  @override
  int get hashCode => Object.hash(
    kind,
    asset,
    color,
    scrimOpacity,
    blurSigma,
    rendererId,
    hashMap(parameters),
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
      mapEquals(other.stateEffects, stateEffects) &&
      listEquals(other.transitions, transitions) &&
      other.visibleWhen == visibleWhen &&
      other.interactive == interactive &&
      mapEquals(other.properties, properties);

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
    hashMap(stateEffects),
    Object.hashAll(transitions),
    visibleWhen,
    interactive,
    hashMap(properties),
  ]);
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
      mapEquals(other.themeProperties, themeProperties) &&
      mapEquals(other.styleTokens, styleTokens) &&
      listEquals(other.guides, guides);

  @override
  int get hashCode => Object.hash(
    id,
    version,
    canvas,
    background,
    Object.hashAll(nodes),
    hashMap(themeProperties),
    hashMap(styleTokens),
    Object.hashAll(guides),
  );
}

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

/// Sentinel for [SceneNode.copyWith] nullable fields that may be cleared.
const Object _unset = Object();
