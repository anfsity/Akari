import 'package:flutter/material.dart';

import '../feature/greeter/greeter_slots.dart';
import 'visual_layer.dart';

class StaticBackgroundVisual extends VisualLayer {
  const StaticBackgroundVisual({required this.slots, super.key});

  final BackgroundSlots slots;

  @override
  Widget build(BuildContext context) {
    final color = switch (slots.mood) {
      BackgroundMood.calm => const Color(0xff0d151a),
      BackgroundMood.active => const Color(0xff102329),
      BackgroundMood.success => const Color(0xff10231e),
      BackgroundMood.error => const Color(0xff29191d),
    };

    return ColoredBox(
      color: color,
      child: CustomPaint(
        painter: _BackgroundPainter(
          color: Theme.of(context).colorScheme.primary,
          intensity: slots.intensity,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  const _BackgroundPainter({required this.color, required this.intensity});

  final Color color;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.08 + intensity * 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final inset = size.width * 0.08;
    final rect = Rect.fromLTWH(
      inset,
      size.height * 0.16,
      size.width - inset * 2,
      size.height * 0.68,
    );
    canvas.drawOval(rect, paint);
    canvas.drawOval(rect.deflate(size.width * 0.08), paint);
  }

  @override
  bool shouldRepaint(_BackgroundPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.intensity != intensity;
  }
}
