import 'package:flutter/material.dart';
import 'package:scene/scene.dart';

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
          child: child,
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
      child,
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
