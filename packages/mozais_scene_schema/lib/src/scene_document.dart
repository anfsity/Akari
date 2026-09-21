enum SceneCanvasFit { cover, contain, reflow }

enum SceneNodeKind {
  background,
  glassPanel,
  avatar,
  accountName,
  accountPicker,
  sessionPicker,
  credentialField,
  primaryAction,
  secondaryAction,
  powerActions,
  dateTime,
  status,
  decoration,
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
}

final class SceneAll extends SceneCondition {
  const SceneAll(this.conditions);

  final List<SceneCondition> conditions;
}

final class SceneAny extends SceneCondition {
  const SceneAny(this.conditions);

  final List<SceneCondition> conditions;
}

final class SceneNot extends SceneCondition {
  const SceneNot(this.condition);

  final SceneCondition condition;
}

/// Evaluates [condition] against the predicates currently true for the scene.
bool evaluateSceneCondition(
  SceneCondition condition,
  Set<ScenePredicate> activePredicates,
) {
  return switch (condition) {
    ScenePredicateCondition(:final predicate) =>
      activePredicates.contains(predicate),
    SceneAll(:final conditions) => conditions.every(
      (condition) => evaluateSceneCondition(condition, activePredicates),
    ),
    SceneAny(:final conditions) => conditions.any(
      (condition) => evaluateSceneCondition(condition, activePredicates),
    ),
    SceneNot(:final condition) =>
      !evaluateSceneCondition(condition, activePredicates),
  };
}

enum SceneAction {
  selectUser,
  selectSession,
  beginAuthentication,
  respondToPrompt,
  cancelAuthentication,
  requestPowerAction,
  retryAuthentication,
  retryPrompt,
  reconnectService,
  retrySessionCatalog,
}

enum SceneMotionPreset {
  none,
  fade,
  fadeSlide,
  fadeScale,
  hoverLift,
  focusGlow,
}

enum SceneBackgroundKind { image, solid, video, custom }

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
}

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
}

class SceneCanvas {
  const SceneCanvas({this.fit = SceneCanvasFit.cover, this.useSafeArea = true});

  final SceneCanvasFit fit;
  final bool useSafeArea;
}

class SceneBackground {
  const SceneBackground({
    required this.kind,
    this.asset,
    this.color = 0xff0d151a,
    this.scrimOpacity = 0.35,
    this.blurSigma = 0,
    this.rendererId,
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

  SceneBackground copyWith({
    SceneBackgroundKind? kind,
    String? asset,
    int? color,
    double? scrimOpacity,
    double? blurSigma,
    String? rendererId,
  }) {
    return SceneBackground(
      kind: kind ?? this.kind,
      asset: asset ?? this.asset,
      color: color ?? this.color,
      scrimOpacity: scrimOpacity ?? this.scrimOpacity,
      blurSigma: blurSigma ?? this.blurSigma,
      rendererId: rendererId ?? this.rendererId,
    );
  }
}

class SceneNode {
  const SceneNode({
    required this.id,
    required this.kind,
    required this.rect,
    this.transform = const SceneTransform(),
    this.z = 0,
    this.renderOrder = 0,
    this.focusOrder = 0,
    this.motion = SceneMotionPreset.none,
    this.visibleWhen,
    this.action,
    this.properties = const <String, String>{},
  });

  final String id;
  final SceneNodeKind kind;
  final SceneRect rect;
  final SceneTransform transform;
  final int z;
  final int renderOrder;
  final int focusOrder;
  final SceneMotionPreset motion;

  /// Condition controlling whether the node is present; null means always.
  final SceneCondition? visibleWhen;

  final SceneAction? action;
  final Map<String, String> properties;

  bool get isInteractive =>
      action != null ||
      kind == SceneNodeKind.accountPicker ||
      kind == SceneNodeKind.sessionPicker ||
      kind == SceneNodeKind.credentialField ||
      kind == SceneNodeKind.primaryAction ||
      kind == SceneNodeKind.secondaryAction ||
      kind == SceneNodeKind.powerActions;
}

class SceneDocument {
  const SceneDocument({
    required this.id,
    required this.version,
    required this.canvas,
    required this.background,
    required this.nodes,
  });

  final String id;
  final int version;
  final SceneCanvas canvas;
  final SceneBackground background;
  final List<SceneNode> nodes;

  List<SceneNode> get paintOrder {
    final ordered = [...nodes]
      ..sort((left, right) {
        final byRenderOrder = left.renderOrder.compareTo(right.renderOrder);
        if (byRenderOrder != 0) {
          return byRenderOrder;
        }
        return left.z.compareTo(right.z);
      });
    return ordered;
  }
}
