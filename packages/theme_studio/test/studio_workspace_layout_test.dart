import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theme_studio/src/studio_workspace_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('workspace docking widths and floating bounds persist independently', () async {
    SharedPreferences.setMockInitialValues({});
    await const StudioWorkspaceLayout(mode: StudioWorkspaceMode.motion,
      sidebarDock: StudioDock.right, inspectorDock: StudioDock.floating,
      sidebarVisible: false, leftWidth: 240, rightWidth: 320,
      inspectorBounds: Rect.fromLTWH(100, 80, 320, 480)).save();
    final restored = await StudioWorkspaceLayout.load();
    expect(restored.mode, StudioWorkspaceMode.motion);
    expect(restored.sidebarDock, StudioDock.right);
    expect(restored.inspectorDock, StudioDock.floating);
    expect(restored.sidebarVisible, isFalse);
    expect(restored.leftWidth, 240); expect(restored.rightWidth, 320);
    expect(restored.inspectorBounds, const Rect.fromLTWH(100, 80, 320, 480));
    expect(() => StudioWorkspaceLayout.decode({'sidebarVisible': true, 'inspectorVisible': true}), throwsFormatException);
  });
}
