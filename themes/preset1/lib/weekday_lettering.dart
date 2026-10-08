import 'package:flutter/material.dart';

/// A small authored display alphabet for weekdays, matching the reference's
/// squared, open geometry. Body text stays native for selection and access.
class WeekdayLettering extends StatelessWidget {
  const WeekdayLettering({
    required this.text,
    required this.color,
    required this.height,
    super.key,
  });

  final String text;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => Semantics(
    label: text,
    child: SizedBox(
      width: text.length * height * 1.32,
      height: height,
      child: CustomPaint(painter: _WeekdayPainter(text, color)),
    ),
  );
}

class _WeekdayPainter extends CustomPainter {
  const _WeekdayPainter(this.text, this.color);

  final String text;
  final Color color;

  // Each polyline is a pen stroke on a 40 x 50 grid. Diagonal cuts, square
  // terminals and generous tracking keep the lettering crisp at any scale.
  static const _strokes = <String, List<List<Offset>>>{
    'A': [
      [
        Offset(3, 47),
        Offset(3, 9),
        Offset(9, 3),
        Offset(31, 3),
        Offset(37, 9),
        Offset(37, 47),
      ],
      [Offset(3, 27), Offset(37, 27)],
    ],
    'D': [
      [
        Offset(3, 47),
        Offset(3, 3),
        Offset(29, 3),
        Offset(37, 11),
        Offset(37, 39),
        Offset(29, 47),
        Offset(3, 47),
      ],
    ],
    'E': [
      [Offset(37, 3), Offset(3, 3), Offset(3, 47), Offset(37, 47)],
      [Offset(3, 25), Offset(30, 25)],
    ],
    'F': [
      [Offset(37, 3), Offset(3, 3), Offset(3, 47)],
      [Offset(3, 25), Offset(30, 25)],
    ],
    'H': [
      [Offset(3, 3), Offset(3, 47)],
      [Offset(37, 3), Offset(37, 47)],
      [Offset(3, 25), Offset(37, 25)],
    ],
    'I': [
      [Offset(20, 3), Offset(20, 47)],
    ],
    'M': [
      [
        Offset(3, 47),
        Offset(3, 3),
        Offset(20, 24),
        Offset(37, 3),
        Offset(37, 47),
      ],
    ],
    'N': [
      [Offset(3, 47), Offset(3, 3), Offset(37, 47), Offset(37, 3)],
    ],
    'O': [
      [
        Offset(11, 3),
        Offset(29, 3),
        Offset(37, 11),
        Offset(37, 39),
        Offset(29, 47),
        Offset(11, 47),
        Offset(3, 39),
        Offset(3, 11),
        Offset(11, 3),
      ],
    ],
    'R': [
      [
        Offset(3, 47),
        Offset(3, 3),
        Offset(31, 3),
        Offset(37, 9),
        Offset(37, 21),
        Offset(31, 27),
        Offset(3, 27),
      ],
      [Offset(17, 27), Offset(37, 47)],
    ],
    'S': [
      [
        Offset(37, 3),
        Offset(9, 3),
        Offset(3, 9),
        Offset(3, 19),
        Offset(9, 25),
        Offset(31, 25),
        Offset(37, 31),
        Offset(37, 41),
        Offset(31, 47),
        Offset(3, 47),
      ],
    ],
    'T': [
      [Offset(3, 3), Offset(37, 3)],
      [Offset(20, 3), Offset(20, 47)],
    ],
    'U': [
      [
        Offset(3, 3),
        Offset(3, 39),
        Offset(11, 47),
        Offset(29, 47),
        Offset(37, 39),
        Offset(37, 3),
      ],
    ],
    'W': [
      [
        Offset(3, 3),
        Offset(8, 47),
        Offset(20, 29),
        Offset(32, 47),
        Offset(37, 3),
      ],
    ],
    'Y': [
      [Offset(3, 3), Offset(20, 23), Offset(37, 3)],
      [Offset(20, 23), Offset(20, 47)],
    ],
  };

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.height / 56);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.bevel
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < text.length; i++) {
      canvas.save();
      canvas.translate(i * 56 * 1.32 + 14, 3);
      for (final stroke in _strokes[text[i]]!) {
        final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
        for (final point in stroke.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(path, paint);
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WeekdayPainter oldDelegate) =>
      text != oldDelegate.text || color != oldDelegate.color;
}
