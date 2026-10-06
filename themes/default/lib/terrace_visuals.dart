import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:theme_sdk/theme_sdk.dart';

/// The sky stays in focus. Local shadows provide contrast without a full-screen
/// blur pass, and pointer motion moves the cached wallpaper rather than inputs.
class TerraceBackgroundRenderer extends BackgroundRenderer {
  const TerraceBackgroundRenderer();

  @override
  Widget build(BuildContext context, SceneBackground background) =>
      _TerraceBackdrop(
        wallpaper: Transform.scale(
          scale: 1.025,
          // Cache the image and its atmosphere together. Keeping gradients
          // outside would blend two full-screen layers on every parallax frame.
          child: RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ImageBackgroundRenderer(
                  alignment: Alignment(0.72, 0),
                  filterQuality: FilterQuality.low,
                ).build(context, background.copyWith(blurSigma: 0)),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xb30b263c),
                        Color(0x380b263c),
                        Color(0x000b263c),
                      ],
                      stops: [0, 0.48, 0.78],
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x2007192c),
                        Colors.transparent,
                        Color(0xb307192c),
                      ],
                      stops: [0, 0.6, 1],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _TerraceBackdrop extends StatefulWidget {
  const _TerraceBackdrop({required this.wallpaper});

  final Widget wallpaper;

  @override
  State<_TerraceBackdrop> createState() => _TerraceBackdropState();
}

class _TerraceBackdropState extends State<_TerraceBackdrop> {
  Offset _target = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) => MouseRegion(
        onHover: reducedMotion
            ? null
            : (event) => setState(() {
                _target = Offset(
                  (event.localPosition.dx / constraints.maxWidth - 0.5) * 12,
                  (event.localPosition.dy / constraints.maxHeight - 0.5) * 8,
                );
              }),
        onExit: reducedMotion
            ? null
            : (event) {
                // Opening a popup also removes the wallpaper from hover. Keep
                // its offset then; reset only when the pointer leaves the view.
                final bounds = Offset.zero & constraints.biggest;
                if (!bounds.contains(event.localPosition)) {
                  setState(() => _target = Offset.zero);
                }
              },
        child: ClipRect(
          child: TweenAnimationBuilder<Offset>(
            tween: Tween(
              begin: Offset.zero,
              end: reducedMotion ? Offset.zero : _target,
            ),
            duration: reducedMotion
                ? Duration.zero
                : const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, offset, child) =>
                Transform.translate(offset: offset, child: child),
            child: widget.wallpaper,
          ),
        ),
      ),
    );
  }
}

/// Panel/clock settle first, followed by the heading, then the controls. All
/// layers share reversible runtime progress so interrupted wakes stay smooth.
class TerraceEntranceMotion extends SceneMotionBuilder {
  const TerraceEntranceMotion();

  @override
  Widget build(
    BuildContext context,
    SceneMotionSpec spec,
    Animation<double> progress,
    Widget child,
  ) {
    final surface = spec.preset == SceneMotionPreset.fadeScale;
    final entrance = progress.drive(
      CurveTween(curve: Interval(surface ? 0 : 0.12, surface ? 0.82 : 1)),
    );
    return FadeTransition(
      opacity: entrance.drive(CurveTween(curve: Curves.easeOutCubic)),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(surface ? -0.02 : 0, surface ? 0 : 0.16),
          end: Offset.zero,
        ).animate(entrance.drive(CurveTween(curve: Curves.easeOutCubic))),
        child: ScaleTransition(
          alignment: Alignment.centerLeft,
          scale: Tween<double>(
            begin: surface ? 0.96 : 0.985,
            end: 1,
          ).animate(entrance.drive(CurveTween(curve: Curves.easeOutBack))),
          // Cache the static content inside the moving layer; the scene's
          // outer boundary otherwise repaints text at every scale/slide step.
          child: RepaintBoundary(child: child),
        ),
      ),
    );
  }
}

class TerraceFadeMotion extends SceneMotionBuilder {
  const TerraceFadeMotion();

  @override
  Widget build(
    BuildContext context,
    SceneMotionSpec spec,
    Animation<double> progress,
    Widget child,
  ) => FadeTransition(
    opacity: progress.drive(
      CurveTween(curve: const Interval(0.24, 1, curve: Curves.easeOutCubic)),
    ),
    child: child,
  );
}

class TerraceActionMotion extends SceneMotionBuilder {
  const TerraceActionMotion();

  @override
  Widget build(
    BuildContext context,
    SceneMotionSpec spec,
    Animation<double> progress,
    Widget child,
  ) => FadeTransition(
    opacity: progress.drive(
      CurveTween(curve: const Interval(0.24, 1, curve: Curves.easeOutCubic)),
    ),
    child: const HoverLiftMotionBuilder().build(
      context,
      (
        preset: spec.preset,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        reducedMotion: spec.reducedMotion,
      ),
      progress,
      RepaintBoundary(child: child),
    ),
  );
}

/// Keep the native field and focus mounted while a rejection moves its surface.
/// Only new credential errors trigger motion; unrelated slot updates and waking
/// an existing error must not replay it. Frames repaint without field rebuilds.
class TerraceCredentialFeedback extends StatefulWidget {
  const TerraceCredentialFeedback({
    required this.auth,
    required this.child,
    super.key,
  });

  final AuthPromptSlots auth;
  final Widget child;

  @override
  State<TerraceCredentialFeedback> createState() =>
      _TerraceCredentialFeedbackState();
}

class _TerraceCredentialFeedbackState extends State<TerraceCredentialFeedback>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void didUpdateWidget(TerraceCredentialFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    final error = widget.auth.error;
    final rejected =
        error != null &&
        (error.kind == GreeterErrorKind.authentication ||
            error.kind == GreeterErrorKind.input) &&
        error != oldWidget.auth.error;
    final promptRejected =
        widget.auth.promptError != null &&
        widget.auth.promptError != oldWidget.auth.promptError;
    if ((rejected || promptRejected) &&
        !MediaQuery.disableAnimationsOf(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      final progress = _controller.value;
      final envelope = (1 - progress) * (1 - progress);
      return Transform.translate(
        offset: Offset(math.sin(progress * math.pi * 6) * 9 * envelope, 0),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius:
                (InputDecorationTheme.of(context).enabledBorder!
                        as OutlineInputBorder)
                    .borderRadius,
            border: Border.all(
              color: Theme.of(context).colorScheme.error
                  .withValues(alpha: math.sin(progress * math.pi) * 0.85),
            ),
          ),
          child: child,
        ),
      );
    },
    child: RepaintBoundary(child: widget.child),
  );
}

class TerraceChoiceLabel extends StatelessWidget {
  const TerraceChoiceLabel({
    required this.id,
    required this.label,
    this.style,
    super.key,
  });

  final String? id;
  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    layoutBuilder: (child, previous) =>
        Stack(alignment: Alignment.centerLeft, children: [...previous, ?child]),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.35),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
    child: Text(
      label,
      key: ValueKey(id),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    ),
  );
}

class TerracePanel extends StatelessWidget {
  const TerracePanel({required this.radius, super.key});

  final double radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
      ),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xb30e2536), Color(0x8c0e2536)],
      ),
    ),
  );
}
