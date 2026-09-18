import 'package:flutter/material.dart';

import '../model/scene_document.dart';
import 'motion.dart';

class FadeMotionBuilder extends SceneMotionBuilder {
  const FadeMotionBuilder();

  @override
  Widget build(BuildContext context, SceneMotionSpec spec, Widget child) {
    if (spec.reducedMotion || spec.preset == SceneMotionPreset.none) {
      return child;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: spec.duration,
      curve: spec.curve,
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: child,
    );
  }
}

class FadeSlideMotionBuilder extends SceneMotionBuilder {
  const FadeSlideMotionBuilder();

  @override
  Widget build(BuildContext context, SceneMotionSpec spec, Widget child) {
    if (spec.reducedMotion || spec.preset == SceneMotionPreset.none) {
      return child;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: spec.duration,
      curve: spec.curve,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * 16),
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
  Widget build(BuildContext context, SceneMotionSpec spec, Widget child) {
    if (spec.reducedMotion || spec.preset == SceneMotionPreset.none) {
      return child;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.96, end: 1),
      duration: spec.duration,
      curve: spec.curve,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.scale(scale: value, child: child),
      ),
      child: child,
    );
  }
}

class HoverLiftMotionBuilder extends SceneMotionBuilder {
  const HoverLiftMotionBuilder();

  @override
  Widget build(BuildContext context, SceneMotionSpec spec, Widget child) {
    if (spec.reducedMotion) {
      return child;
    }
    return _HoverLift(spec: spec, child: child);
  }
}

class FocusGlowMotionBuilder extends SceneMotionBuilder {
  const FocusGlowMotionBuilder();

  @override
  Widget build(BuildContext context, SceneMotionSpec spec, Widget child) {
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
