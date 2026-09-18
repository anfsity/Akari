import 'dart:ui';

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

enum SceneBinding {
  serviceMode,
  authMode,
  authPrompt,
  authError,
  accountUsers,
  accountSelected,
  sessionMode,
  sessionSessions,
  sessionSelected,
  continueEnabled,
  powerMode,
  powerError,
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
    this.color = const Color(0xff0d151a),
    this.scrimOpacity = 0.35,
    this.rendererId,
  });

  final SceneBackgroundKind kind;
  final String? asset;
  final Color color;
  final double scrimOpacity;
  final String? rendererId;
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
    this.bindings = const <SceneBinding>{},
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
  final Set<SceneBinding> bindings;
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
