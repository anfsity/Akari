import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:theme_sdk/theme_sdk.dart';

class StudioRulers extends StatelessWidget {
  const StudioRulers({
    required this.size,
    required this.scale,
    required this.guides,
    required this.onStart,
    required this.onUpdate,
    required this.onStop,
    required this.onCancel,
    required this.onDelete,
    this.readOnly = false,
    super.key,
  });
  final bool readOnly;
  final Size size;
  final double scale;
  final List<SceneGuide> guides;
  final void Function(SceneGuideAxis, int?) onStart;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onStop;
  final VoidCallback onCancel;
  final ValueChanged<int> onDelete;

  Widget _handle(SceneGuideAxis axis, int? index, {required Widget child}) =>
      Listener(
        onPointerCancel: readOnly ? null : (_) => onCancel(),
        child: GestureDetector(
          key: ValueKey(index == null ? 'ruler-${axis.name}' : 'guide-$index'),
          behavior: HitTestBehavior.opaque,
          onDoubleTap: readOnly || index == null ? null : () => onDelete(index),
          onPanStart: readOnly
              ? null
              : (details) {
                  onStart(axis, index);
                  onUpdate(details.globalPosition);
                },
          onPanUpdate: readOnly
              ? null
              : (details) => onUpdate(details.globalPosition),
          onPanEnd: readOnly ? null : (_) => onStop(),
          onPanCancel: readOnly ? null : onCancel,
          child: child,
        ),
      );
  @override
  Widget build(BuildContext context) {
    final band = 18 / scale;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _RulerPainter(scale, guides)),
          ),
        ),
        for (final (index, guide) in guides.indexed)
          Positioned(
            key: ValueKey('guide-position-$index'),
            left: guide.axis == SceneGuideAxis.vertical
                ? guide.position * size.width - 4 / scale
                : 0,
            top: guide.axis == SceneGuideAxis.horizontal
                ? guide.position * size.height - 4 / scale
                : 0,
            width: guide.axis == SceneGuideAxis.vertical
                ? 8 / scale
                : size.width,
            height: guide.axis == SceneGuideAxis.horizontal
                ? 8 / scale
                : size.height,
            child: MouseRegion(
              cursor: guide.axis == SceneGuideAxis.vertical
                  ? SystemMouseCursors.resizeLeftRight
                  : SystemMouseCursors.resizeUpDown,
              child: _handle(guide.axis, index, child: const SizedBox.expand()),
            ),
          ),
        Positioned(
          key: const ValueKey('ruler-band-vertical'),
          left: band,
          top: 0,
          right: 0,
          height: band,
          child: _handle(
            SceneGuideAxis.vertical,
            null,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          key: const ValueKey('ruler-band-horizontal'),
          left: 0,
          top: band,
          bottom: 0,
          width: band,
          child: _handle(
            SceneGuideAxis.horizontal,
            null,
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

class _RulerPainter extends CustomPainter {
  const _RulerPainter(this.scale, this.guides);
  final double scale;
  final List<SceneGuide> guides;
  @override
  void paint(Canvas canvas, Size size) {
    final band = 18 / scale;
    final fill = Paint()..color = const Color(0xee27272a);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, band), fill);
    canvas.drawRect(Rect.fromLTWH(0, 0, band, size.height), fill);
    final paint = Paint()
      ..color = const Color(0xffa1a1aa)
      ..strokeWidth = 1 / scale;
    final magnitude = math
        .pow(10, (math.log(70 / scale) / math.ln10).floor())
        .toDouble();
    final ratio = 70 / scale / magnitude;
    final step =
        magnitude *
        (ratio <= 1
            ? 1
            : ratio <= 2
            ? 2
            : ratio <= 5
            ? 5
            : 10);
    for (final horizontal in [true, false]) {
      final length = horizontal ? size.width : size.height;
      for (var i = 0; i * step / 5 < length; i++) {
        final position = i * step / 5;
        final tick = (i % 5 == 0 ? 7 : 3) / scale;
        canvas.drawLine(
          horizontal
              ? Offset(position, band - tick)
              : Offset(band - tick, position),
          horizontal ? Offset(position, band) : Offset(band, position),
          paint,
        );
        if (i % 5 == 0 && i > 0) {
          final label = TextPainter(
            text: TextSpan(
              text: '${position.round()}',
              style: TextStyle(
                color: const Color(0xffd4d4d8),
                fontSize: 9 / scale,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          if (horizontal) {
            label.paint(canvas, Offset(position + 2 / scale, 0));
          } else {
            canvas.save();
            canvas.translate(band, position + 2 / scale);
            canvas.rotate(math.pi / 2);
            label.paint(canvas, Offset.zero);
            canvas.restore();
          }
          label.dispose();
        }
      }
    }
    paint.color = const Color(0xff22d3ee);
    for (final guide in guides) {
      if (guide.axis == SceneGuideAxis.vertical) {
        final x = guide.position * size.width;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      } else {
        final y = guide.position * size.height;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.scale != scale || old.guides != guides;
}
