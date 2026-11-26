import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';
import 'package:theme_studio/src/preview/studio_preview.dart';
import 'package:theme_studio/src/canvas/studio_canvas.dart';
import 'package:theme_studio/src/authoring/studio_components.dart';

import 'studio_app_test_harness.dart';

class _ThemedBackground extends BackgroundRenderer {
  const _ThemedBackground({this.resolveImage});
  final SceneImageProviderResolver? resolveImage;

  @override
  _ThemedBackground getWithImageResolver(
    SceneImageProviderResolver resolveImage,
  ) => _ThemedBackground(resolveImage: resolveImage);

  @override
  Widget build(BuildContext context, SceneBackground background) =>
      const ColoredBox(color: Color(0xff123456));
}

Future<void> _writeImage(File file) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xff123456), BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(2, 2);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
}

void main() {
  final harness = StudioAppTestHarness();
  setUp(harness.setUp);
  tearDown(harness.tearDown);

  testWidgets(
    'Studio binds file images without replacing the theme background renderer',
    (tester) async {
      await harness.openStudio(
        tester,
        themeBuilder: ({Color? seed, SceneDocument? document}) {
          final theme = buildStudioTestTheme(seed: seed, document: document);
          return theme.copyWith(
            bundle: theme.bundle.copyWith(
              backgrounds: const {
                SceneBackgroundKind.image: _ThemedBackground(),
              },
            ),
          );
        },
      );
      final preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
      final renderer =
          preview.theme.bundle.backgrounds[SceneBackgroundKind.image]
              as _ThemedBackground;
      expect(
        (renderer.resolveImage!('assets/test.png') as FileImage).file.path,
        '${harness.directory.path}/assets/test.png',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'themes without image backgrounds do not offer a misleading wallpaper action',
    (tester) async {
      final image = File('${harness.directory.path}/assets/wallpaper.png');
      image.parent.createSync();
      await tester.runAsync(() => _writeImage(image));
      await harness.openStudio(
        tester,
        themeBuilder: ({Color? seed, SceneDocument? document}) {
          final theme = buildStudioTestTheme(seed: seed, document: document);
          return theme.copyWith(
            bundle: theme.bundle.copyWith(backgrounds: const {}),
          );
        },
      );
      await tester.tap(find.byKey(const ValueKey('sidebar-assets')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PrimaryButton>(
              find.widgetWithText(PrimaryButton, 'Use image'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('toolbar-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-nav-background')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Background: solid'));
      await tester.pumpAndSettle();
      expect(find.text('image'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'imported SVG layers preview tint, undo, save and reopen without restarting',
    (tester) async {
      final source = File('${harness.directory.path}/badge.svg')
        ..writeAsStringSync(
          '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><rect width="32" height="32"/></svg>',
        );
      await harness.openStudio(tester);
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      harness.picker.selected = StudioTestPickedFile(source);
      await tester.tap(find.byKey(const ValueKey('sidebar-assets')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Import asset'));
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsWidgets);
      expect(editor.canUndo, isFalse);
      final toggle = find.ancestor(
        of: find.text('Override icon color'),
        matching: find.byType(Row),
      );
      await tester.tap(
        find.descendant(of: toggle, matching: find.byType(Switch)),
      );
      await tester.pumpAndSettle();
      tester
          .widget<ColorInput>(find.byKey(const ValueKey('asset-tint')))
          .onChanged!(ColorDerivative.fromColor(const Color(0xff123456)));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('place-asset')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(editor.document.nodes.length, 3);
      expect(editor.selectedNode.asset!.path, 'packages/test/assets/badge.svg');
      expect(editor.selectedNode.asset!.tint, 0xff123456);
      final iconId = editor.selectedId;
      expect(find.byKey(ValueKey('preview-$iconId')), findsOneWidget);
      final previewIcon = find.descendant(
        of: find.byKey(ValueKey('preview-$iconId')),
        matching: find.byType(SvgPicture),
      );
      expect(
        tester.widget<SvgPicture>(previewIcon).colorFilter,
        const ColorFilter.mode(Color(0xff123456), BlendMode.srcIn),
      );
      editor.undo();
      await tester.pumpAndSettle();
      expect(editor.document.nodes.length, 2);
      expect(editor.canUndo, isFalse);
      editor.redo();
      await tester.pumpAndSettle();
      tester
          .widget<ColorInput>(find.byKey(const ValueKey('node-asset-tint')))
          .onChanged!(ColorDerivative.fromColor(const Color(0xffabcdef)));
      await tester.pumpAndSettle();
      expect(editor.selectedNode.asset!.tint, 0xffabcdef);
      editor.undo();
      await tester.pumpAndSettle();
      expect(editor.selectedNode.asset!.tint, 0xff123456);
      editor.redo();
      expect(editor.save(), isTrue);
      final saved = decodeSceneDocument(harness.file.readAsStringSync());
      expect(saved.nodes.last.asset!.tint, 0xffabcdef);
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.openStudio(tester);
      final reopened = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      expect(reopened.document.nodes.last.asset!.tint, 0xffabcdef);
      expect(reopened.isDirty, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid SVG assets and inspector drafts cannot replace the scene',
    (tester) async {
      final source = File('${harness.directory.path}/broken.svg')
        ..writeAsStringSync('not SVG content');
      await harness.openStudio(tester);
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      harness.picker.selected = StudioTestPickedFile(source);
      await tester.tap(find.byKey(const ValueKey('sidebar-assets')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Import asset'));
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      editor.inspector.getField('Width').text = '-1';
      await tester.tap(find.byKey(const ValueKey('place-asset')));
      await tester.pumpAndSettle();
      expect(editor.inspector.error, isNotNull);
      expect(editor.document.nodes.length, 2);
      editor.inspector.resetNode(editor.selectedNode);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('place-asset')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('Cannot place asset:'), findsOneWidget);
      expect(editor.canUndo, isFalse);
      expect(editor.isDirty, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'font previews expand and apply the selected face as an undoable scene style',
    (tester) async {
      final font = File('${harness.directory.path}/assets/Preview.otf');
      font.parent.createSync();
      File('../../themes/default/assets/fonts/SpaceGrotesk-Regular.otf')
          .copySync(font.path);
      await harness.openStudio(tester);
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      editor.createComponent(StudioComponent.text);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('sidebar-assets')));
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      final sample = tester.widget<Text>(
        find.byKey(const ValueKey('font-preview-sample')),
      );
      expect(sample.maxLines, 1);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('expand-font-preview')));
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<Text>(find.byKey(const ValueKey('font-preview-sample')))
            .any((sample) => sample.maxLines == 3),
        isTrue,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('apply-asset-font')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      final token = editor.selectedNode.styleToken!;
      expect(
        editor.document.styleTokens[token]!.fontAsset,
        'packages/test/assets/Preview.otf',
      );
      editor.undo();
      expect(editor.document.styleTokens[token]!.fontAsset, isNull);
      editor.redo();
      expect(editor.save(), isTrue);
      expect(
        decodeSceneDocument(harness.file.readAsStringSync())
            .styleTokens[token]!
            .fontAsset,
        'packages/test/assets/Preview.otf',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'asset search and categories filter resources without changing scene history',
    (tester) async {
      final font = File('${harness.directory.path}/assets/fonts/Preview.otf');
      font.parent.createSync(recursive: true);
      File('../../themes/default/assets/fonts/SpaceGrotesk-Regular.otf')
          .copySync(font.path);
      File('${harness.directory.path}/assets/rain.frag')
          .writeAsStringSync('void main() {}');
      await harness.openStudio(tester);
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('sidebar-assets')));
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('font-preview-sample')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('font-preview-text')),
        'My font sample',
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('font-preview-sample')))
            .data,
        'My font sample',
      );
      await tester.enterText(
        find.byKey(const ValueKey('asset-search')),
        'RAIN',
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('asset-packages/test/assets/rain.frag')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('asset-packages/test/assets/fonts/Preview.otf'),
        ),
        findsNothing,
      );
      await tester.enterText(find.byKey(const ValueKey('asset-search')), '');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('asset-category')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Shaders'),
        60,
        scrollable: find
            .descendant(
              of: find.byType(SelectPopup<String>),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shaders').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          const ValueKey('asset-packages/test/assets/fonts/Preview.otf'),
        ),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const ValueKey('asset-search')),
        'nothing',
      );
      await tester.pumpAndSettle();
      expect(find.text('No matching assets.'), findsOneWidget);
      expect(editor.canUndo, isFalse);
      expect(editor.isDirty, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('imported image previews immediately and background edits undo', (
    tester,
  ) async {
    final source = File('${harness.directory.path}/wallpaper.png');
    await tester.runAsync(() => _writeImage(source));
    await harness.openStudio(tester);
    harness.picker.selected = StudioTestPickedFile(source);
    await tester.tap(find.byKey(const ValueKey('sidebar-assets')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import asset'));
    await tester.pumpAndSettle();
    final initialTheme = tester
        .widget<StudioPreview>(find.byType(StudioPreview))
        .theme;
    expect(
      File('${harness.directory.path}/assets/wallpaper.png').existsSync(),
      isTrue,
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Use image'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    final preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
    expect(
      preview.document.background.asset,
      'packages/test/assets/wallpaper.png',
    );
    expect(preview.document.background.kind, SceneBackgroundKind.image);
    expect(
      preview.theme.materialTheme.colorScheme.primary,
      isNot(initialTheme.materialTheme.colorScheme.primary),
    );
    await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
    await tester.pumpAndSettle();
    final undonePreview = tester.widget<StudioPreview>(
      find.byType(StudioPreview),
    );
    expect(undonePreview.document.background.kind, SceneBackgroundKind.solid);
    expect(
      undonePreview.theme.materialTheme.colorScheme.primary,
      initialTheme.materialTheme.colorScheme.primary,
    );
    expect(
      File('${harness.directory.path}/assets/wallpaper.png').existsSync(),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'loaded theme owns imported assets, saved paths and background previews',
    (tester) async {
      final source = File('${harness.directory.path}/assets/wallpaper.png');
      source.parent.createSync();
      await tester.runAsync(() => _writeImage(source));
      final originalManifest = File('${harness.directory.path}/pubspec.yaml')
          .readAsStringSync();
      final other = Directory('${harness.directory.path}/other-project')
        ..createSync();
      final manifest = File('${other.path}/pubspec.yaml')
        ..writeAsStringSync('name: theme_other\n');
      final localImage = File('${other.path}/assets/local.png');
      localImage.parent.createSync();
      source.copySync(localImage.path);
      const localAsset = 'packages/theme_other/assets/local.png';
      final scene = File('${other.path}/lib/scenes/other.scene.json');
      scene.parent.createSync(recursive: true);
      scene.writeAsStringSync(
        encodeSceneDocument(
          studioTestDocument.copyWith(
            id: 'other',
            background: const SceneBackground(
              kind: SceneBackgroundKind.image,
              asset: localAsset,
            ),
          ),
        ),
      );
      await harness.openStudio(tester);
      final invalid = File('${scene.parent.path}/invalid.json')
        ..writeAsStringSync('invalid');
      harness.picker.selected = StudioTestPickedFile(invalid);
      await tester.tap(find.byKey(const ValueKey('studio-scene-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load JSON'));
      await tester.pumpAndSettle();
      expect(find.textContaining('FormatException'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sidebar-assets')));
      await tester.pumpAndSettle();
      expect(find.text('wallpaper.png'), findsWidgets);
      expect(find.text('local.png'), findsNothing);
      harness.picker.selected = StudioTestPickedFile(scene);
      await tester.tap(find.byKey(const ValueKey('studio-scene-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load JSON'));
      await tester.pumpAndSettle();
      expect(find.text('local.png'), findsWidgets);
      expect(find.text('wallpaper.png'), findsNothing);
      var preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
      var renderer =
          preview.theme.bundle.backgrounds[SceneBackgroundKind.image]
              as ImageBackgroundRenderer;
      expect(
        (renderer.resolveImage(localAsset) as FileImage).file.path,
        localImage.path,
      );

      harness.picker.selected = StudioTestPickedFile(source);
      await tester.tap(find.byKey(const ValueKey('sidebar-assets')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import asset'));
      await tester.pumpAndSettle();
      expect(
        File('${other.path}/assets/wallpaper.png').readAsBytesSync(),
        source.readAsBytesSync(),
      );
      expect(manifest.readAsStringSync(), contains('assets/wallpaper.png'));
      expect(
        File('${harness.directory.path}/pubspec.yaml').readAsStringSync(),
        originalManifest,
      );
      expect(
        File('${harness.directory.path}/assets/wallpaper-2.png').existsSync(),
        isFalse,
      );
      await tester.ensureVisible(find.text('Use image').last);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Use image').last);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      const importedAsset = 'packages/theme_other/assets/wallpaper.png';
      expect(
        decodeSceneDocument(scene.readAsStringSync()).background.asset,
        importedAsset,
      );
      preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
      renderer =
          preview.theme.bundle.backgrounds[SceneBackgroundKind.image]
              as ImageBackgroundRenderer;
      expect(
        (renderer.resolveImage(importedAsset) as FileImage).file.path,
        '${other.path}/assets/wallpaper.png',
      );
      expect(
        decodeSceneDocument(harness.file.readAsStringSync()).background.kind,
        SceneBackgroundKind.solid,
      );

      await tester.tap(find.byKey(const ValueKey('studio-scene-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('test.scene.json').last);
      await tester.pumpAndSettle();
      expect(find.text('local.png'), findsNothing);
      expect(find.text('wallpaper.png'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('sidebar-assets')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import asset'));
      await tester.pumpAndSettle();
      expect(
        File('${harness.directory.path}/assets/wallpaper-2.png').existsSync(),
        isTrue,
      );
      expect(
        File('${other.path}/assets/wallpaper-2.png').existsSync(),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
