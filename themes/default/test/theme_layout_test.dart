import 'package:flutter_test/flutter_test.dart';
import 'package:theme_default/theme.dart';
import 'package:theme_sdk/theme_sdk.dart';

void main() {
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
