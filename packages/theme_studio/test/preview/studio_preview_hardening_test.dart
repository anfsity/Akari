import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';
import 'package:theme_studio/src/authoring/scene_editor.dart';
import 'package:theme_studio/src/preview/studio_preview.dart';
import 'package:theme_studio/src/workspace/studio_preferences.dart';
import 'package:theme_studio/src/workspace/studio_sidebar.dart';

class _TestComponents implements GreeterThemeComponents {
  @override
  Widget build(BuildContext context, SceneNode node) => node.componentId == 'frame'
      ? const SizedBox.expand()
      : Text(node.properties['text'] ?? '');
}

ThemeDefinition _buildTestTheme(SceneDocument document) => ThemeDefinition(
  id: 'test',
  bundle: ThemeBundle(
    tokens: ThemeTokens(
      materialTheme: material.ThemeData(
        colorScheme: const material.ColorScheme.dark(),
      ),
      panelRadius: 8,
      mediumMotion: Duration.zero,
      disableAnimations: true,
      standardCurve: Curves.linear,
      minHitTarget: 44,
      surfaceColor: const Color(0xff222222),
      surfaceVariantColor: const Color(0xff333333),
    ),
    backgrounds: const {
      SceneBackgroundKind.solid: SolidBackgroundRenderer(),
    },
  ),
  document: document,
  componentCatalog: const ThemeComponentCatalog(
    components: {
      'frame': ThemeComponentDefinition(label: 'Frame'),
      'label': ThemeComponentDefinition(
        label: 'Label',
        properties: [
          ThemeTextProperty(
            name: 'text',
            label: 'Text',
            defaultValue: 'Hello',
          ),
        ],
      ),
    },
  ),
  components: (_) => _TestComponents(),
);

void main() {
  late Directory directory;
  late File file;
  late SceneEditor editor;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('studio-preview-hardening-');
    file = File('${directory.path}/test.scene.json');
    const doc = SceneDocument(
      id: 'test',
      version: currentSceneVersion,
      canvas: SceneCanvas(referenceWidth: 800, referenceHeight: 600),
      background: SceneBackground(kind: SceneBackgroundKind.solid),
      nodes: [
        SceneNode(
          id: 'frame',
          componentId: 'frame',
          layout: SceneLayout(),
          rect: SceneRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
        ),
        SceneNode(
          id: 'caption',
          componentId: 'label',
          parentId: 'frame',
          rect: SceneRect(x: 0.1, y: 0.1, width: 0.4, height: 0.1),
          properties: {'text': 'Hello'},
        ),
      ],
    );
    file.writeAsStringSync(encodeSceneDocument(doc));
    editor = SceneEditor(file);
  });

  tearDown(() {
    editor.dispose();
    directory.deleteSync(recursive: true);
  });

  Widget buildPreviewHost({
    List<SceneNode>? nodesOverride,
    bool readOnly = false,
    ValueChanged<List<SceneNode>>? onCommitNodes,
    ValueChanged<SceneNode>? onDragNodeChanged,
  }) => ShadcnApp(
    home: Scaffold(
      child: Center(
        child: SizedBox(
          width: 800,
          height: 600,
          child: ListenableBuilder(
            listenable: editor,
            builder: (context, _) {
              final doc = nodesOverride == null
                  ? editor.previewDocument
                  : editor.document.copyWith(nodes: nodesOverride);
              return StudioPreview(
                theme: _buildTestTheme(doc),
                document: doc,
                selectedId: editor.selectedId,
                selectedIds: editor.selectedIds,
                dormant: false,
                readOnly: readOnly,
                preferences: const StudioPreferences(),
                tool: StudioCanvasTool.move,
                onSelect: editor.selectNode,
                onSelectNodes: editor.selectNodes,
                onStartDrag: (id) {
                  editor.selectNode(id);
                  return editor.document.nodes.firstWhere(
                    (node) => node.id == id,
                  );
                },
                onCommitNodes: onCommitNodes ?? editor.updateNodes,
                onDragNodeChanged: onDragNodeChanged ?? (_) {},
                onUpdateText: editor.updateNodeText,
              );
            },
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'inline text editor retains invalid text and clears cleanly if node is deleted',
    (tester) async {
      await tester.pumpWidget(buildPreviewHost());
      await tester.pumpAndSettle();

      final captionFinder = find.byKey(const ValueKey('preview-caption'));
      await tester.tap(captionFinder);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(captionFinder);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('canvas-text-editor')), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('canvas-text-editor')),
        '',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('canvas-text-editor')), findsOneWidget);
      expect(editor.inspector.error, isNotNull);

      editor.selectNode('caption');
      editor.deleteSelectedNode();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('canvas-text-editor')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelling a frame drag does not commit changes', (tester) async {
    var commits = 0;
    await tester.pumpWidget(
      buildPreviewHost(onCommitNodes: (_) => commits++),
    );
    await tester.pumpAndSettle();

    final frameFinder = find.byKey(const ValueKey('preview-frame'));
    final start = tester.getTopLeft(frameFinder) + const Offset(10, 10);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(40, 30));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(commits, 0);
  });

  testWidgets('layer tree shows rule badge for transition-only nodes', (
    tester,
  ) async {
    final original = editor.document.nodes.last;
    editor.updateNode(
      original.copyWith(
        transitions: const [
          SceneStateTransition(
            from: ScenePredicateCondition(ScenePredicate.isDormant),
            to: ScenePredicateCondition(ScenePredicate.isAuthError),
            effect: SceneStateEffect.shake,
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      ShadcnApp(
        home: Scaffold(
          child: SizedBox(
            width: 280,
            height: 600,
            child: StudioSidebar(
              scenePaths: [file.path],
              assetPaths: const [],
              resolveAssetImage: (path) => FileImage(File(path)),
              loadAssetText: (path) async => '',
              loadFontPreview: (path) async => 'Roboto',
              onPlaceAsset: null,
              onApplyFont: null,
              editor: editor,
              loadingFile: false,
              onLoadJson: () {},
              onSwitchScene: (_) {},
              onImportAsset: () {},
              onApplyBackground: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('sidebar-layers')));
    await tester.pumpAndSettle();
    expect(find.byIcon(LucideIcons.gitBranch), findsOneWidget);
  });
}
