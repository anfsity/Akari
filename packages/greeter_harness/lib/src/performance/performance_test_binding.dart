import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Allow application-requested frames without the live test binding's extra
/// frame after every draw. That automatic reschedule otherwise keeps a static
/// scene rendering and makes the idle and vsync measurements describe the test
/// harness. Requests made by application code during a draw still pass through.
class PerformanceTestBinding extends IntegrationTestWidgetsFlutterBinding {
  PerformanceTestBinding() {
    framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;
  }

  @override
  void handleDrawFrame() => _runWithFramePolicy(
    LiveTestWidgetsFlutterBindingFramePolicy.benchmark,
    super.handleDrawFrame,
  );

  @override
  void scheduleFrame() => _runWithFramePolicy(
    LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive,
    super.scheduleFrame,
  );

  @override
  void scheduleForcedFrame() => _runWithFramePolicy(
    LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive,
    super.scheduleForcedFrame,
  );

  void _runWithFramePolicy(
    LiveTestWidgetsFlutterBindingFramePolicy policy,
    VoidCallback action,
  ) {
    final previous = framePolicy;
    framePolicy = policy;
    try {
      action();
    } finally {
      framePolicy = previous;
    }
  }
}
