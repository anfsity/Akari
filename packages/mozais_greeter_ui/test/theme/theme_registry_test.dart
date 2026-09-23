import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mozais_greeter_ui/mozais_greeter_ui.dart';
import 'package:mozais_scene/mozais_scene.dart';

void main() {
  test('resolves the imported document theme family by id', () {
    final document = _document('nocturne');

    final theme = ThemeRegistry.resolveDocument(
      document,
      seed: const Color(0xffd14a7a),
    );

    expect(theme.id, ThemeRegistry.nocturneThemeName);
    expect(theme.document, same(document));
  });

  test('builds the default palette from its extracted seed', () {
    final document = _document(ThemeRegistry.defaultThemeName);
    final warm = ThemeRegistry.resolveDocument(
      document,
      seed: const Color(0xffe53935),
    );
    final cool = ThemeRegistry.resolveDocument(
      document,
      seed: const Color(0xff1e88e5),
    );

    expect(
      warm.materialTheme.colorScheme.primary,
      isNot(cool.materialTheme.colorScheme.primary),
    );
    expect(warm.tokens.glassColor, isNot(cool.tokens.glassColor));
  });
}

SceneDocument _document(String id) {
  return SceneDocument(
    id: id,
    version: 1,
    canvas: const SceneCanvas(useSafeArea: false),
    background: const SceneBackground(kind: SceneBackgroundKind.solid),
    nodes: const [
      SceneNode(
        id: 'panel',
        kind: SceneNodeKind.glassPanel,
        rect: SceneRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
      ),
    ],
  );
}
