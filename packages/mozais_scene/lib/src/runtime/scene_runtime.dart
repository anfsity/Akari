import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/scene_document.dart';
import '../model/theme_bundle.dart';
import 'builtin_backgrounds.dart';

typedef SceneNodeBuilder = Widget Function(
  BuildContext context,
  SceneNode node,
);

class SceneRuntime extends StatelessWidget {
  const SceneRuntime({
    required this.document,
    required this.theme,
    required this.nodeBuilder,
    this.backgroundBlurSigma,
    super.key,
  });

  final SceneDocument document;
  final ThemeBundle theme;
  final SceneNodeBuilder nodeBuilder;

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

    Widget child = nodeBuilder(context, node);
    child = _applyTransform(node, child);
    child = _applyMotion(context, node, child);
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

  Widget _applyMotion(BuildContext context, SceneNode node, Widget child) {
    final builder = theme.motionBuilder(node.motion);
    if (builder == null) {
      return child;
    }
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return builder.build(
      context,
      (
        preset: node.motion,
        duration: reducedMotion ? Duration.zero : theme.tokens.mediumMotion,
        curve: theme.tokens.standardCurve,
        reducedMotion: reducedMotion,
      ),
      child,
    );
  }
}
