import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'studio_form.dart';
import 'scene_editor.dart';
import 'studio_timeline_tracks.dart';
import 'studio_preview_host.dart';

enum StudioTransition {
  entrance(
    'Entrance',
    false,
    false,
    StudioPreviewScenario.password,
    StudioPreviewScenario.password,
  ),
  wake(
    'Dormant → Login',
    true,
    false,
    StudioPreviewScenario.password,
    StudioPreviewScenario.password,
  ),
  sleep(
    'Login → Dormant',
    false,
    true,
    StudioPreviewScenario.password,
    StudioPreviewScenario.password,
  ),
  success(
    'Submit → Success',
    false,
    false,
    StudioPreviewScenario.submitting,
    StudioPreviewScenario.success,
  ),
  error(
    'Submit → Error',
    false,
    false,
    StudioPreviewScenario.submitting,
    StudioPreviewScenario.error,
  );

  const StudioTransition(
    this.label,
    this.fromDormant,
    this.toDormant,
    this.fromScenario,
    this.toScenario,
  );
  final String label;
  final bool fromDormant;
  final bool toDormant;
  final StudioPreviewScenario fromScenario;
  final StudioPreviewScenario toScenario;
}

class StudioTimeline extends StatefulWidget {
  const StudioTimeline({
    required this.editor,
    required this.fallbackDuration,
    required this.duration,
    required this.elapsed,
    required this.transition,
    required this.onTimeChanged,
    required this.onTransitionChanged,
    super.key,
  });
  final SceneEditor editor;
  final Duration fallbackDuration;
  final Duration duration;
  final Duration elapsed;
  final StudioTransition transition;
  final ValueChanged<Duration> onTimeChanged;
  final ValueChanged<StudioTransition> onTransitionChanged;
  @override
  State<StudioTimeline> createState() => _StudioTimelineState();
}

class _StudioTimelineState extends State<StudioTimeline>
    with SingleTickerProviderStateMixin {
  bool _synchronizing = false;
  late final AnimationController _player =
      AnimationController(vsync: this, duration: widget.duration)
        ..addListener(() {
          if (!_synchronizing) {
            widget.onTimeChanged(
              Duration(
                microseconds: (_player.value * widget.duration.inMicroseconds)
                    .round(),
              ),
            );
          }
        });
  @override
  void didUpdateWidget(StudioTimeline old) {
    super.didUpdateWidget(old);
    _player.duration = widget.duration;
    if (!_player.isAnimating) {
      _synchronizing = true;
      _player.value =
          (widget.elapsed.inMicroseconds / widget.duration.inMicroseconds)
              .clamp(0, 1);
      _synchronizing = false;
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('Timeline').small().semiBold(),
            const Gap(12),
            Expanded(
              child: StudioEnumSelect(
                value: widget.transition,
                values: StudioTransition.values,
                formatValue: (value) => value.label,
                onChanged: (value) {
                  _player.stop();
                  widget.onTransitionChanged(value);
                },
              ),
            ),
            const Gap(8),
            OutlineButton(
              key: const ValueKey('timeline-restart'),
              onPressed: () {
                _player.stop();
                widget.onTimeChanged(Duration.zero);
              },
              child: const Icon(LucideIcons.skipBack, size: 16),
            ),
            const Gap(4),
            OutlineButton(
              key: const ValueKey('timeline-play'),
              onPressed: () => setState(() {
                if (_player.isAnimating) {
                  _player.stop();
                } else {
                  _player.forward(from: _player.value >= 1 ? 0 : _player.value);
                }
              }),
              child: Icon(
                _player.isAnimating ? LucideIcons.pause : LucideIcons.play,
                size: 16,
              ),
            ),
          ],
        ),
        const Gap(8),
        Slider(
          key: const ValueKey('timeline-scrubber'),
          value: SliderValue.single(
            (widget.elapsed.inMicroseconds / widget.duration.inMicroseconds)
                .clamp(0, 1),
          ),
          onChanged: (value) {
            _player.stop();
            widget.onTimeChanged(
              Duration(
                microseconds: (value.value * widget.duration.inMicroseconds)
                    .round(),
              ),
            );
          },
        ),
        const Gap(6),
        Text(
          '${(widget.elapsed.inMilliseconds / 1000).toStringAsFixed(2)} s / ${(widget.duration.inMilliseconds / 1000).toStringAsFixed(2)} s',
        ).small().muted(),
        StudioTimelineTracks(
          editor: widget.editor,
          duration: widget.duration,
          elapsed: widget.elapsed,
          fallbackDuration: widget.fallbackDuration,
        ),
      ],
    ),
  );
}
