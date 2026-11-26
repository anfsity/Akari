import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../ui/studio_form.dart';
import '../ui/studio_form_values.dart';

class StudioKeyframeDialog extends StatefulWidget {
  const StudioKeyframeDialog({
    required this.track,
    required this.index,
    super.key,
  });

  final SceneMotionTrack track;
  final int index;

  @override
  State<StudioKeyframeDialog> createState() => _StudioKeyframeDialogState();
}

class _StudioKeyframeDialogState extends State<StudioKeyframeDialog> {
  late final _time = TextEditingController(
    text: '${widget.track.keyframes[widget.index].timeMs}',
  );
  late final _value = TextEditingController(
    text: '${widget.track.keyframes[widget.index].value}',
  );
  late SceneKeyframeCurve _curve = widget.track.keyframes[widget.index].curve;
  String? _error;

  @override
  void dispose() {
    _time.dispose();
    _value.dispose();
    super.dispose();
  }

  void _save() {
    try {
      final time = getIntegerInput('Time', _time.text);
      final value = getFiniteNumberInput('Value', _value.text);
      final frames = widget.track.keyframes;
      if (time < 0 ||
          time > maxSceneMotionTimeMs ||
          (widget.index > 0 && time <= frames[widget.index - 1].timeMs) ||
          (widget.index < frames.length - 1 &&
              time >= frames[widget.index + 1].timeMs)) {
        throw const FormatException(
          'Time must stay between adjacent keyframes (0..$maxSceneMotionTimeMs ms).',
        );
      }
      if (clampSceneKeyframeValue(widget.track.property, value) != value) {
        throw const FormatException(
          'Opacity must be 0..1; other values must be within ±100000.',
        );
      }
      Navigator.of(
        context,
      ).pop((frame: SceneKeyframe(timeMs: time, value: value, curve: _curve)));
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return AlertDialog(
      title: Text('${widget.track.property.name} keyframe'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            StudioFormField(
              label: 'Time ms',
              controller: _time,
              inputKey: const ValueKey('keyframe-time'),
            ),
            StudioFormField(
              label: 'Value',
              controller: _value,
              inputKey: const ValueKey('keyframe-value'),
            ),
            StudioEnumSelect(
              value: _curve,
              values: SceneKeyframeCurve.values,
              onChanged: (value) => setState(() => _curve = value),
            ),
            if (error != null) StudioFormError(error),
          ],
        ),
      ),
      actions: [
        GhostButton(
          onPressed: () => Navigator.of(context).pop((frame: null)),
          child: const Text('Delete'),
        ),
        OutlineButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        PrimaryButton(onPressed: _save, child: const Text('Apply')),
      ],
    );
  }
}
