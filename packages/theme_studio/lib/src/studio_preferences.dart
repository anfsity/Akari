import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class StudioPreferences {
  const StudioPreferences({
    this.darkMode = true,
    this.showGrid = false,
    this.snapToGrid = false,
    this.gridSize = 24,
  });

  final bool darkMode;
  final bool showGrid;
  final bool snapToGrid;
  final int gridSize;

  static void validateGridSize(int size) {
    if (size < 4 || size > 512) {
      throw const FormatException(
        'Grid size must be between 4 and 512 pixels.',
      );
    }
  }

  static Future<StudioPreferences> load() async {
    final storage = await SharedPreferences.getInstance();
    final source = storage.getString('mozais.studio.preferences');
    if (source == null) return const StudioPreferences();
    final json = jsonDecode(source);
    if (json is! Map<String, dynamic> ||
        json['darkMode'] is! bool ||
        json['showGrid'] is! bool ||
        json['snapToGrid'] is! bool ||
        json['gridSize'] is! int) {
      throw const FormatException(
        'Invalid Studio preferences. Apply Settings to reset them.',
      );
    }
    validateGridSize(json['gridSize'] as int);
    return StudioPreferences(
      darkMode: json['darkMode'] as bool,
      showGrid: json['showGrid'] as bool,
      snapToGrid: json['snapToGrid'] as bool,
      gridSize: json['gridSize'] as int,
    );
  }

  Future<void> save() async {
    final storage = await SharedPreferences.getInstance();
    final saved = await storage.setString(
      'mozais.studio.preferences',
      jsonEncode({
        'darkMode': darkMode,
        'showGrid': showGrid,
        'snapToGrid': snapToGrid,
        'gridSize': gridSize,
      }),
    );
    if (!saved) throw StateError('Unable to save Studio preferences.');
  }
}
