import 'dart:convert';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

enum StudioDock { left, right, floating }

enum StudioWorkspaceMode { design, motion, focus }

/// Workspace geometry is a user preference, independent of scene history.
class StudioWorkspaceLayout {
  const StudioWorkspaceLayout({
    this.mode = StudioWorkspaceMode.design,
    this.sidebarDock = StudioDock.left,
    this.inspectorDock = StudioDock.right,
    this.sidebarVisible = true,
    this.inspectorVisible = true,
    this.leftWidth = 232,
    this.rightWidth = 280,
    this.sidebarBounds = const Rect.fromLTWH(16, 16, 300, 520),
    this.inspectorBounds = const Rect.fromLTWH(460, 16, 300, 520),
  });

  static const storageKey = 'akari.studio.workspace';
  final StudioWorkspaceMode mode;
  final StudioDock sidebarDock;
  final StudioDock inspectorDock;
  final bool sidebarVisible;
  final bool inspectorVisible;
  final double leftWidth;
  final double rightWidth;
  final Rect sidebarBounds;
  final Rect inspectorBounds;

  static Future<StudioWorkspaceLayout> load() async {
    final storage = await SharedPreferences.getInstance();
    final source = storage.getString(storageKey);
    if (source == null) return const StudioWorkspaceLayout();
    return StudioWorkspaceLayout.decode(jsonDecode(source));
  }

  factory StudioWorkspaceLayout.decode(Object? value) {
    if (value is! Map ||
        value['sidebarVisible'] is! bool ||
        value['inspectorVisible'] is! bool) {
      throw const FormatException('Invalid saved workspace.');
    }
    double number(Object? value, double min, double max) {
      if (value is! num || !value.isFinite || value < min || value > max) {
        throw const FormatException('Invalid workspace dimensions.');
      }
      return value.toDouble();
    }

    StudioDock dock(Object? value) => StudioDock.values.firstWhere(
      (dock) => dock.name == value,
      orElse: () => throw const FormatException('Invalid dock position.'),
    );
    Rect bounds(Object? value) {
      if (value is! List || value.length != 4) {
        throw const FormatException('Invalid floating panel bounds.');
      }
      return Rect.fromLTWH(
        number(value[0], 0, 16384),
        number(value[1], 0, 16384),
        number(value[2], 216, 900),
        number(value[3], 200, 1600),
      );
    }

    return StudioWorkspaceLayout(
      mode: StudioWorkspaceMode.values.firstWhere(
        (mode) => mode.name == value['mode'],
        orElse: () => throw const FormatException('Invalid workspace mode.'),
      ),
      sidebarDock: dock(value['sidebarDock']),
      inspectorDock: dock(value['inspectorDock']),
      sidebarVisible: value['sidebarVisible'] as bool,
      inspectorVisible: value['inspectorVisible'] as bool,
      leftWidth: number(value['leftWidth'], 216, 360),
      rightWidth: number(value['rightWidth'], 260, 420),
      sidebarBounds: bounds(value['sidebarBounds']),
      inspectorBounds: bounds(value['inspectorBounds']),
    );
  }

  Future<void> save() async {
    final storage = await SharedPreferences.getInstance();
    List<double> bounds(Rect rect) => [
      rect.left,
      rect.top,
      rect.width,
      rect.height,
    ];
    final saved = await storage.setString(
      storageKey,
      jsonEncode({
        'mode': mode.name,
        'sidebarDock': sidebarDock.name,
        'inspectorDock': inspectorDock.name,
        'sidebarVisible': sidebarVisible,
        'inspectorVisible': inspectorVisible,
        'leftWidth': leftWidth,
        'rightWidth': rightWidth,
        'sidebarBounds': bounds(sidebarBounds),
        'inspectorBounds': bounds(inspectorBounds),
      }),
    );
    if (!saved) throw StateError('Could not save the workspace.');
  }
}
