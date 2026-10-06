import 'package:flutter/material.dart';
import 'package:scene/scene.dart';

/// The sky stays in focus. Local shadows provide contrast without a full-screen
/// blur pass, and pointer motion moves the cached wallpaper rather than inputs.
class TerraceBackgroundRenderer extends BackgroundRenderer {
  const TerraceBackgroundRenderer();

  @override
  Widget build(BuildContext context, SceneBackground background) =>
      _TerraceBackdrop(background: background);
}

class _TerraceBackdrop extends StatefulWidget {
  const _TerraceBackdrop({required this.background});

  final SceneBackground background;

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
        onExit: (_) => setState(() => _target = Offset.zero),
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              TweenAnimationBuilder<Offset>(
                tween: Tween(
                  begin: Offset.zero,
                  end: reducedMotion ? Offset.zero : _target,
                ),
                duration: reducedMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, offset, child) => Transform.translate(
                  offset: offset,
                  child: Transform.scale(scale: 1.025, child: child),
                ),
                child: RepaintBoundary(
                  child: const ImageBackgroundRenderer(
                    alignment: Alignment(0.72, 0),
                  ).build(context, widget.background.copyWith(blurSigma: 0)),
                ),
              ),
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
}

/// All entrance layers share the runtime's reversible progress. A small yaw
/// and depth offset suggest approaching a marker on the terrace, without moving
/// the native credential field or recreating its focus and controller.
class TerraceEntranceMotion extends SceneMotionBuilder {
  const TerraceEntranceMotion();

  @override
  Widget build(
    BuildContext context,
    SceneMotionSpec spec,
    Animation<double> progress,
    Widget child,
  ) {
    return FadeTransition(
      opacity: progress,
      child: AnimatedBuilder(
        animation: progress,
        child: child,
        builder: (context, child) {
          final remaining = 1 - progress.value;
          return Transform(
            alignment: Alignment.centerLeft,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0007)
              ..translateByDouble(-18 * remaining, 6 * remaining, 0, 1)
              ..rotateY(-0.06 * remaining),
            child: child,
          );
        },
      ),
    );
  }
}

class TerracePortal extends StatelessWidget {
  const TerracePortal({super.key});

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _PortalPainter(Theme.of(context).colorScheme.primary),
  );
}

class _PortalPainter extends CustomPainter {
  const _PortalPainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final plane = Path()
      ..moveTo(0, size.height * 0.025)
      ..lineTo(size.width, 0)
      ..lineTo(size.width * 0.97, size.height)
      ..lineTo(0, size.height * 0.965)
      ..close();
    canvas.drawPath(
      plane,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x080e3047), Color(0xb30e3047)],
        ).createShader(bounds),
    );
    final line = Paint()
      ..color = accent.withValues(alpha: 0.34)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height * 0.14)
        ..lineTo(0, size.height * 0.025)
        ..lineTo(size.width * 0.18, size.height * 0.02),
      line,
    );
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.68, size.height * 0.99)
        ..lineTo(size.width * 0.97, size.height)
        ..lineTo(size.width * 0.973, size.height * 0.88),
      line,
    );
    canvas.drawLine(
      Offset(size.width * 0.07, size.height * 0.965),
      Offset(size.width * 0.57, size.height * 0.984),
      Paint()
        ..strokeWidth = 1.5
        ..shader = LinearGradient(
          colors: [accent.withValues(alpha: 0.6), accent.withValues(alpha: 0)],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(_PortalPainter oldDelegate) =>
      oldDelegate.accent != accent;
}
