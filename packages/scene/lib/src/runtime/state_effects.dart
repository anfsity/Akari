import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:scene_schema/scene_schema.dart';

import 'motion.dart';

/// Visual responses observe semantic state; they never own authentication
/// transitions. A controller is allocated only after a rule actually fires.
class SceneStateEffects extends StatefulWidget {
  const SceneStateEffects({
    required this.node,
    required this.activePredicates,
    required this.predicatesListenable,
    required this.duration,
    required this.curve,
    required this.playback,
    required this.child,
    super.key,
  });
  final SceneNode node;
  final Set<ScenePredicate> activePredicates;
  final ValueListenable<Set<ScenePredicate>>? predicatesListenable;
  final Duration duration;
  final Curve curve;
  final ScenePlayback? playback;
  final Widget child;
  @override
  State<SceneStateEffects> createState() => _SceneStateEffectsState();
}

class _SceneStateEffectsState extends State<SceneStateEffects>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  SceneStateEffect _effect = SceneStateEffect.shake;
  Set<ScenePredicate> _previous = {};
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    widget.predicatesListenable?.addListener(_updatePredicates);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    _updatePredicates();
  }

  @override
  void didUpdateWidget(SceneStateEffects old) {
    super.didUpdateWidget(old);
    if (old.predicatesListenable != widget.predicatesListenable) {
      old.predicatesListenable?.removeListener(_updatePredicates);
      widget.predicatesListenable?.addListener(_updatePredicates);
    }
    if (!mapEquals(old.node.stateEffects, widget.node.stateEffects)) {
      _previous = {};
    }
    _controller?.duration = getSceneMotionDuration(
      widget.node,
      widget.duration,
    );
    _updatePredicates();
  }

  void _updatePredicates() {
    final predicates =
        widget.predicatesListenable?.value ?? widget.activePredicates;
    if (_reduced ||
        widget.playback != null ||
        widget.node.stateEffects.isEmpty) {
      _controller?.stop();
      _controller?.value = 1;
    } else {
      final triggered = widget.node.stateEffects.entries
          .where(
            (rule) =>
                predicates.contains(rule.key) && !_previous.contains(rule.key),
          )
          .lastOrNull;
      if (triggered != null) {
        _effect = triggered.value;
        final needsListener = _controller == null;
        final controller = _controller ??= AnimationController(vsync: this);
        controller.duration = getSceneMotionDuration(
          widget.node,
          widget.duration,
        );
        controller.forward(from: 0);
        if (needsListener) setState(() {});
      }
    }
    _previous = Set.of(predicates);
  }

  @override
  void dispose() {
    widget.predicatesListenable?.removeListener(_updatePredicates);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller ?? const AlwaysStoppedAnimation(1.0),
    child: widget.child,
    builder: (context, child) {
      var progress = _reduced ? 1.0 : _controller?.value ?? 1.0;
      var effect = _effect;
      if (widget.playback case final playback?) {
        final triggered = widget.node.stateEffects.entries
            .where(
              (rule) =>
                  widget.activePredicates.contains(rule.key) &&
                  !playback.from.contains(rule.key),
            )
            .lastOrNull;
        if (!_reduced && triggered != null) {
          effect = triggered.value;
          final duration = getSceneMotionDuration(
            widget.node,
            widget.duration,
          ).inMicroseconds;
          progress = duration == 0
              ? 1
              : (playback.elapsed.inMicroseconds / duration).clamp(0.0, 1.0);
        } else {
          progress = 1;
        }
      }
      progress = getSceneMotionCurve(
        widget.node,
        widget.duration,
        widget.curve,
      ).transform(progress);
      final matrix = Matrix4.identity();
      if (effect == SceneStateEffect.shake) {
        matrix.translateByDouble(
          math.sin(progress * math.pi * 8) * (1 - progress) * 12,
          0,
          0,
          1,
        );
      } else {
        final scale = 1 + math.sin(progress * math.pi) * .04;
        matrix.scaleByDouble(scale, scale, 1, 1);
      }
      return Transform(
        transform: matrix,
        alignment: Alignment.center,
        child: child,
      );
    },
  );
}
