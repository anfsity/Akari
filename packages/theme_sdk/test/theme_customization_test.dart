import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theme_sdk/theme_sdk.dart';

enum _Style { regular, large }

const _text = ThemeTextProperty(
  name: 'text',
  label: 'Text',
  defaultValue: 'Welcome',
);
const _style = ThemeChoiceProperty(
  name: 'variant',
  label: 'Text style',
  defaultValue: _Style.regular,
  choices: {_Style.regular: 'Regular', _Style.large: 'Large'},
);
const _catalog = ThemeComponentCatalog(
  components: {
    'label': ThemeComponentDefinition(
      label: 'Label',
      properties: [_text, _style],
    ),
  },
);
const _presets = ThemePresetCatalog(properties: [_style]);

SceneDocument _getDocument(Map<String, String> properties) => SceneDocument(
  id: 'test',
  version: currentSceneVersion,
  canvas: const SceneCanvas(),
  background: const SceneBackground(kind: SceneBackgroundKind.solid),
  nodes: [
    SceneNode(
      id: 'heading',
      componentId: 'label',
      rect: const SceneRect(x: 0, y: 0, width: 1, height: 1),
      properties: properties,
    ),
  ],
);

void main() {
  test('copying a theme preserves its editing catalog', () {
    final theme = ThemeDefinition(
      id: 'test',
      document: _getDocument({}),
      componentCatalog: _catalog,
      presetCatalog: _presets,
      layout: const ThemeLayoutDefinition(
        sceneId: 'test',
        label: 'Test',
        slots: [],
      ),
      components: (_) => throw UnimplementedError(),
      bundle: ThemeBundle(
        tokens: ThemeTokens(
          materialTheme: ThemeData(),
          panelRadius: 0,
          mediumMotion: Duration.zero,
          standardCurve: Curves.linear,
          minHitTarget: 44,
          surfaceColor: Colors.transparent,
          surfaceVariantColor: Colors.transparent,
        ),
      ),
    );
    expect(theme.copyWith(id: 'copy').componentCatalog, same(_catalog));
    expect(theme.copyWith(id: 'copy').presetCatalog, same(_presets));
    expect(theme.copyWith(id: 'copy').layout, same(theme.layout));
  });
}
