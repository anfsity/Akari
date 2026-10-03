import 'dart:convert';

import 'package:shadcn_flutter/shadcn_flutter.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import 'studio_theme.dart';

class StudioPreferences {
  const StudioPreferences({
    this.themeMode = ThemeMode.system,
    this.palette = StudioPalette.zinc,
    this.showGrid = false,
    this.snapToGrid = false,
    this.gridSize = 24,
  });

  final ThemeMode themeMode;
  final StudioPalette palette;
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
        json['showGrid'] is! bool ||
        json['snapToGrid'] is! bool ||
        json['gridSize'] is! int) {
      throw const FormatException(
        'Invalid Studio preferences. Apply Settings to reset them.',
      );
    }
    validateGridSize(json['gridSize'] as int);
    // Older Studio versions stored only a darkMode boolean. Keep that user's
    // explicit choice when migrating to the three-way appearance setting.
    final ThemeMode themeMode;
    if (json.containsKey('themeMode')) {
      themeMode = ThemeMode.values.firstWhere(
        (mode) => mode.name == json['themeMode'],
        orElse: () => throw const FormatException('Invalid appearance mode.'),
      );
    } else if (json['darkMode'] is bool) {
      themeMode = json['darkMode'] as bool ? ThemeMode.dark : ThemeMode.light;
    } else {
      throw const FormatException('Invalid appearance mode.');
    }
    final palette = json.containsKey('palette')
        ? StudioPalette.values.firstWhere(
            (palette) => palette.name == json['palette'],
            orElse: () =>
                throw const FormatException('Invalid editor palette.'),
          )
        : StudioPalette.zinc;
    return StudioPreferences(
      themeMode: themeMode,
      palette: palette,
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
        'themeMode': themeMode.name,
        'palette': palette.name,
        'showGrid': showGrid,
        'snapToGrid': snapToGrid,
        'gridSize': gridSize,
      }),
    );
    if (!saved) throw StateError('Unable to save Studio preferences.');
  }
}
