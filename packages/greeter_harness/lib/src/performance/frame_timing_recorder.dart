import 'dart:async';
import 'dart:ui' show FrameTiming, PlatformDispatcher;

import 'package:flutter/scheduler.dart';

/// Owns phase attribution and timing callbacks for one performance journey.
/// Engine batches can arrive after the next phase starts, so frames are matched
/// by their engine number recorded at frame start, never by callback time.
class FrameTimingRecorder {
  FrameTimingRecorder({
    required String activePhase,
    this.interactionPhases = const {},
  }) : _activePhase = activePhase,
       phaseTimings = {activePhase: []} {
    if (interactionPhases.contains(activePhase)) {
      actionResponseTimings[activePhase] = [];
    }
  }

  String _activePhase;
  String get activePhase => _activePhase;
  set activePhase(String value) {
    _activePhase = value;
    phaseTimings.putIfAbsent(value, () => []);
    if (interactionPhases.contains(value)) {
      actionResponseTimings.putIfAbsent(value, () => []);
    }
  }

  final Set<String> interactionPhases;
  final Map<String, List<FrameTiming>> phaseTimings;
  final interactionTimings = <FrameTiming>[];
  final actionResponseTimings = <String, List<FrameTiming>>{};
  final _phaseAtFrameStart = <int, ({String phase, bool actionResponse})>{};
  var observedFrameCount = 0;
  var unmatchedFrameCount = 0;
  var _recording = false;
  var _persistentCallbackRegistered = false;
  var _timingsCallbackRegistered = false;
  Completer<void>? _actionFrame;
  Completer<void>? _drainCompleter;

  void start() {
    if (_recording) {
      return;
    }
    _recording = true;
    if (!_persistentCallbackRegistered) {
      _persistentCallbackRegistered = true;
      // Persistent callbacks cannot be removed; a weak reference lets
      // completed journeys and their timing samples be collected after stop().
      final recorder = WeakReference(this);
      SchedulerBinding.instance.addPersistentFrameCallback(
        (elapsed) => recorder.target?._recordFramePhase(elapsed),
      );
    }
    if (!_timingsCallbackRegistered) {
      _timingsCallbackRegistered = true;
      SchedulerBinding.instance.addTimingsCallback(_recordTimings);
    }
  }

  void stop() {
    // Disable attribution before unregistering timing delivery.
    _recording = false;
    _phaseAtFrameStart.clear();
    if (_timingsCallbackRegistered) {
      _timingsCallbackRegistered = false;
      SchedulerBinding.instance.removeTimingsCallback(_recordTimings);
    }
    if (_actionFrame case final pending? when !pending.isCompleted) {
      pending.completeError(
        StateError('FrameTimingRecorder stopped before a frame was recorded.'),
      );
    }
    if (_drainCompleter case final pending? when !pending.isCompleted) {
      pending.complete();
    }
  }

  /// Stops recording new frames, waits briefly for in-flight engine timing
  /// batches already started during this session, and then calls [stop].
  Future<void> drain({
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    _recording = false;
    if (_phaseAtFrameStart.isNotEmpty && _timingsCallbackRegistered) {
      final completer = _drainCompleter ??= Completer<void>();
      await completer.future.timeout(timeout, onTimeout: () {});
    }
    stop();
  }

  Future<void> captureAction(
    String phase,
    Future<void> Function() action, {
    Duration frameTimeout = const Duration(seconds: 10),
  }) async {
    if (!_recording) {
      throw StateError('FrameTimingRecorder is not started.');
    }
    activePhase = phase;
    final firstFrame = Completer<void>();
    _actionFrame = firstFrame;
    try {
      await action();
      await firstFrame.future.timeout(frameTimeout);
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
    if (!_recording &&
        _phaseAtFrameStart.isEmpty &&
        _drainCompleter != null &&
        !_drainCompleter!.isCompleted) {
      _drainCompleter!.complete();
      _drainCompleter = null;
    }
  }
}
