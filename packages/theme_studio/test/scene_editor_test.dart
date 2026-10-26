import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:theme_sdk/theme_sdk.dart';
import 'package:theme_studio/src/scene_editor.dart';
import 'package:theme_studio/src/node_inspector_controller.dart';

enum _PanelVariant { compact, wide }

const _catalog = ThemeComponentCatalog(
  components: {
    'panel': ThemeComponentDefinition(
      label: 'Panel',
      properties: [
        ThemeChoiceProperty(
          name: 'variant',
          label: 'Style',
          defaultValue: _PanelVariant.compact,
          choices: {
            _PanelVariant.compact: 'Compact',
            _PanelVariant.wide: 'Wide',
          },
        ),
      ],
    ),
  },
);

const _caption = SceneNode(
  id: 'caption',
  componentId: 'label',
  rect: SceneRect(x: 0.2, y: 0.05, width: 0.4, height: 0.1),
  renderOrder: 20,
  motion: SceneMotionPreset.fadeSlide,
  visibleWhen: ScenePredicateCondition(ScenePredicate.isDormant),
  properties: {'text': 'Welcome'},
);
const _action = SceneNode(
  id: 'action',
  componentId: 'primaryAction',
  rect: SceneRect(x: 0.6, y: 0.5, width: 0.1, height: 0.1),
  interactive: true,
  focusOrder: 40,
);
const _layout = ThemeLayoutDefinition(
  sceneId: 'test',
  label: 'Test layout',
  slots: [
    ThemeLayoutSlot(
      label: 'Login panel',
      isRequired: true,
      defaultNode: SceneNode(
        id: 'panel',
        componentId: 'panel',
        rect: SceneRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5),
        properties: {'variant': 'compact'},
      ),
    ),
    ThemeLayoutSlot(label: 'Standby caption', defaultNode: _caption),
    ThemeLayoutSlot(label: 'Sign in', defaultNode: _action, isRequired: true),
  ],
);

void main() {
  late Directory directory;
  late File file;
  late SceneEditor editor;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('scene-editor-');
    file = File('${directory.path}/test.scene.json')
      ..writeAsStringSync(
        encodeSceneDocument(
          const SceneDocument(
            id: 'test',
            version: currentSceneVersion,
            canvas: SceneCanvas(),
            background: SceneBackground(kind: SceneBackgroundKind.solid),
            nodes: [
              SceneNode(
                id: 'panel',
                componentId: 'panel',
                rect: SceneRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5),
                transform: SceneTransform(pivotX: 0.2),
                properties: {'variant': 'compact'},
              ),
            ],
          ),
        ),
      );
    editor = SceneEditor(file);
  });

  tearDown(() {
    editor.dispose();
    directory.deleteSync(recursive: true);
  });

  test(
    'slot insertion, edits, removal and restoration use document history',
    () {
      editor.updateAuthoring(componentCatalog: _catalog, layout: _layout);
      final original = editor.encodedDocument;
      editor.updateLayoutSlot('caption', isPresent: true);
      expect(editor.selectedId, 'caption');
      expect(editor.selectedNode.properties, {'text': 'Welcome'});
      expect(editor.selectedNode.rect.x, 0.2);
      expect(editor.selectedNode.motion, SceneMotionPreset.fadeSlide);
      expect(
        evaluateSceneCondition(editor.selectedNode.visibleWhen!, {}),
        isFalse,
      );
      editor.updateLayoutSlot('caption', isPresent: true);
      expect(editor.document.nodes, hasLength(2));
      editor.undo();
      expect(editor.encodedDocument, original);
      expect(editor.selectedId, 'panel');
      expect(editor.canUndo, isFalse);
      editor.redo();
      editor.inspector.updateProperty('text', 'Edited caption');
      editor.inspector.getField('X').text = '576';
      editor.applyDraft();
      editor.selectNode('panel');
      editor.updateLayoutSlot('caption', isPresent: false);
      expect(editor.selectedId, 'panel');
      editor.undo();
      expect(editor.selectedId, 'panel');
      final restored = editor.document.nodes.singleWhere(
        (node) => node.id == 'caption',
      );
      expect(restored.properties, {'text': 'Edited caption'});
      expect(restored.rect.x, 0.3);
      editor.redo();
      editor.save();
      editor.dispose();
      editor = SceneEditor(file, componentCatalog: _catalog, layout: _layout);
      editor.updateLayoutSlot('caption', isPresent: true);
      expect(editor.selectedNode.properties, {'text': 'Welcome'});
      expect(editor.selectedNode.rect.x, 0.2);
      editor.updateLayoutSlot('caption', isPresent: false);
      expect(editor.document.nodes, hasLength(1));
      expect(editor.selectedId, 'panel');
    },
  );

  test(
    'required slots are protected and missing slots are repaired in one edit',
    () {
      editor.updateAuthoring(componentCatalog: _catalog, layout: _layout);
      expect(editor.missingRequiredSlots.single.defaultNode.id, 'action');
      editor.addRequiredLayoutSlots();
      expect(editor.selectedId, 'action');
      expect(editor.missingRequiredSlots, isEmpty);
      expect(editor.selectedNode.interactive, isTrue);
      expect(editor.selectedNode.focusOrder, 40);
      expect(editor.canDeleteNode, isFalse);
      expect(editor.deletionBlockReason, 'Sign in is required by this layout.');
      expect(editor.deleteSelectedNode, throwsStateError);
      expect(
        () => editor.updateLayoutSlot('panel', isPresent: false),
        throwsStateError,
      );
      expect(editor.canDuplicateNode, isFalse);
      expect(editor.duplicateSelectedNode, throwsStateError);
      editor.addRequiredLayoutSlots();
      editor.undo();
      expect(editor.document.nodes, hasLength(1));
      expect(editor.canUndo, isFalse);
      editor.redo();
      editor.save();
      editor.reload();
      expect(editor.missingRequiredSlots, isEmpty);
    },
  );

  test(
    'invalid drafts block assembly commands without changing the document',
    () {
      editor.updateAuthoring(componentCatalog: _catalog, layout: _layout);
      final original = editor.encodedDocument;
      editor.inspector.getField('Width').text = '3840';
      editor.updateLayoutSlot('caption', isPresent: true);
      editor.updateLayoutSlot('panel', isPresent: false);
      editor.addRequiredLayoutSlots();
      expect(editor.encodedDocument, original);
      expect(editor.canUndo, isFalse);
      expect(editor.inspector.error, isNotNull);
    },
  );

  test('layout reservations validate loads and edits, with opt-out for other scenes', () {
    editor.updateAuthoring(componentCatalog: _catalog, layout: _layout);
    final original = editor.document;
    expect(
      () =>
          editor.updateNode(editor.selectedNode.copyWith(componentId: 'label')),
      throwsFormatException,
    );
    expect(
      () => editor.updateLayoutSlot('unknown', isPresent: true),
      throwsArgumentError,
    );
    expect(editor.document, same(original));
    file.writeAsStringSync(
      encodeSceneDocument(
        original.copyWith(
          nodes: [original.nodes.single.copyWith(componentId: 'label')],
        ),
      ),
    );
    expect(() => SceneEditor(file, layout: _layout), throwsFormatException);
    expect(editor.reload, throwsFormatException);
    expect(editor.document, same(original));
    file.writeAsStringSync(encodeSceneDocument(original.copyWith(id: 'other')));
    editor.reload();
    expect(editor.layout, isNull);
    expect(editor.missingRequiredSlots, isEmpty);
    expect(editor.canDuplicateNode, isTrue);
    editor.duplicateSelectedNode();
    expect(editor.canDeleteNode, isTrue);
  });

  test(
    'hot-reloaded layout and catalog replace atomically against history',
    () {
      editor.updateNode(editor.selectedNode.copyWith(componentId: 'label'));
      editor.updateNode(editor.selectedNode.copyWith(componentId: 'panel'));
      expect(
        () =>
            editor.updateAuthoring(componentCatalog: _catalog, layout: _layout),
        throwsFormatException,
      );
      expect(editor.layout, isNull);
      expect(editor.componentCatalog.components, isEmpty);
      editor.undo();
      expect(editor.selectedNode.componentId, 'label');
    },
  );

  test('theme choices validate drafts before preview, history and saving', () {
    editor.updateAuthoring(componentCatalog: _catalog, layout: null);
    editor.inspector.updateProperty('variant', 'wide');
    expect(editor.applyDraft(), isTrue);
    final valid = editor.document;
    editor.inspector.updateProperty('variant', 'unsupported');
    expect(editor.applyDraft(), isFalse);
    expect(editor.save(), isFalse);
    expect(editor.document, same(valid));
    expect(
      editor.inspector.error,
      contains('Node "panel": Property "variant"'),
    );
    expect(
      decodeSceneDocument(file.readAsStringSync()).nodes.single.properties,
      {'variant': 'compact'},
    );

    editor.inspector.updateProperty('variant', 'compact');
    expect(editor.applyDraft(), isTrue);
    editor.undo();
    expect(editor.selectedNode.properties['variant'], 'wide');
    editor.undo();
    expect(editor.selectedNode.properties['variant'], 'compact');
    expect(editor.canUndo, isFalse);
    editor.redo();
    expect(editor.selectedNode.properties['variant'], 'wide');
  });

  test('invalid theme choices cannot load or replace a working session', () {
    editor.updateAuthoring(componentCatalog: _catalog, layout: null);
    final valid = editor.document;
    file.writeAsStringSync(
      encodeSceneDocument(
        valid.copyWith(
          nodes: [
            editor.selectedNode.copyWith(
              properties: {'variant': 'unsupported'},
            ),
          ],
        ),
      ),
    );
    expect(
      () => SceneEditor(file, componentCatalog: _catalog),
      throwsFormatException,
    );
    expect(editor.reload, throwsFormatException);
    expect(editor.document, same(valid));
    expect(editor.isDirty, isFalse);
    expect(editor.canUndo, isFalse);
  });

  test('catalog replacement preserves valid undo and redo history', () {
    editor.updateAuthoring(componentCatalog: _catalog, layout: null);
    editor.inspector.updateProperty('variant', 'wide');
    editor.applyDraft();
    const compactOnly = ThemeComponentCatalog(
      components: {
        'panel': ThemeComponentDefinition(
          label: 'Panel',
          properties: [
            ThemeChoiceProperty(
              name: 'variant',
              label: 'Style',
              defaultValue: _PanelVariant.compact,
              choices: {_PanelVariant.compact: 'Compact'},
            ),
          ],
        ),
      },
    );
    expect(
      () => editor.updateAuthoring(componentCatalog: compactOnly, layout: null),
      throwsFormatException,
    );
    editor.undo();
    expect(
      () => editor.updateAuthoring(componentCatalog: compactOnly, layout: null),
      throwsFormatException,
    );
    editor.redo();
    expect(editor.selectedNode.properties['variant'], 'wide');
    expect(editor.componentCatalog, same(_catalog));
    editor.inspector.updateProperty('private', 'keep');
    expect(editor.save(), isTrue);
    expect(
      decodeSceneDocument(file.readAsStringSync()).nodes.single.properties,
      {'variant': 'wide', 'private': 'keep'},
    );
  });

  test('edit, undo, redo and save preserve the complete scene', () {
    editor.updateNode(editor.selectedNode.copyWith(z: 3));
    expect(editor.isDirty, isTrue);
    editor.undo();
    expect(editor.isDirty, isFalse);
    expect(editor.selectedNode.z, 0);
    editor.redo();
    editor.save();
    final restored = decodeSceneDocument(file.readAsStringSync());
    expect(restored.nodes.single.z, 3);
    expect(restored.nodes.single.transform.pivotX, 0.2);
    expect(restored.nodes.single.properties, {'variant': 'compact'});
    expect(editor.isDirty, isFalse);
    editor.undo();
    expect(editor.isDirty, isTrue);
    editor.redo();
    expect(editor.isDirty, isFalse);
    expect(directory.listSync(), hasLength(1));
  });

  test('draft commands work without a mounted inspector', () {
    editor.inspector.getField('X').text = '384';
    editor.undo();
    expect(editor.selectedNode.rect.x, 0.1);
    expect(editor.inspector.hasDraft, isFalse);
    editor.redo();
    expect(editor.selectedNode.rect.x, 0.2);

    editor.inspector.getField('X').text = '576';
    editor.duplicateSelectedNode();
    expect(editor.document.nodes.map((node) => node.rect.x), [0.3, 0.3]);
    editor.inspector.getField('X').text = '768';
    editor.selectNode('panel');
    expect(editor.document.nodes.last.rect.x, 0.4);
    expect(editor.inspector.getField('X').text, '576');

    editor.inspector.getField('X').text = '384';
    expect(editor.save(), isTrue);
    expect(
      decodeSceneDocument(file.readAsStringSync()).nodes.first.rect.x,
      0.2,
    );
  });

  test('invalid drafts block document commands and reload clears them', () {
    editor.duplicateSelectedNode();
    final document = editor.document;
    final source = file.readAsStringSync();
    editor.inspector.getField('Width').text = '3840';
    editor.undo();
    editor.redo();
    editor.duplicateSelectedNode();
    editor.deleteSelectedNode();
    editor.updateScene(canvas: const SceneCanvas(referenceWidth: 1600));
    expect(editor.selectNode('panel'), isFalse);
    expect(editor.save(), isFalse);
    expect(editor.document, same(document));
    expect(editor.selectedId, 'panel-copy');
    expect(file.readAsStringSync(), source);
    expect(editor.inspector.error, contains('non-normalized rect'));

    editor.reload();
    expect(editor.inspector.hasDraft, isFalse);
    expect(editor.inspector.error, isNull);
    expect(editor.inspector.getField('Width').text, '960');
  });

  test('equivalent drafts clear without creating history', () {
    editor.inspector.getField('X').text = '192.00';
    expect(editor.applyDraft(), isTrue);
    expect(editor.inspector.hasDraft, isFalse);
    expect(editor.canUndo, isFalse);
    expect(editor.isDirty, isFalse);
  });

  test('layout units preserve drafts, transforms and normalized storage', () {
    expect(editor.inspector.getField('Width').text, '960');
    editor.inspector.getField('X').text = '384';
    editor.inspector.getField('Rotate Z').text = '20';
    editor.inspector.updateLayoutUnit(StudioLayoutUnit.percent);
    expect(editor.inspector.getField('X').text, '20');
    expect(editor.inspector.getField('Width').text, '50');
    expect(editor.inspector.getField('Rotate Z').text, '20');
    expect(editor.canUndo, isFalse);
    expect(editor.inspector.hasDraft, isTrue);
    expect(editor.applyDraft(), isTrue);
    expect(editor.selectedNode.rect.x, 0.2);
    expect(editor.selectedNode.transform.rotationZ, 20);
    editor.undo();
    expect(editor.inspector.getField('X').text, '10');
    editor.inspector.updateLayoutUnit(StudioLayoutUnit.pixels);
    expect(editor.inspector.getField('X').text, '192');
    expect(editor.inspector.hasDraft, isFalse);
  });

  test(
    'pixel dimensions follow canvas settings and retain geometry precision',
    () {
      editor.updateNode(
        editor.selectedNode.copyWith(
          rect: editor.selectedNode.rect.copyWith(x: 0.123456789),
        ),
      );
      final original = encodeSceneDocument(editor.document);
      editor.inspector.updateLayoutUnit(StudioLayoutUnit.percent);
      editor.inspector.updateLayoutUnit(StudioLayoutUnit.pixels);
      expect(editor.inspector.hasDraft, isFalse);
      expect(editor.applyDraft(), isTrue);
      expect(encodeSceneDocument(editor.document), original);
      editor.inspector.getField('Depth').text = '1';
      editor.applyDraft();
      expect(editor.selectedNode.rect.x, 0.123456789);
      editor.updateScene(canvas: const SceneCanvas(referenceWidth: 1000));
      expect(editor.inspector.getField('Width').text, '500');
      editor.undo();
      expect(editor.inspector.getField('Width').text, '960');
      editor.inspector.getField('X').text = 'invalid';
      editor.inspector.updateLayoutUnit(StudioLayoutUnit.percent);
      expect(editor.inspector.layoutUnit, StudioLayoutUnit.pixels);
      expect(editor.inspector.getField('X').text, 'invalid');
      expect(editor.inspector.error, 'X must be a finite number.');
    },
  );

  test(
    'draft parsing rejects non-finite numbers, invalid integers and properties',
    () {
      for (final value in ['NaN', 'Infinity', 'not a number']) {
        editor.inspector.getField('X').text = value;
        expect(editor.applyDraft(), isFalse);
        expect(editor.inspector.error, 'X must be a finite number.');
      }
      editor.inspector.getField('X').text = '192';
      editor.inspector.getField('Depth').text = '1.5';
      expect(editor.applyDraft(), isFalse);
      expect(editor.inspector.error, 'Depth must be an integer.');
      editor.inspector.getField('Depth').text = '0';
      for (final value in ['[]', '{"variant":42}', '{"variant":""}']) {
        editor.inspector.getField('Properties').text = value;
        expect(editor.applyDraft(), isFalse);
        expect(editor.inspector.error, contains('non-empty strings'));
      }
      expect(editor.isDirty, isFalse);
      expect(editor.canUndo, isFalse);
    },
  );

  test('invalid geometry leaves the working scene and history intact', () {
    expect(
      () => editor.updateNode(
        editor.selectedNode.copyWith(
          rect: editor.selectedNode.rect.copyWith(width: 1),
        ),
      ),
      throwsFormatException,
    );
    expect(editor.selectedNode.rect.width, 0.5);
    expect(editor.canUndo, isFalse);
    expect(editor.isDirty, isFalse);
  });

  test(
    'duplicate preserves node configuration and restores selection in history',
    () {
      editor.updateNode(
        editor.selectedNode.copyWith(
          z: 4,
          renderOrder: 2,
          focusOrder: 3,
          motion: SceneMotionPreset.fade,
          interactive: true,
          visibleWhen: const ScenePredicateCondition(ScenePredicate.isDormant),
        ),
      );
      final original = editor.selectedNode;
      editor.duplicateSelectedNode();
      expect(editor.selectedId, 'panel-copy');
      expect(editor.document.nodes.map((node) => node.id), [
        'panel',
        'panel-copy',
      ]);
      expect(
        encodeSceneDocument(
          editor.document.copyWith(
            nodes: [editor.selectedNode.copyWith(id: original.id)],
          ),
        ),
        encodeSceneDocument(editor.document.copyWith(nodes: [original])),
      );
      editor.undo();
      expect(editor.document.nodes, hasLength(1));
      expect(editor.selectedId, 'panel');
      editor.redo();
      expect(editor.selectedId, 'panel-copy');
      editor.save();
      expect(decodeSceneDocument(file.readAsStringSync()).nodes, hasLength(2));
      expect(editor.isDirty, isFalse);
    },
  );

  test('duplicate allocates unique ids and new edits clear redo', () {
    editor.duplicateSelectedNode();
    editor.selectNode('panel');
    editor.duplicateSelectedNode();
    expect(editor.selectedId, 'panel-copy-2');
    editor.selectNode('panel');
    editor.duplicateSelectedNode();
    expect(editor.selectedId, 'panel-copy-3');
    editor.undo();
    expect(editor.selectedId, 'panel');
    editor.duplicateSelectedNode();
    expect(editor.selectedId, 'panel-copy-3');
    expect(editor.canRedo, isFalse);
  });

  test('delete selects a neighbor and undo restores the deleted node', () {
    editor.duplicateSelectedNode();
    editor.selectNode('panel');
    editor.duplicateSelectedNode();
    editor.deleteSelectedNode();
    expect(editor.selectedId, 'panel-copy');
    expect(editor.document.nodes.map((node) => node.id), [
      'panel',
      'panel-copy',
    ]);
    editor.undo();
    expect(editor.selectedId, 'panel-copy-2');
    expect(editor.document.nodes, hasLength(3));
    editor.redo();
    expect(editor.selectedId, 'panel-copy');
    editor.deleteSelectedNode();
    expect(editor.selectedId, 'panel');
    expect(editor.canDeleteNode, isFalse);
    expect(editor.isDirty, isFalse);
    editor.undo();
    expect(editor.selectedId, 'panel-copy');
    editor.selectNode('panel');
    editor.deleteSelectedNode();
    expect(editor.selectedId, 'panel-copy');
    editor.save();
    expect(
      decodeSceneDocument(file.readAsStringSync()).nodes.single.id,
      'panel-copy',
    );
  });

  test('the last node cannot be deleted and rejection adds no history', () {
    expect(editor.canDeleteNode, isFalse);
    expect(editor.deleteSelectedNode, throwsStateError);
    expect(editor.selectedNode.id, 'panel');
    expect(editor.canUndo, isFalse);
    expect(editor.isDirty, isFalse);
  });

  test('saving detects external edits and keeps unsaved work', () {
    editor.updateNode(editor.selectedNode.copyWith(z: 3));
    file.writeAsStringSync('external edit');
    expect(editor.save, throwsA(isA<FileSystemException>()));
    expect(file.readAsStringSync(), 'external edit');
    expect(editor.selectedNode.z, 3);
    expect(editor.isDirty, isTrue);
    expect(editor.reload, throwsFormatException);
    expect(editor.selectedNode.z, 3);
  });

  test('a new edit after undo clears redo, and no-op edits add no history', () {
    editor.updateNode(editor.selectedNode);
    expect(editor.canUndo, isFalse);
    editor.updateNode(editor.selectedNode.copyWith(z: 1));
    editor.undo();
    editor.updateNode(editor.selectedNode.copyWith(z: 2));
    expect(editor.canRedo, isFalse);
    editor.reload();
    expect(editor.selectedNode.z, 0);
    expect(editor.canUndo, isFalse);
    expect(editor.isDirty, isFalse);
  });
}
