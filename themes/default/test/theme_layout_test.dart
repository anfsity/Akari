import 'package:flutter_test/flutter_test.dart';
import 'package:theme_default/theme.dart';
import 'package:theme_sdk/theme_sdk.dart';

void main() {
  test('both designed layouts compose all global presets and preserve customized text', () {
    final original = buildDefaultTheme();
    final layout = original.layout!;
    expect(layout.presets.keys, ['split', 'centered']);
    final heading = original.document.nodes.firstWhere(
      (node) => node.id == 'entrance_heading',
    );
    final customized = original.document.copyWith(
      nodes: [
        for (final node in original.document.nodes)
          if (node.id == heading.id)
            node.copyWith(
              properties: {'text': 'My desktop', 'variant': 'large'},
            )
          else if (node.id != 'hello_world')
            node,
      ],
    );
    for (final preset in layout.presets.keys) {
      for (final palette in original.presetCatalog.properties[0].choices.keys) {
        for (final material
            in original.presetCatalog.properties[1].choices.keys) {
          for (final motion
              in original.presetCatalog.properties[2].choices.keys) {
            final configured = layout.getDocumentWithPreset(
              customized.copyWith(
                themeProperties: {
                  'palette': palette.name,
                  'material': material.name,
                  'motion': motion.name,
                },
              ),
              preset,
            );
            final theme = buildDefaultTheme(
              document: decodeSceneDocument(encodeSceneDocument(configured)),
            );
            expect(theme.document.themeProperties['layout'], preset);
            expect(
              theme.document.nodes.any((node) => node.id == 'hello_world'),
              isFalse,
            );
            expect(
              theme.document.nodes
                  .firstWhere((node) => node.id == heading.id)
                  .properties['text'],
              'My desktop',
            );
            expect(
              theme.layout!.findMissingRequiredSlots(theme.document),
              isEmpty,
            );
            final credential = theme.document.nodes.firstWhere(
              (node) => node.id == 'credential_field',
            );
            expect(credential.rect.x, preset == 'centered' ? 0.3 : 0.085);
            expect(credential.interactive, isTrue);
          }
        }
      }
    }
  });

  test('layout templates form a complete valid login scene', () {
    final theme = buildDefaultTheme();
    final layout = theme.layout!;
    final document = decodeSceneDocument(
      encodeSceneDocument(
        theme.document.copyWith(
          nodes: [for (final slot in layout.slots) slot.defaultNode],
        ),
      ),
    );
    theme.componentCatalog.validateDocument(document);
    layout.validateDocument(document);
    expect(layout.findMissingRequiredSlots(document), isEmpty);
    expect(
      layout.slots.map((slot) => slot.defaultNode.id).toSet().length,
      layout.slots.length,
    );
    expect(
      layout.slots
          .where((slot) => slot.isRequired)
          .map((slot) => slot.defaultNode.id),
      containsAll([
        'credential_field',
        'primary_action',
        'account_picker',
        'session_picker',
        'status',
        'power_actions',
      ]),
    );
  });

  test('saved removals keep insertion defaults available after reopening', () {
    final theme = buildDefaultTheme();
    final document = decodeSceneDocument(
      encodeSceneDocument(
        theme.document.copyWith(
          nodes: [
            for (final node in theme.document.nodes)
              if (node.id != 'scene_signature' && node.id != 'credential_field')
                node,
          ],
        ),
      ),
    );
    final reopened = buildDefaultTheme(document: document);
    expect(
      reopened.document.nodes.any((node) => node.id == 'scene_signature'),
      isFalse,
    );
    expect(
      reopened.layout!.findSlot('scene_signature')!.defaultNode.properties,
      {'text': 'AKARI / ABOVE THE CITY'},
    );
    final missing = reopened.layout!.findMissingRequiredSlots(document);
    expect(missing.single.defaultNode.id, 'credential_field');
    final restored = buildDefaultTheme(
      document: document.copyWith(
        nodes: [...document.nodes, missing.single.defaultNode],
      ),
    );
    expect(
      restored.layout!.findMissingRequiredSlots(restored.document),
      isEmpty,
    );
    final credential = restored.document.nodes.last;
    expect(credential.interactive, isTrue);
    expect(credential.focusOrder, 30);
    expect(evaluateSceneCondition(credential.visibleWhen!, {}), isTrue);
    expect(
      evaluateSceneCondition(credential.visibleWhen!, {
        ScenePredicate.isDormant,
      }),
      isFalse,
    );
  });
}
