import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:mozais_scene_schema/mozais_scene_schema.dart';

import '../model/theme_bundle.dart';
import 'builtin_backgrounds.dart';
import 'motion.dart';
import 'node_transform.dart';

typedef SceneNodeBuilder = Widget Function(
  BuildContext context,
  SceneNode node,
);

class SceneRuntime extends StatelessWidget {
  const SceneRuntime({
    required this.document,
    required this.theme,
    required this.nodeBuilder,
    this.activePredicates = const <ScenePredicate>{},
    this.activePredicatesListenable,
    this.backgroundBlurSigma,
    this.prewarmHiddenNodes = false,
    super.key,
  });

  final SceneDocument document;
  final ThemeBundle theme;
  final SceneNodeBuilder nodeBuilder;

  /// Predicates currently true for the scene.
  ///
  /// A node with a non-null [SceneNode.visibleWhen] is present only while its
  /// condition evaluates true against this set.
  final Set<ScenePredicate> activePredicates;

  /// Notifies only affected node hosts when [activePredicates] changes.
  final ValueListenable<Set<ScenePredicate>>? activePredicatesListenable;

  /// Drives an override of the document background's blur when set.
  ///
  /// A host uses this to ramp the frost as the scene becomes active; null
  /// keeps the blur authored in the document.
  final Animation<double>? backgroundBlurSigma;

  /// Builds and lays out hidden nodes before they become visible.
  ///
  /// Hidden nodes remain excluded from pointer, focus, and semantics handling.
  final bool prewarmHiddenNodes;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          fit: StackFit.expand,
          children: [
            _buildBackground(context),
            for (final node in document.paintOrder)
              _buildNode(context, size, node),
          ],
        );
      },
    );
  }

  Widget _buildBackground(BuildContext context) {
    final renderer =
        theme.backgroundRenderer(document.background.kind) ??
        const SolidBackgroundRenderer();
    final blur = backgroundBlurSigma;
    if (blur == null) {
      return RepaintBoundary(
        child: renderer.build(context, document.background),
      );
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: blur,
        builder: (context, child) => renderer.build(
          context,
          document.background.copyWith(blurSigma: blur.value),
        ),
      ),
    );
  }

  Widget _buildNode(BuildContext context, Size size, SceneNode node) {
    final visibleWhen = node.visibleWhen;
    final visible =
        visibleWhen == null ||
        evaluateSceneCondition(visibleWhen, activePredicates);
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final safeArea = document.canvas.useSafeArea
        ? MediaQuery.paddingOf(context)
        : EdgeInsets.zero;
    final rect = sceneNodeRect(
      node: node,
      sceneSize: size,
      safeArea: safeArea,
      minHitTarget: theme.tokens.minHitTarget,
    );

    Widget child = _SceneNodeHost(
      visible: visible,
      activePredicatesListenable: visibleWhen == null
          ? null
          : activePredicatesListenable,
      visibleWhen: visibleWhen,
      prewarmHiddenNodes: prewarmHiddenNodes,
      motionBuilder: theme.motionBuilder(node.motion),
      spec: (
        preset: node.motion,
        duration: reducedMotion ? Duration.zero : theme.tokens.mediumMotion,
        curve: theme.tokens.standardCurve,
        reducedMotion: reducedMotion,
      ),
      builder: (context) =>
          _applyTransform(node, rect.size, nodeBuilder(context, node)),
    );
    if (node.interactive) {
      child = FocusTraversalOrder(
        order: NumericFocusOrder(node.focusOrder.toDouble()),
        child: child,
      );
    }

    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: RepaintBoundary(child: child),
    );
  }

  Widget _applyTransform(SceneNode node, Size size, Widget child) {
    if (node.transform.isIdentity) {
      return child;
    }
    return Transform(
      transform: sceneNodeTransformMatrix(node.transform, size),
      child: child,
    );
  }
}

/// Owns one node's presence lifecycle.
///
/// The controller runs from 0 (hidden) to 1 (shown) and follows [visible].
/// By default, a hidden node is unmounted after its exit transition. Hosts can
/// keep it mounted and laid out to avoid building its subtree on demand.
class _SceneNodeHost extends StatefulWidget {
  const _SceneNodeHost({
    required this.visible,
    required this.activePredicatesListenable,
    required this.visibleWhen,
    required this.prewarmHiddenNodes,
    required this.motionBuilder,
    required this.spec,
    required this.builder,
  });

  final bool visible;
  final ValueListenable<Set<ScenePredicate>>? activePredicatesListenable;
  final SceneCondition? visibleWhen;
  final bool prewarmHiddenNodes;
  final SceneMotionBuilder? motionBuilder;
  final SceneMotionSpec spec;
  final WidgetBuilder builder;

  @override
  State<_SceneNodeHost> createState() => _SceneNodeHostState();
}

class _SceneNodeHostState extends State<_SceneNodeHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _progress;
  late bool _visible;
  Widget? _prewarmedChild;

  bool get _animates =>
      widget.motionBuilder != null &&
      widget.motionBuilder!.animatesPresence &&
      widget.spec.preset != SceneMotionPreset.none &&
      !widget.spec.reducedMotion;

  @override
  void initState() {
    super.initState();
    _visible = widget.visible;
    widget.activePredicatesListenable?.addListener(
      _handleActivePredicatesChanged,
    );
    _controller = AnimationController(
      vsync: this,
      duration: widget.spec.duration,
    );
    _progress = _controller.drive(CurveTween(curve: widget.spec.curve));
    _controller.addStatusListener(_handleStatus);
    if (widget.visible) {
      if (_animates) {
        _controller.forward();
      } else {
        _controller.value = 1;
      }
    }
  }

  @override
  void didUpdateWidget(_SceneNodeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.builder != oldWidget.builder) {
      _prewarmedChild = null;
    }
    if (widget.activePredicatesListenable !=
        oldWidget.activePredicatesListenable) {
      oldWidget.activePredicatesListenable?.removeListener(
        _handleActivePredicatesChanged,
      );
      widget.activePredicatesListenable?.addListener(
        _handleActivePredicatesChanged,
      );
    }
    if (widget.spec.curve != oldWidget.spec.curve) {
      _progress = _controller.drive(CurveTween(curve: widget.spec.curve));
    }
    if (widget.spec.duration != oldWidget.spec.duration) {
      _controller.duration = widget.spec.duration;
    }
    final predicates = widget.activePredicatesListenable;
    final condition = widget.visibleWhen;
    final nextVisible = predicates != null && condition != null
        ? evaluateSceneCondition(condition, predicates.value)
        : widget.visible;
    if (nextVisible != _visible) {
      _setVisible(nextVisible);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _prewarmedChild = null;
  }

  void _handleActivePredicatesChanged() {
    final condition = widget.visibleWhen;
    if (condition == null) {
      return;
    }
    final visible = evaluateSceneCondition(
      condition,
      widget.activePredicatesListenable!.value,
    );
    if (visible != _visible) {
      setState(() => _setVisible(visible));
    }
  }

  void _setVisible(bool visible) {
    _visible = visible;
    if (!_animates) {
      _controller.value = visible ? 1 : 0;
    } else if (visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed &&
        !_visible &&
        !widget.prewarmHiddenNodes) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    widget.activePredicatesListenable?.removeListener(
      _handleActivePredicatesChanged,
    );
    _controller.removeStatusListener(_handleStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_animates) {
      if (_visible) {
        return _buildChild(context);
      }
      if (!widget.prewarmHiddenNodes) {
        return const SizedBox.shrink();
      }
      return _hideFromInteraction(
        Opacity(opacity: 0, child: _buildChild(context)),
      );
    }
    if (!_visible &&
        _controller.status == AnimationStatus.dismissed &&
        !widget.prewarmHiddenNodes) {
      return const SizedBox.shrink();
    }
    final animated = widget.motionBuilder!.build(
      context,
      widget.spec,
      _progress,
      _buildChild(context),
    );
    if (_visible) {
      return animated;
    }
    return _hideFromInteraction(animated);
  }

  Widget _hideFromInteraction(Widget child) {
    return IgnorePointer(
      child: ExcludeFocus(child: ExcludeSemantics(child: child)),
    );
  }

  Widget _buildChild(BuildContext context) {
    if (!widget.prewarmHiddenNodes) {
      return widget.builder(context);
    }
    return _prewarmedChild ??= widget.builder(context);
  }
}
