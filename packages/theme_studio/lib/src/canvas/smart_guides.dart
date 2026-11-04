import 'dart:math' as math;

import 'package:flutter/widgets.dart';

typedef GuideMeasurement = ({Offset start, Offset end});

typedef SmartGuideResult = ({
  Offset correction,
  List<double> vertical,
  List<double> horizontal,
  List<GuideMeasurement> measurements,
});

/// Snap the nearest edge/center on each axis, measured in canvas pixels.
/// Tolerance is supplied in screen pixels converted through viewport zoom.
SmartGuideResult calculateSmartGuides({
  required Rect moving,
  required Iterable<Rect> targets,
  required Size canvasSize,
  required double tolerance,
  Iterable<double> verticalGuides = const [],
  Iterable<double> horizontalGuides = const [],
}) {
  final rectangles = targets.toList();
  final verticalTargets = [
    0.0,
    canvasSize.width / 2,
    canvasSize.width,
    ...verticalGuides,
  ];
  final horizontalTargets = [
    0.0,
    canvasSize.height / 2,
    canvasSize.height,
    ...horizontalGuides,
  ];
  for (final target in rectangles) {
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
  final snapped = moving.shift(Offset(x.delta, y.delta));
  GuideMeasurement? horizontalMeasurement;
  GuideMeasurement? verticalMeasurement;
  for (final target in rectangles) {
    if (snapped.top < target.bottom && snapped.bottom > target.top) {
      final y =
          (math.max(snapped.top, target.top) +
              math.min(snapped.bottom, target.bottom)) /
          2;
      final measurement = snapped.left > target.right
          ? (start: Offset(target.right, y), end: Offset(snapped.left, y))
          : target.left > snapped.right
          ? (start: Offset(snapped.right, y), end: Offset(target.left, y))
          : null;
      if (measurement != null &&
          (horizontalMeasurement == null ||
              (measurement.end - measurement.start).distance <
                  (horizontalMeasurement.end - horizontalMeasurement.start)
                      .distance)) {
        horizontalMeasurement = measurement;
      }
    }
    if (snapped.left < target.right && snapped.right > target.left) {
      final x =
          (math.max(snapped.left, target.left) +
              math.min(snapped.right, target.right)) /
          2;
      final measurement = snapped.top > target.bottom
          ? (start: Offset(x, target.bottom), end: Offset(x, snapped.top))
          : target.top > snapped.bottom
          ? (start: Offset(x, snapped.bottom), end: Offset(x, target.top))
          : null;
      if (measurement != null &&
          (verticalMeasurement == null ||
              (measurement.end - measurement.start).distance <
                  (verticalMeasurement.end - verticalMeasurement.start)
                      .distance)) {
        verticalMeasurement = measurement;
      }
    }
  }
  return (
    correction: Offset(x.delta, y.delta),
    vertical: x.guides,
    horizontal: y.guides,
    measurements: [?horizontalMeasurement, ?verticalMeasurement],
  );
}

class SmartGuidePainter extends CustomPainter {
  const SmartGuidePainter({
    required this.vertical,
    required this.horizontal,
    required this.scale,
    this.measurements = const [],
  });
  final List<double> vertical;
  final List<double> horizontal;
  final double scale;
  final List<GuideMeasurement> measurements;

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
    for (final measurement in measurements) {
      canvas.drawLine(measurement.start, measurement.end, paint);
      final label = TextPainter(
        text: TextSpan(
          text: '${(measurement.end - measurement.start).distance.round()} px',
          style: TextStyle(
            color: const Color(0xfffb7185),
            fontSize: 10 / scale,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final origin =
          (measurement.start + measurement.end) / 2 -
          Offset(label.width / 2, label.height / 2);
      canvas.drawRect(
        (origin & label.size).inflate(2 / scale),
        Paint()..color = const Color(0xee18181b),
      );
      label.paint(canvas, origin);
      label.dispose();
    }
  }

  @override
  bool shouldRepaint(SmartGuidePainter old) =>
      old.vertical != vertical ||
      old.horizontal != horizontal ||
      old.measurements != measurements ||
      old.scale != scale;
}
