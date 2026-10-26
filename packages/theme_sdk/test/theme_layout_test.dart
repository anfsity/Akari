import 'package:flutter_test/flutter_test.dart';
import 'package:theme_sdk/theme_sdk.dart';

const _credential = SceneNode(
  id: 'credential',
  componentId: 'credentialField',
  rect: SceneRect(x: 0.1, y: 0.5, width: 0.4, height: 0.1),
  focusOrder: 10,
  interactive: true,
  visibleWhen: SceneNot(ScenePredicateCondition(ScenePredicate.isDormant)),
);
const _caption = SceneNode(
  id: 'caption',
  componentId: 'label',
  rect: SceneRect(x: 0.1, y: 0.2, width: 0.4, height: 0.1),
  properties: {'text': 'Welcome'},
);
const _layout = ThemeLayoutDefinition(
  sceneId: 'login',
  label: 'Centered',
  slots: [
    ThemeLayoutSlot(
      label: 'Credential',
      defaultNode: _credential,
      isRequired: true,
    ),
    ThemeLayoutSlot(label: 'Caption', defaultNode: _caption),
  ],
);
const _document = SceneDocument(
  id: 'login',
  version: currentSceneVersion,
  canvas: SceneCanvas(),
  background: SceneBackground(kind: SceneBackgroundKind.solid),
  nodes: [_credential, _caption],
);

void main() {
  test('slot templates do not override authored geometry or properties', () {
    final document = _document.copyWith(
      nodes: [
        _credential,
        _caption.copyWith(
          rect: const SceneRect(x: 0.3, y: 0.1, width: 0.5, height: 0.2),
          properties: {'text': 'My desktop', 'private': 'keep'},
        ),
        _caption.copyWith(id: 'custom-caption'),
      ],
    );
    final encoded = encodeSceneDocument(document);
    _layout.validateDocument(document);
    expect(_layout.findMissingRequiredSlots(document), isEmpty);
    expect(encodeSceneDocument(document), encoded);
    expect(_layout.findSlot('caption')!.defaultNode.properties, {
      'text': 'Welcome',
    });
    expect(_layout.findSlot('custom-caption'), isNull);
  });

  test(
    'missing required slots can be discovered without rejecting a scene',
    () {
      final document = _document.copyWith(nodes: [_caption]);
      _layout.validateDocument(document);
      expect(
        _layout.findMissingRequiredSlots(document).single.defaultNode,
        _credential,
      );
      expect(
        _layout.findMissingRequiredSlots(
          _document.copyWith(nodes: [_credential]),
        ),
        isEmpty,
      );
    },
  );

  test('reserved IDs reject conflicting components', () {
    expect(
      () => _layout.validateDocument(
        _document.copyWith(nodes: [_credential.copyWith(componentId: 'label')]),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('slot "credential" requires component "credentialField"'),
        ),
      ),
    );
  });

  test('layout rules apply only to their declared scene', () {
    final other = _document.copyWith(
      id: 'other',
      nodes: [_credential.copyWith(componentId: 'custom')],
    );
    _layout.validateDocument(other);
    expect(_layout.findMissingRequiredSlots(other), isEmpty);
  });
}
