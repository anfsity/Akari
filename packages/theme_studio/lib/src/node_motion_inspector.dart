import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'scene_editor.dart';
import 'studio_form.dart';
import 'studio_form_values.dart';

class NodeMotionInspector extends StatefulWidget {
  const NodeMotionInspector({required this.editor, super.key});
  final SceneEditor editor;
  @override
  State<NodeMotionInspector> createState() => _NodeMotionInspectorState();
}

class _NodeMotionInspectorState extends State<NodeMotionInspector> {
  final _fields = <String, TextEditingController>{};
  @override
  void initState() {
    super.initState();
    _updateFields();
  }

  @override
  void didUpdateWidget(NodeMotionInspector old) {
    super.didUpdateWidget(old);
    _updateFields();
  }

  void _updateFields() {
    final timing = widget.editor.selectedNode.motionTiming;
    final curve = timing.curve ?? const SceneCubicBezier(.2, 0, .2, 1);
    for (final entry in {
      'Duration ms': timing.durationMs?.toString() ?? '',
      'Delay ms': '${timing.delayMs}',
      'Bezier X1': '${curve.x1}',
      'Bezier Y1': '${curve.y1}',
      'Bezier X2': '${curve.x2}',
      'Bezier Y2': '${curve.y2}',
    }.entries) {
      _fields.putIfAbsent(entry.key, TextEditingController.new).text =
          entry.value;
    }
  }

  void _apply({bool? customCurve}) {
    if (!widget.editor.applyDraft()) return;
    try {
      double number(String label) =>
          getFiniteNumberInput(label, _fields[label]!.text);
      widget.editor.updateNode(
        widget.editor.selectedNode.copyWith(
          motionTiming: SceneMotionTiming(
            durationMs: _fields['Duration ms']!.text.isEmpty
                ? null
                : getIntegerInput('Duration ms', _fields['Duration ms']!.text),
            delayMs: getIntegerInput('Delay ms', _fields['Delay ms']!.text),
            curve:
                (customCurve ??
                    widget.editor.selectedNode.motionTiming.curve != null)
                ? SceneCubicBezier(
                    number('Bezier X1'),
                    number('Bezier Y1'),
                    number('Bezier X2'),
                    number('Bezier Y2'),
                  )
                : null,
          ),
        ),
      );
    } on FormatException catch (error) {
      widget.editor.inspector.showError(error.message);
    }
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Widget _field(String label) => StudioFormField(
    label: label,
    controller: _fields[label]!,
    inputKey: ValueKey('motion-$label'),
    onSubmitted: () =>
        _apply(customCurve: label.startsWith('Bezier') ? true : null),
    onFocusLost: () =>
        _apply(customCurve: label.startsWith('Bezier') ? true : null),
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Gap(12),
      StudioFieldRow(left: _field('Duration ms'), right: _field('Delay ms')),
      Row(
        children: [
          const Expanded(child: Text('Custom Bezier')),
          Switch(
            value: widget.editor.selectedNode.motionTiming.curve != null,
            onChanged: (value) => _apply(customCurve: value),
          ),
        ],
      ),
      if (widget.editor.selectedNode.motionTiming.curve case final curve?)
        SizedBox(
          height: 90,
          child: CustomPaint(painter: _BezierPainter(curve)),
        ),
      const Gap(8),
      StudioFieldRow(left: _field('Bezier X1'), right: _field('Bezier Y1')),
      StudioFieldRow(left: _field('Bezier X2'), right: _field('Bezier Y2')),
      const Text(
        'Blank duration inherits theme timing. Curve controls use 0..1.',
      ).small().muted(),
    ],
  );
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
