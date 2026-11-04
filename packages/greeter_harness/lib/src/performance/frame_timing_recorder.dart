import 'dart:async';
import 'dart:ui' show FrameTiming, PlatformDispatcher;

import 'package:flutter/scheduler.dart';

/// Owns phase attribution and timing callbacks for one performance journey.
/// Engine batches can arrive after the next phase starts, so frames are matched
/// by their engine number recorded at frame start, never by callback time.
class FrameTimingRecorder {
  FrameTimingRecorder({
    required this.activePhase,
    this.interactionPhases = const {},
  }) : phaseTimings = {activePhase: []};

  String activePhase;
  final Set<String> interactionPhases;
  final Map<String, List<FrameTiming>> phaseTimings;
  final interactionTimings = <FrameTiming>[];
  final actionResponseTimings = <String, List<FrameTiming>>{};
  final _phaseAtFrameStart = <int, ({String phase, bool actionResponse})>{};
  var observedFrameCount = 0;
  var unmatchedFrameCount = 0;
  var _recording = false;
  Completer<void>? _actionFrame;

  void start() {
    _recording = true;
    // Persistent callbacks cannot be removed; a weak reference lets completed
    // journeys and their timing samples be collected after stop().
    final recorder = WeakReference(this);
    SchedulerBinding.instance.addPersistentFrameCallback(
      (elapsed) => recorder.target?._recordFramePhase(elapsed),
    );
    SchedulerBinding.instance.addTimingsCallback(_recordTimings);
  }

  void stop() {
    // Disable attribution before unregistering timing delivery.
    _recording = false;
    _phaseAtFrameStart.clear();
    SchedulerBinding.instance.removeTimingsCallback(_recordTimings);
  }

  Future<void> captureAction(
    String phase,
    Future<void> Function() action,
  ) async {
    activePhase = phase;
    final firstFrame = Completer<void>();
    _actionFrame = firstFrame;
    try {
      await action();
      await firstFrame.future.timeout(const Duration(seconds: 10));
    } finally {
      _actionFrame = null;
    }
  }

  void _recordFramePhase(Duration _) {
    if (!_recording) return;
    final frameNumber = PlatformDispatcher.instance.frameData.frameNumber;
    if (frameNumber < 0) return;
    _phaseAtFrameStart[frameNumber] = (
      phase: activePhase,
      actionResponse: _actionFrame != null,
    );
    _actionFrame?.complete();
    _actionFrame = null;
  }

  void _recordTimings(List<FrameTiming> batch) {
    for (final timing in batch) {
      observedFrameCount++;
      final frame = timing.frameNumber < 0
          ? null
          : _phaseAtFrameStart.remove(timing.frameNumber);
      if (frame == null) {
        unmatchedFrameCount++;
        continue;
      }
      phaseTimings.putIfAbsent(frame.phase, () => []).add(timing);
      if (interactionPhases.contains(frame.phase)) {
        interactionTimings.add(timing);
        if (frame.actionResponse) {
          actionResponseTimings.putIfAbsent(frame.phase, () => []).add(timing);
        }
      }
    }
  }
}
