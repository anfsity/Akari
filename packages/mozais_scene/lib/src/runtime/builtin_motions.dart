import 'package:flutter/material.dart';
import 'package:mozais_scene_schema/mozais_scene_schema.dart';

import 'motion.dart';

class FadeMotionBuilder extends SceneMotionBuilder {
  const FadeMotionBuilder();

  @override
  Widget build(
    BuildContext context,
    SceneMotionSpec spec,
    Animation<double> progress,
    Widget child,
  ) {
    if (spec.reducedMotion || spec.preset == SceneMotionPreset.none) {
      return child;
    }
    return FadeTransition(opacity: progress, child: child);
  }
}

class FadeSlideMotionBuilder extends SceneMotionBuilder {
  const FadeSlideMotionBuilder();

  @override
  Widget build(
    BuildContext context,
    SceneMotionSpec spec,
    Animation<double> progress,
    Widget child,
  ) {
    if (spec.reducedMotion || spec.preset == SceneMotionPreset.none) {
      return child;
    }
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) => Opacity(
        opacity: progress.value,
        child: Transform.translate(
          offset: Offset(0, (1 - progress.value) * 16),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class FadeScaleMotionBuilder extends SceneMotionBuilder {
  const FadeScaleMotionBuilder();

  @override
  Widget build(
    BuildContext context,
    SceneMotionSpec spec,
    Animation<double> progress,
    Widget child,
  ) {
    if (spec.reducedMotion || spec.preset == SceneMotionPreset.none) {
      return child;
    }
    return FadeTransition(
      opacity: progress,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(progress),
        child: child,
      ),
    );
  }
}

class HoverLiftMotionBuilder extends SceneMotionBuilder {
  const HoverLiftMotionBuilder();

  @override
  bool get animatesPresence => false;

  @override
  Widget build(
    BuildContext context,
    SceneMotionSpec spec,
    Animation<double> progress,
    Widget child,
  ) {
    if (spec.reducedMotion) {
      return child;
    }
    return _HoverLift(spec: spec, child: child);
  }
}

class FocusGlowMotionBuilder extends SceneMotionBuilder {
  const FocusGlowMotionBuilder();

  @override
  bool get animatesPresence => false;

  @override
  Widget build(
    BuildContext context,
    SceneMotionSpec spec,
    Animation<double> progress,
    Widget child,
  ) {
    if (spec.reducedMotion) {
      return child;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary
                .withValues(alpha: 0.18),
            blurRadius: 18,
          ),
        ],
      ),
      child: child,
    );
  }
}

class _HoverLift extends StatefulWidget {
  const _HoverLift({required this.spec, required this.child});

  final SceneMotionSpec spec;
  final Widget child;

  @override
  State<_HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<_HoverLift> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.02 : 1,
        duration: widget.spec.duration,
        curve: widget.spec.curve,
        child: widget.child,
      ),
    );
  }
}
