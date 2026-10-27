import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:scene_schema/scene_schema.dart';

import '../model/theme_bundle.dart';
import 'builtin_backgrounds.dart';
import 'motion.dart';
import 'node_transform.dart';
import 'scene_layout.dart';
import 'node_style.dart';
import 'state_effects.dart';
import 'scene_asset.dart';
import 'scene_font.dart';
import 'background_renderer.dart';

typedef SceneNodeBuilder = Widget Function(
  BuildContext context,
  SceneNode node,
);

typedef SceneFrameBuilder = Widget Function(
  BuildContext context,
  SceneNode node,
  Widget child,
);

/// Executes an authored document using compiled renderers and components.
///
/// Layout and presence belong here; authentication and component content do
/// not. Each node has a paint boundary and a local presence host so motion or
/// visibility changes can update independently of the rest of the scene.
class SceneRuntime extends StatelessWidget {
  const SceneRuntime({
    required this.document,
    required this.theme,
    required this.nodeBuilder,
    this.frameBuilder,
    this.playback,
    this.contentDecorator,
    this.assetImageResolver,
    this.assetSvgLoader,
    this.assetFontLoader,
    this.activePredicates = const <ScenePredicate>{},
    this.activePredicatesListenable,
    this.backgroundBlurSigma,
    this.prewarmHiddenNodes = false,
    super.key,
  });

  final SceneDocument document;
  final ThemeBundle theme;
  final SceneNodeBuilder nodeBuilder;
  final SceneFrameBuilder? frameBuilder;
  final ScenePlayback? playback;
  final SceneFrameBuilder? contentDecorator;
  final SceneImageProviderResolver? assetImageResolver;
  final SceneSvgLoader? assetSvgLoader;
  final SceneFontLoader? assetFontLoader;

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
  /// Their state and subscriptions remain alive, trading resource use while
  /// hidden for lower latency when they first appear.
  final bool prewarmHiddenNodes;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations:
            theme.tokens.disableAnimations ||
            MediaQuery.disableAnimationsOf(context),
      ),
      child: ValueListenableBuilder<Map<String, String>>(
        valueListenable: sceneFontFamilies,
        builder: (context, fonts, _) => LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final geometry = calculateSceneLayout(
              document: document,
              size: size,
              fontFamilies: fonts,
              safeArea: MediaQuery.paddingOf(context),
              minHitTarget: theme.tokens.minHitTarget,
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                _buildBackground(context),
                for (final node in document.getChildren(null))
                  _buildNode(context, geometry, node),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBackground(BuildContext context) {
    final renderer =
        theme.backgrounds[document.background.kind] ??
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

  Widget _buildNode(
    BuildContext context,
    Map<String, SceneNodeGeometry> geometry,
    SceneNode node,
  ) {
    node = geometry[node.id]!.node;
    final visibleWhen = node.visibleWhen;
    final visible =
        visibleWhen == null ||
        evaluateSceneCondition(visibleWhen, activePredicates);
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final layout = node.layout;
    final asset = node.asset;
    final duration = reducedMotion
        ? Duration.zero
        : Duration(
            milliseconds:
                node.motionTiming.durationMs ??
                theme.tokens.mediumMotion.inMilliseconds,
          );
    final curve = getSceneMotionCurve(
      node,
      duration,
      theme.tokens.standardCurve,
    );
    final motion = theme.motions[node.motion];
    double? previewProgress;
    if (playback case final playback?) {
      final before =
          !playback.enterAll &&
          (visibleWhen == null ||
              evaluateSceneCondition(visibleWhen, playback.from));
      if (before == visible ||
          reducedMotion ||
          motion == null ||
          !motion.animatesPresence ||
          node.motion == SceneMotionPreset.none) {
        previewProgress = visible ? 1 : 0;
      } else {
        final total = getSceneMotionDuration(node, duration).inMicroseconds;
        final time = total == 0
            ? 1.0
            : (playback.elapsed.inMicroseconds / total).clamp(0.0, 1.0);
        previewProgress = curve.transform(visible ? time : 1 - time);
      }
    }
    final SceneNodeBuilder contentBuilder;
    if (layout != null) {
      contentBuilder = (context, node) {
        final child = Stack(
          fit: StackFit.expand,
          clipBehavior: layout.clip ? Clip.hardEdge : Clip.none,
          children: [
            for (final child in document.getChildren(node.id))
              _buildNode(context, geometry, child),
          ],
        );
        return frameBuilder?.call(context, node, child) ?? child;
      };
    } else if (asset != null) {
      contentBuilder = (context, node) {
        final child = SceneAssetView(
          asset: asset,
          resolveImage: assetImageResolver,
          loadSvg: assetSvgLoader,
        );
        return contentDecorator?.call(context, node, child) ?? child;
      };
    } else if (node.primitive case final primitive?) {
      contentBuilder = (context, node) {
        final child = primitive == ScenePrimitive.text
            ? Align(
                alignment: Alignment.topLeft,
                child: Text(
                  node.properties['text'] ?? 'Text',
                  style: TextStyle(
                    fontSize:
                        document.styleTokens[node.styleToken]?.fontSize == 0 ||
                            document.styleTokens[node.styleToken] == null
                        ? 14
                        : document.styleTokens[node.styleToken]!.fontSize,
                  ),
                ),
              )
            : const SizedBox.expand();
        return contentDecorator?.call(context, node, child) ?? child;
      };
    } else {
      contentBuilder = nodeBuilder;
    }
    final content = _SceneNodeHost(
      previewProgress: previewProgress,
      playbackElapsed: playback?.elapsed,
      visible: visible,
      activePredicatesListenable: visibleWhen == null
          ? null
          : activePredicatesListenable,
      visibleWhen: visibleWhen,
      prewarmHiddenNodes: prewarmHiddenNodes,
      motionBuilder: motion,
      spec: (
        preset: node.motion,
        duration: duration,
        curve: theme.tokens.standardCurve,
        reducedMotion: reducedMotion,
      ),
      node: node,
      style: document.styleTokens[node.styleToken] ?? const SceneStyle(),
      nodeBuilder: contentBuilder,
      loadFont: assetFontLoader,
    );

    final rect = geometry[node.id]!.rect;
    final contentBoundary = RepaintBoundary(
      child: SceneStateEffects(
        node: node,
        activePredicates: activePredicates,
        predicatesListenable:
            node.stateEffects.isEmpty && node.transitions.isEmpty
            ? null
            : activePredicatesListenable,
        duration: duration,
        curve: theme.tokens.standardCurve,
        playback: playback,
        child: node.interactive
            // Keyboard order is authored separately from paint order; raising a
            // visual layer must not silently reorder navigation between controls.
            ? FocusTraversalOrder(
                order: NumericFocusOrder(node.focusOrder.toDouble()),
                child: content,
              )
            : content,
      ),
    );
    // Keep the subtree mounted when a live edit leaves or returns to identity.
    // Adding/removing this wrapper would reset component state and active drags.
    return Positioned(
      key: _SceneNodeKey(node.id),
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Transform(
        transform: sceneNodeTransformMatrix(node.transform, rect.size),
        child: contentBoundary,
      ),
    );
  }
}

class _SceneNodeKey extends LocalKey {
  const _SceneNodeKey(this.nodeId);

  final String nodeId;

  @override
  bool operator ==(Object other) =>
      other is _SceneNodeKey && other.nodeId == nodeId;

  @override
  int get hashCode => nodeId.hashCode;
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
    required this.node,
    required this.style,
    required this.previewProgress,
    required this.playbackElapsed,
    required this.nodeBuilder,
    required this.loadFont,
  });

  final bool visible;
  final ValueListenable<Set<ScenePredicate>>? activePredicatesListenable;
  final SceneCondition? visibleWhen;
  final bool prewarmHiddenNodes;
  final SceneMotionBuilder? motionBuilder;
  final SceneMotionSpec spec;
  final SceneNode node;
  final SceneStyle style;
  final SceneFontLoader? loadFont;
  final double? previewProgress;
  final Duration? playbackElapsed;
  final SceneNodeBuilder nodeBuilder;

  @override
  State<_SceneNodeHost> createState() => _SceneNodeHostState();
}

class _SceneNodeHostState extends State<_SceneNodeHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _progress;
  late bool _visible;
  Widget? _prewarmedChild;

  bool get _animatesPresence =>
      !widget.spec.reducedMotion &&
      (widget.node.tracks.isNotEmpty ||
          (widget.motionBuilder != null &&
              widget.motionBuilder!.animatesPresence &&
              widget.spec.preset != SceneMotionPreset.none));

  @override
  void initState() {
    super.initState();
    _visible = widget.visible;
    widget.activePredicatesListenable?.addListener(
      _handleActivePredicatesChanged,
    );
    _controller = AnimationController(
      vsync: this,
      duration: getSceneMotionDuration(widget.node, widget.spec.duration),
    );
    _progress = _controller.drive(
      CurveTween(
        curve: getSceneMotionCurve(
          widget.node,
          widget.spec.duration,
          widget.spec.curve,
        ),
      ),
    );
    _controller.addStatusListener(_handleStatus);
    if (widget.visible) {
      if (_animatesPresence && widget.previewProgress == null) {
        _controller.forward();
      } else {
        _controller.value = 1;
      }
    }
  }

  @override
  void didUpdateWidget(_SceneNodeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.nodeBuilder != oldWidget.nodeBuilder ||
        !identical(widget.node, oldWidget.node)) {
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
    if (widget.spec.curve != oldWidget.spec.curve ||
        (widget.node.motionTiming != oldWidget.node.motionTiming ||
            widget.node.tracks != oldWidget.node.tracks)) {
      _progress = _controller.drive(
        CurveTween(
          curve: getSceneMotionCurve(
            widget.node,
            widget.spec.duration,
            widget.spec.curve,
          ),
        ),
      );
    }
    if (widget.spec.duration != oldWidget.spec.duration ||
        (widget.node.motionTiming != oldWidget.node.motionTiming ||
            widget.node.tracks != oldWidget.node.tracks)) {
      _controller.duration = getSceneMotionDuration(
        widget.node,
        widget.spec.duration,
      );
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
    // Reuse the current controller value on reversal. Restarting at an endpoint
    // would jump when a new predicate update interrupts an enter or exit.
    if (!_animatesPresence || widget.previewProgress != null) {
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
      // Dismissal can occur while another lifecycle method is building. The
      // next frame removes the exited subtree without mutating that build.
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
    if (widget.previewProgress case final progress?) {
      if (progress == 0) return const SizedBox.shrink();
      final child = _buildChild(context);
      final motion = widget.motionBuilder;
      return IgnorePointer(
        child: ExcludeFocus(
          child: motion != null && _animatesPresence
              ? motion.build(
                  context,
                  widget.spec,
                  AlwaysStoppedAnimation(progress),
                  child,
                )
              : child,
        ),
      );
    }
    if (!_visible &&
        !widget.prewarmHiddenNodes &&
        (!_animatesPresence ||
            _controller.status == AnimationStatus.dismissed)) {
      return const SizedBox.shrink();
    }
    final child = _buildChild(context);
    final motionBuilder = widget.motionBuilder;
    // Interaction effects still wrap nodes whose presence changes immediately.
    final animated =
        motionBuilder != null &&
            widget.spec.preset != SceneMotionPreset.none &&
            !widget.spec.reducedMotion
        ? motionBuilder.build(context, widget.spec, _progress, child)
        : child;
    // Exiting nodes remain visible until motion settles, but stop accepting
    // input immediately. Keep these wrappers mounted on both sides of the
    // transition: removing them would discard prewarmed component state and
    // rebuild input, focus and menu subtrees on every wake.
    return IgnorePointer(
      ignoring: !_visible,
      child: ExcludeFocus(
        excluding: !_visible,
        child: ExcludeSemantics(
          excluding: !_visible,
          child: _animatesPresence
              ? animated
              : Opacity(opacity: _visible ? 1 : 0, child: animated),
        ),
      ),
    );
  }

  Widget _buildChild(BuildContext context) {
    // Cache the widget configuration across presence changes. Its own slot
    // listeners still rebuild content; builder or inherited dependency changes
    // invalidate this cache in the lifecycle hooks above.
    final child = widget.prewarmHiddenNodes
        ? (_prewarmedChild ??= widget.nodeBuilder(context, widget.node))
        : widget.nodeBuilder(context, widget.node);
    final styled = SceneStyleView(
      style: widget.style,
      loadFont: widget.loadFont,
      shape: widget.node.primitive == ScenePrimitive.circle
          ? BoxShape.circle
          : BoxShape.rectangle,
      child: child,
    );
    if (widget.node.tracks.isEmpty) return styled;
    return AnimatedBuilder(
      animation: _controller,
      child: styled,
      builder: (context, child) {
        final elapsed = widget.spec.reducedMotion
            ? getSceneMotionDuration(widget.node, widget.spec.duration)
            : widget.playbackElapsed ??
                  Duration(
                    microseconds:
                        (_controller.value *
                                _controller.duration!.inMicroseconds)
                            .round(),
                  );
        final time =
            elapsed - Duration(milliseconds: widget.node.motionTiming.delayMs);
        var opacity = 1.0;
        var x = 0.0;
        var y = 0.0;
        var scale = 1.0;
        var rotation = 0.0;
        for (final track in widget.node.tracks) {
          final value = calculateSceneTrackValue(track, time);
          switch (track.property) {
            case SceneMotionProperty.opacity:
              opacity = value;
            case SceneMotionProperty.translateX:
              x = value;
            case SceneMotionProperty.translateY:
              y = value;
            case SceneMotionProperty.scale:
              scale = value;
            case SceneMotionProperty.rotation:
              rotation = value;
          }
        }
        return Opacity(
          opacity: opacity,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..translateByDouble(x, y, 0, 1)
              ..rotateZ(rotation * 3.141592653589793 / 180)
              ..scaleByDouble(scale, scale, 1, 1),
            child: child,
          ),
        );
      },
    );
  }
}
