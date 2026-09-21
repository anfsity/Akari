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
    this.backgroundBlurSigma,
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

  /// Drives an override of the document background's blur when set.
  ///
  /// A host uses this to ramp the frost as the scene becomes active; null
  /// keeps the blur authored in the document.
  final Animation<double>? backgroundBlurSigma;

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
    if (node.motion != SceneMotionPreset.none) {
      child = RepaintBoundary(child: child);
    }

    if (node.isInteractive) {
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
      child: child,
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
/// When the node leaves the scene the runtime keeps it mounted until the exit
/// transition settles, then unmounts it so stateful content such as the clock
/// timer stops.
class _SceneNodeHost extends StatefulWidget {
  const _SceneNodeHost({
    required this.visible,
    required this.motionBuilder,
    required this.spec,
    required this.builder,
  });

  final bool visible;
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

  bool get _animates =>
      widget.motionBuilder != null &&
      widget.motionBuilder!.animatesPresence &&
      widget.spec.preset != SceneMotionPreset.none &&
      !widget.spec.reducedMotion;

  @override
  void initState() {
    super.initState();
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
    if (widget.spec.curve != oldWidget.spec.curve) {
      _progress = _controller.drive(CurveTween(curve: widget.spec.curve));
    }
    if (widget.spec.duration != oldWidget.spec.duration) {
      _controller.duration = widget.spec.duration;
    }
    if (widget.visible != oldWidget.visible) {
      if (!_animates) {
        _controller.value = widget.visible ? 1 : 0;
      } else if (widget.visible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !widget.visible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_animates) {
      return widget.visible ? widget.builder(context) : const SizedBox.shrink();
    }
    if (!widget.visible && _controller.status == AnimationStatus.dismissed) {
      return const SizedBox.shrink();
    }
    final animated = widget.motionBuilder!.build(
      context,
      widget.spec,
      _progress,
      widget.builder(context),
    );
    if (widget.visible) {
      return animated;
    }
    return IgnorePointer(child: ExcludeFocus(child: animated));
  }
}
