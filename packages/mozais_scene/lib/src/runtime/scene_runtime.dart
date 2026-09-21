import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/scene_document.dart';
import '../model/theme_bundle.dart';
import 'builtin_backgrounds.dart';
import 'motion.dart';

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
    final availableWidth = math.max(0, size.width - safeArea.horizontal);
    final availableHeight = math.max(0, size.height - safeArea.vertical);

    var width = availableWidth * node.rect.width;
    var height = availableHeight * node.rect.height;
    final left = safeArea.left + availableWidth * node.rect.x;
    final top = safeArea.top + availableHeight * node.rect.y;

    if (node.isInteractive) {
      width = math.max(width, theme.tokens.minHitTarget);
      height = math.max(height, theme.tokens.minHitTarget);
    }

    Widget child = _SceneNodeHost(
      visible: visible,
      motionBuilder: theme.motionBuilder(node.motion),
      spec: (
        preset: node.motion,
        duration: reducedMotion ? Duration.zero : theme.tokens.mediumMotion,
        curve: theme.tokens.standardCurve,
        reducedMotion: reducedMotion,
      ),
      builder: (context) => _applyTransform(node, nodeBuilder(context, node)),
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
      left: left,
      top: top,
      width: width,
      height: height,
      child: child,
    );
  }

  Widget _applyTransform(SceneNode node, Widget child) {
    if (node.transform.isIdentity) {
      return child;
    }

    final transform = node.transform;
    final maxRotation = theme.tokens.maxInteractiveRotationDegrees;
    final rotationX = node.isInteractive
        ? transform.rotationX.clamp(-maxRotation, maxRotation)
        : transform.rotationX;
    final rotationY = node.isInteractive
        ? transform.rotationY.clamp(-maxRotation, maxRotation)
        : transform.rotationY;
    final rotationZ = node.isInteractive
        ? transform.rotationZ.clamp(-maxRotation, maxRotation)
        : transform.rotationZ;

    final matrix = Matrix4.identity()
      ..translateByDouble(transform.translateX, transform.translateY, 0, 1)
      ..scaleByDouble(transform.scaleX, transform.scaleY, 1, 1)
      ..rotateX(rotationX * math.pi / 180)
      ..rotateY(rotationY * math.pi / 180)
      ..rotateZ(rotationZ * math.pi / 180);

    if (transform.perspective != 0) {
      matrix.setEntry(3, 2, transform.perspective);
    }

    return Transform(
      transform: matrix,
      alignment: Alignment(transform.pivotX * 2 - 1, transform.pivotY * 2 - 1),
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
