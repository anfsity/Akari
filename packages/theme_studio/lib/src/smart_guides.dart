import 'package:flutter/widgets.dart';

typedef SmartGuideResult = ({
  Offset correction,
  List<double> vertical,
  List<double> horizontal,
});

/// Snap the nearest edge/center on each axis, measured in canvas pixels.
/// Tolerance is supplied in screen pixels converted through viewport zoom.
SmartGuideResult calculateSmartGuides({
  required Rect moving,
  required Iterable<Rect> targets,
  required Size canvasSize,
  required double tolerance,
}) {
  final verticalTargets = [0.0, canvasSize.width / 2, canvasSize.width];
  final horizontalTargets = [0.0, canvasSize.height / 2, canvasSize.height];
  for (final target in targets) {
    verticalTargets.addAll([target.left, target.center.dx, target.right]);
    horizontalTargets.addAll([target.top, target.center.dy, target.bottom]);
  }
  ({double delta, List<double> guides}) nearest(
    List<double> moving,
    List<double> targets,
  ) {
    var distance = tolerance;
    var delta = 0.0;
    var guides = <double>[];
    for (final source in moving) {
      for (final target in targets) {
        final candidate = target - source;
        if (candidate.abs() < distance ||
            (guides.isEmpty && candidate.abs() == distance)) {
          distance = candidate.abs();
          delta = candidate;
          guides = [target];
        } else if (guides.isNotEmpty && (candidate - delta).abs() < 1e-6) {
          guides.add(target);
        }
      }
    }
    return (delta: delta, guides: guides.toSet().toList());
  }

  final x = nearest([
    moving.left,
    moving.center.dx,
    moving.right,
  ], verticalTargets);
  final y = nearest([
    moving.top,
    moving.center.dy,
    moving.bottom,
  ], horizontalTargets);
  return (
    correction: Offset(x.delta, y.delta),
    vertical: x.guides,
    horizontal: y.guides,
  );
}

class SmartGuidePainter extends CustomPainter {
  const SmartGuidePainter({
    required this.vertical,
    required this.horizontal,
    required this.scale,
  });
  final List<double> vertical;
  final List<double> horizontal;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xfff43f5e)
      ..strokeWidth = 1 / scale;
    for (final x in vertical) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (final y in horizontal) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(SmartGuidePainter old) =>
      old.vertical != vertical ||
      old.horizontal != horizontal ||
      old.scale != scale;
}
