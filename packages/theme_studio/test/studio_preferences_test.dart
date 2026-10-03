import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theme_studio/src/studio_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preferences persist independently of scene history', () async {
    SharedPreferences.setMockInitialValues({});
    expect((await StudioPreferences.load()).darkMode, isTrue);
    await const StudioPreferences(
      darkMode: false,
      showGrid: true,
      snapToGrid: true,
      gridSize: 32,
    ).save();
    final restored = await StudioPreferences.load();
    expect(restored.darkMode, isFalse);
    expect(restored.showGrid, isTrue);
    expect(restored.snapToGrid, isTrue);
    expect(restored.gridSize, 32);
  });

  test('corrupt stored preferences can be replaced with defaults', () async {
    SharedPreferences.setMockInitialValues({
      'mozais.studio.preferences': '{"gridSize":0}',
    });
    await expectLater(StudioPreferences.load(), throwsFormatException);
    await const StudioPreferences().save();
    expect((await StudioPreferences.load()).gridSize, 24);
  });
}
