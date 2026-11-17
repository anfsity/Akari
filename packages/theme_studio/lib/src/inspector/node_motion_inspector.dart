import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../authoring/scene_editor.dart';
import '../ui/studio_form.dart';

class NodeMotionInspector extends StatelessWidget {
  const NodeMotionInspector({required this.editor, super.key});

  final SceneEditor editor;

  static const _prefixes = <String, String>{
    'Duration ms': 'Dur',
    'Delay ms': 'Delay',
    'Bezier X1': 'X1',
    'Bezier Y1': 'Y1',
    'Bezier X2': 'X2',
    'Bezier Y2': 'Y2',
  };

  Widget _field(String label) => StudioFormField(
    label: label,
    prefix: _prefixes[label],
    controller: editor.inspector.getField(label),
    inputKey: ValueKey('motion-$label'),
    onSubmitted: editor.tryApplyDraft,
    onFocusLost: editor.tryApplyDraft,
  );

  @override
  Widget build(BuildContext context) {
    final controller = editor.inspector;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          StudioFieldRow(
            left: _field('Duration ms'),
            right: _field('Delay ms'),
          ),
          StudioSwitchRow(
            label: 'Custom Bezier',
            value: controller.hasCustomMotionCurve,
            onChanged: (value) {
              controller.updateCustomMotionCurve(value);
              editor.tryApplyDraft();
            },
          ),
          if (controller.hasCustomMotionCurve)
            ListenableBuilder(
              listenable: Listenable.merge([
                controller.getField('Bezier X1'),
                controller.getField('Bezier Y1'),
                controller.getField('Bezier X2'),
                controller.getField('Bezier Y2'),
              ]),
              builder: (context, _) => SizedBox(
                height: 80,
                child: CustomPaint(
                  painter: _BezierPainter(controller.motionCurvePreview!),
                ),
              ),
            ),
          StudioFieldRow(left: _field('Bezier X1'), right: _field('Bezier Y1')),
          StudioFieldRow(left: _field('Bezier X2'), right: _field('Bezier Y2')),
          const Text(
            'Blank duration inherits theme timing. Curve controls use 0..1.',
          ).xSmall().muted(),
        ],
      ),
    );
  }
}

class _BezierPainter extends CustomPainter {
  const _BezierPainter(this.curve);
  final SceneCubicBezier curve;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xff8b5cf6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()
      ..moveTo(0, size.height)
      ..cubicTo(
        curve.x1 * size.width,
        (1 - curve.y1) * size.height,
        curve.x2 * size.width,
        (1 - curve.y2) * size.height,
        size.width,
        0,
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BezierPainter old) => old.curve != curve;
}
