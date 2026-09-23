import 'package:flutter/material.dart';

/// Editor-only palettes. These style the authoring UI and never touch the
/// greeter's compile-time `ThemeTokens`.
enum EditorThemeId {
  catppuccinLatte,
  catppuccinMocha,
  tokyoNight,
  githubLight,
  githubDark,
  nord,
  dracula,
}

/// A named palette mapped onto a Material [ColorScheme].
class EditorTheme {
  const EditorTheme({
    required this.id,
    required this.name,
    required this.palette,
  });

  final EditorThemeId id;
  final String name;
  final EditorPalette palette;

  ColorScheme get colorScheme {
    final base = ColorScheme.fromSeed(
      seedColor: palette.accent,
      brightness: palette.brightness,
    );
    return base.copyWith(
      surface: palette.background,
      onSurface: palette.foreground,
      surfaceContainerLowest: palette.background,
      surfaceContainerLow: palette.surface,
      surfaceContainer: palette.surface,
      surfaceContainerHigh: palette.surfaceVariant,
      surfaceContainerHighest: palette.surfaceVariant,
      outline: palette.outline,
      outlineVariant: palette.outline.withValues(alpha: 0.5),
      onSurfaceVariant: palette.foreground.withValues(alpha: 0.72),
    );
  }

  ThemeData toThemeData() {
    final scheme = colorScheme;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.background,
      dividerColor: palette.outline.withValues(alpha: 0.6),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.surface,
        foregroundColor: palette.foreground,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: palette.outline.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}

/// Raw colors for one editor theme.
class EditorPalette {
  const EditorPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.outline,
    required this.foreground,
    required this.accent,
  });

  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color outline;
  final Color foreground;
  final Color accent;
}

const _catppuccinLatte = EditorPalette(
  brightness: Brightness.light,
  background: Color(0xffeff1f5),
  surface: Color(0xffe6e9ef),
  surfaceVariant: Color(0xffccd0da),
  outline: Color(0xff9ca0b0),
  foreground: Color(0xff4c4f69),
  accent: Color(0xff1e66f5),
);

const _catppuccinMocha = EditorPalette(
  brightness: Brightness.dark,
  background: Color(0xff1e1e2e),
  surface: Color(0xff181825),
  surfaceVariant: Color(0xff313244),
  outline: Color(0xff6c7086),
  foreground: Color(0xffcdd6f4),
  accent: Color(0xff89b4fa),
);

const _tokyoNight = EditorPalette(
  brightness: Brightness.dark,
  background: Color(0xff1a1b26),
  surface: Color(0xff16161e),
  surfaceVariant: Color(0xff292e42),
  outline: Color(0xff565f89),
  foreground: Color(0xffc0caf5),
  accent: Color(0xff7aa2f7),
);

const _githubLight = EditorPalette(
  brightness: Brightness.light,
  background: Color(0xffffffff),
  surface: Color(0xfff6f8fa),
  surfaceVariant: Color(0xffeaeef2),
  outline: Color(0xffd0d7de),
  foreground: Color(0xff1f2328),
  accent: Color(0xff0969da),
);

const _githubDark = EditorPalette(
  brightness: Brightness.dark,
  background: Color(0xff0d1117),
  surface: Color(0xff161b22),
  surfaceVariant: Color(0xff21262d),
  outline: Color(0xff30363d),
  foreground: Color(0xffc9d1d9),
  accent: Color(0xff58a6ff),
);

const _nord = EditorPalette(
  brightness: Brightness.dark,
  background: Color(0xff2e3440),
  surface: Color(0xff3b4252),
  surfaceVariant: Color(0xff434c5e),
  outline: Color(0xff4c566a),
  foreground: Color(0xffeceff4),
  accent: Color(0xff88c0d0),
);

const _dracula = EditorPalette(
  brightness: Brightness.dark,
  background: Color(0xff282a36),
  surface: Color(0xff21222c),
  surfaceVariant: Color(0xff44475a),
  outline: Color(0xff6272a4),
  foreground: Color(0xfff8f8f2),
  accent: Color(0xffbd93f9),
);

const editorThemes = <EditorThemeId, EditorTheme>{
  EditorThemeId.catppuccinLatte: EditorTheme(
    id: EditorThemeId.catppuccinLatte,
    name: 'Catppuccin Latte',
    palette: _catppuccinLatte,
  ),
  EditorThemeId.catppuccinMocha: EditorTheme(
    id: EditorThemeId.catppuccinMocha,
    name: 'Catppuccin Mocha',
    palette: _catppuccinMocha,
  ),
  EditorThemeId.tokyoNight: EditorTheme(
    id: EditorThemeId.tokyoNight,
    name: 'Tokyo Night',
    palette: _tokyoNight,
  ),
  EditorThemeId.githubLight: EditorTheme(
    id: EditorThemeId.githubLight,
    name: 'GitHub Light',
    palette: _githubLight,
  ),
  EditorThemeId.githubDark: EditorTheme(
    id: EditorThemeId.githubDark,
    name: 'GitHub Dark',
    palette: _githubDark,
  ),
  EditorThemeId.nord: EditorTheme(
    id: EditorThemeId.nord,
    name: 'Nord',
    palette: _nord,
  ),
  EditorThemeId.dracula: EditorTheme(
    id: EditorThemeId.dracula,
    name: 'Dracula',
    palette: _dracula,
  ),
};

EditorTheme editorThemeFor(EditorThemeId id) => editorThemes[id]!;

const _brightnessPairs = <EditorThemeId, EditorThemeId>{
  EditorThemeId.catppuccinLatte: EditorThemeId.catppuccinMocha,
  EditorThemeId.catppuccinMocha: EditorThemeId.catppuccinLatte,
  EditorThemeId.githubLight: EditorThemeId.githubDark,
  EditorThemeId.githubDark: EditorThemeId.githubLight,
};

/// The same theme family in the opposite brightness.
///
/// Palettes without an explicit partner fall back to a default of the target
/// brightness so the light/dark toggle always has a destination.
EditorThemeId toggledThemeBrightness(EditorThemeId id) {
  final paired = _brightnessPairs[id];
  if (paired != null) {
    return paired;
  }
  return editorThemeFor(id).palette.brightness == Brightness.dark
      ? EditorThemeId.catppuccinLatte
      : EditorThemeId.catppuccinMocha;
}
