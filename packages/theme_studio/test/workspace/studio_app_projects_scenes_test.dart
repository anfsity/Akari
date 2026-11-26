import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';
import 'package:theme_studio/theme_studio.dart';
import 'package:theme_studio/src/preview/studio_preview.dart';
import 'package:theme_studio/src/inspector/node_inspector.dart';
import 'package:theme_studio/src/canvas/studio_canvas.dart';
import 'package:theme_studio/src/resources/studio_assets.dart';

import 'studio_app_test_harness.dart';

class _PresetComponents implements GreeterThemeComponents {
  @override
  Widget build(BuildContext context, SceneNode node) =>
      Center(child: Text('preset component ${node.id}'));
}

enum _ThemePalette { ocean, rose }

const _palette = ThemeChoiceProperty(
  name: 'palette',
  label: 'Palette',
  defaultValue: _ThemePalette.ocean,
  choices: {_ThemePalette.ocean: 'Ocean', _ThemePalette.rose: 'Rose'},
);
const _presets = ThemePresetCatalog(properties: [_palette]);

void main() {
  final harness = StudioAppTestHarness();
  setUp(harness.setUp);
  tearDown(harness.tearDown);

  Future<void> prepareSynthesisSource() async {
    final lib = Directory('${harness.directory.path}/lib')..createSync();
    File(
      '${harness.directory.path}/pubspec.yaml',
    ).writeAsStringSync('name: theme_source\nenvironment:\n  sdk: ^3.13.2\n');
    File('${lib.path}/theme.dart').writeAsStringSync(
      'ThemeDefinition buildSourceTheme({Color? seed, SceneDocument? document}) => throw UnimplementedError();\n',
    );
    harness.file = File('${lib.path}/template.scene.json')
      ..writeAsStringSync(encodeSceneDocument(studioTestDocument));
  }

  Future<void> finishCreation(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('create-theme-confirm')));
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump();
        final button = find.byKey(const ValueKey('create-theme-confirm'));
        if (button.evaluate().isEmpty ||
            tester.widget<PrimaryButton>(button).onPressed != null) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      fail('Theme creation did not settle.');
    });
    await tester.pumpAndSettle();
  }

  test(
    'theme creation collects asset layers from the scene owning package',
    () async {
      await prepareSynthesisSource();
      final destination = Directory.systemTemp.createTempSync(
        'studio-assets-theme-',
      );
      addTearDown(() => destination.deleteSync(recursive: true));
      final owner = harness.directory.createTempSync('owner-');
      final icon = File('${owner.path}/assets/logo.svg');
      icon.parent.createSync();
      icon.writeAsStringSync('<svg xmlns="http://www.w3.org/2000/svg"/>');
      final source = StudioThemeProject(
        packageName: 'theme_source',
        directory: harness.directory.path,
        scenePaths: [harness.file.path],
        themeBuilder: buildStudioTestTheme,
      );
      final project = await source.createTheme(
        packageName: 'theme_icons',
        destination: '${destination.path}/icons',
        document: studioTestDocument.copyWith(
          nodes: [
            studioTestDocument.nodes.first.copyWith(
              asset: const SceneAsset(
                path: 'packages/theme_owner/assets/logo.svg',
                kind: SceneAssetKind.svg,
                tint: 0xff123456,
              ),
            ),
          ],
        ),
        assets: StudioAssets(directory: owner, packageName: 'theme_owner'),
      );
      final saved = decodeSceneDocument(
        File(project.scenePaths.first).readAsStringSync(),
      );
      expect(
        saved.nodes.single.asset!.path,
        'packages/theme_icons/assets/composed/logo.svg',
      );
      expect(saved.nodes.single.asset!.tint, 0xff123456);
      expect(
        File('${project.directory}/assets/composed/logo.svg')
            .readAsStringSync(),
        icon.readAsStringSync(),
      );
    },
  );

  testWidgets(
    'creating a theme preserves the source and opens its saved composition',
    (tester) async {
      await prepareSynthesisSource();
      final destination = Directory.systemTemp.createTempSync(
        'studio-created-',
      );
      addTearDown(() => destination.deleteSync(recursive: true));
      final original = harness.file.readAsStringSync();
      ThemeDefinition buildSource({Color? seed, SceneDocument? document}) =>
          buildStudioTestTheme(
            seed:
                _palette.getValue(document?.themeProperties ?? {}) ==
                    _ThemePalette.rose
                ? material.Colors.red
                : material.Colors.blue,
            document: document,
            componentCatalog: studioEditableCatalog,
            presetCatalog: _presets,
            layout: studioAssemblyLayout,
          );
      await harness.openStudio(
        tester,
        themeBuilder: buildSource,
        packageName: 'theme_source',
      );
      final editor = tester
          .widget<StudioCanvas>(find.byType(StudioCanvas))
          .editor!;
      editor.updateLayoutPreset('right');
      editor.updateThemeProperty('palette', 'rose');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('property-text')),
        'My synthesized desktop',
      );
      await tester.tap(find.byKey(const ValueKey('studio-scene-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('create-theme')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('create-theme-name')),
        'neon',
      );
      await tester.enterText(
        find.byKey(const ValueKey('create-theme-location')),
        destination.path,
      );
      await finishCreation(tester);
      expect(find.byKey(const ValueKey('studio-create-theme')), findsNothing);
      expect(harness.file.readAsStringSync(), original);
      final newScene = File(
        '${destination.path}/neon/lib/composition.scene.json',
      );
      final saved = decodeSceneDocument(newScene.readAsStringSync());
      expect(saved.themeProperties, {'layout': 'right', 'palette': 'rose'});
      expect(saved.nodes.first.properties['text'], 'My synthesized desktop');
      expect(saved.nodes.first.rect.x, 0.5);
      final preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
      expect(preview.theme.id, 'neon');
      expect(encodeSceneDocument(preview.document), encodeSceneDocument(saved));
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('theme_neon'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('studio-theme-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('theme_source').last);
      await tester.pumpAndSettle();
      expect(
        encodeSceneDocument(
          tester.widget<StudioPreview>(find.byType(StudioPreview)).document,
        ),
        encodeSceneDocument(studioTestDocument),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'creation validates names, refuses existing folders and fits compact windows',
    (tester) async {
      await prepareSynthesisSource();
      final destination = Directory.systemTemp.createTempSync(
        'studio-existing-',
      );
      addTearDown(() => destination.deleteSync(recursive: true));
      final existing = Directory('${destination.path}/neon')..createSync();
      File('${existing.path}/marker').writeAsStringSync('untouched');
      await harness.openStudio(tester, packageName: 'theme_source');
      tester.view.physicalSize = const Size(600, 480);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('studio-scene-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('create-theme')));
      await tester.pumpAndSettle();
      final dialog = tester.getRect(
        find.byKey(const ValueKey('studio-create-theme')),
      );
      expect(dialog.top, greaterThanOrEqualTo(0));
      expect(dialog.bottom, lessThanOrEqualTo(480));
      await tester.enterText(
        find.byKey(const ValueKey('create-theme-name')),
        'Invalid Name',
      );
      await finishCreation(tester);
      expect(find.textContaining('lowercase underscore'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('create-theme-name')),
        'neon',
      );
      harness.picker.selectedDirectory = destination.path;
      await tester.ensureVisible(find.text('Choose folder'));
      await tester.tap(find.text('Choose folder'));
      await tester.pumpAndSettle();
      await finishCreation(tester);
      expect(find.text('Destination already exists.'), findsOneWidget);
      expect(File('${existing.path}/marker').readAsStringSync(), 'untouched');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('studio-create-theme')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'theme switching guards drafts and switches compiled components and asset ownership',
    (tester) async {
      final presetDirectory = Directory('${harness.directory.path}/preset')
        ..createSync();
      File('${presetDirectory.path}/pubspec.yaml')
          .writeAsStringSync('name: theme_preset\n');
      final presetFile = File('${presetDirectory.path}/preset.scene.json')
        ..writeAsStringSync(
          encodeSceneDocument(studioTestDocument.copyWith(id: 'preset')),
        );
      Directory('${presetDirectory.path}/assets').createSync();
      File('${presetDirectory.path}/assets/preset.txt')
          .writeAsStringSync('preset asset');
      final preset = StudioThemeProject(
        packageName: 'theme_preset',
        directory: presetDirectory.path,
        scenePaths: [presetFile.path],
        themeBuilder: ({Color? seed, SceneDocument? document}) =>
            ThemeDefinition(
              id: 'preset',
              document: studioTestDocument,
              bundle: buildStudioTestTheme().bundle,
              components: (_) => _PresetComponents(),
              componentCatalog: studioEditableCatalog,
              layout: ThemeLayoutDefinition(
                sceneId: 'preset',
                label: 'Preset composition',
                slots: [studioAssemblyLayout.slots.first],
              ),
            ),
      );
      await harness.openStudio(tester, additionalProjects: [preset]);
      Future<void> choosePreset() async {
        await tester.tap(find.byKey(const ValueKey('studio-theme-select')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('theme_preset').last);
        await tester.pumpAndSettle();
      }

      await tester.enterText(find.byKey(const ValueKey('field-Width')), '2560');
      await choosePreset();
      expect(find.textContaining('non-normalized rect'), findsOneWidget);
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).theme.id,
        'test',
      );
      await tester.enterText(find.byKey(const ValueKey('field-Width')), '512');
      await choosePreset();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).theme.id,
        'test',
      );
      await choosePreset();
      await tester.tap(find.text('Save and switch'));
      await tester.pumpAndSettle();
      expect(
        decodeSceneDocument(harness.file.readAsStringSync())
            .nodes
            .first
            .rect
            .width,
        0.4,
      );
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).theme.id,
        'preset',
      );
      expect(find.text('preset component panel'), findsOneWidget);
      expect(
        tester
            .widget<StudioCanvas>(find.byType(StudioCanvas))
            .editor!
            .layout!
            .label,
        'Preset composition',
      );
      expect(find.text('Panel appearance'), findsOneWidget);
      expect(find.byKey(const ValueKey('property-variant')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sidebar-assets')));
      await tester.pumpAndSettle();
      expect(find.text('preset.txt'), findsWidgets);
      await tester.enterText(find.byKey(const ValueKey('field-X')), '256');
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      expect(
        decodeSceneDocument(presetFile.readAsStringSync()).nodes.first.rect.x,
        0.2,
      );
      expect(
        decodeSceneDocument(harness.file.readAsStringSync()).nodes.first.rect.x,
        0.1,
      );
      await tester.enterText(find.byKey(const ValueKey('field-X')), '384');
      await tester.tap(find.byKey(const ValueKey('studio-theme-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('test').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard and switch'));
      await tester.pumpAndSettle();
      expect(
        decodeSceneDocument(presetFile.readAsStringSync()).nodes.first.rect.x,
        0.2,
      );
      expect(find.text('preset.txt'), findsNothing);
      expect(
        tester.widget<StudioCanvas>(find.byType(StudioCanvas)).editor!.layout,
        isNull,
      );
      expect(find.text('Panel appearance'), findsNothing);
      expect(find.byKey(const ValueKey('property-variant')), findsNothing);
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).theme.id,
        'test',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'loading a registered preset scene switches its component factory; broken presets retain the active scene',
    (tester) async {
      final presetDirectory = Directory('${harness.directory.path}/preset')
        ..createSync();
      File('${presetDirectory.path}/pubspec.yaml')
          .writeAsStringSync('name: theme_preset\n');
      final presetFile = File('${presetDirectory.path}/preset.scene.json')
        ..writeAsStringSync(
          encodeSceneDocument(studioTestDocument.copyWith(id: 'preset')),
        );
      final preset = StudioThemeProject(
        packageName: 'theme_preset',
        directory: presetDirectory.path,
        scenePaths: [presetFile.path],
        themeBuilder: ({Color? seed, SceneDocument? document}) =>
            buildStudioTestTheme().copyWith(id: 'preset'),
      );
      await harness.openStudio(tester, additionalProjects: [preset]);
      presetFile.writeAsStringSync('invalid');
      await tester.tap(find.byKey(const ValueKey('studio-theme-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('theme_preset').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).theme.id,
        'test',
      );
      expect(find.textContaining('Cannot open theme'), findsOneWidget);
      presetFile.writeAsStringSync(
        encodeSceneDocument(studioTestDocument.copyWith(id: 'preset')),
      );
      harness.picker.selected = StudioTestPickedFile(presetFile);
      await tester.tap(find.byKey(const ValueKey('studio-scene-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load JSON'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).theme.id,
        'preset',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'theme presets drive runtime styling, undo, save, reopen and inspection',
    (tester) async {
      ThemeDefinition buildPresets({Color? seed, SceneDocument? document}) {
        final palette = _palette.getValue(document?.themeProperties ?? {});
        return buildStudioTestTheme(
          seed: palette == _ThemePalette.ocean
              ? material.Colors.blue
              : material.Colors.red,
          document: document,
          presetCatalog: _presets,
        );
      }

      await harness.openStudio(tester, themeBuilder: buildPresets);
      final source = harness.file.readAsStringSync();
      final choice = find.byKey(const ValueKey('preset-palette'));
      await tester.ensureVisible(choice);
      await tester.pumpAndSettle();
      expect(choice, findsOneWidget);
      expect(find.text('Ocean'), findsOneWidget);
      expect(find.text('Optional components'), findsNothing);
      expect(find.text('Saved'), findsOneWidget);
      final original = tester
          .widget<StudioPreview>(find.byType(StudioPreview))
          .theme
          .materialTheme
          .colorScheme
          .primary;
      await tester.tap(choice);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rose').last);
      await tester.pumpAndSettle();
      var preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
      expect(preview.document.themeProperties, {'palette': 'rose'});
      expect(preview.theme.materialTheme.colorScheme.primary, isNot(original));
      expect(harness.file.readAsStringSync(), source);
      await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
      await tester.pumpAndSettle();
      expect(find.text('Ocean'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toolbar-redo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      expect(
        decodeSceneDocument(harness.file.readAsStringSync()).themeProperties,
        {'palette': 'rose'},
      );
      await tester.pumpWidget(const SizedBox());
      await harness.openStudio(tester, themeBuilder: buildPresets);
      expect(find.text('Rose'), findsOneWidget);
      preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
      expect(preview.theme.materialTheme.colorScheme.primary, isNot(original));
      await tester.tap(find.text('Inspect code'));
      await tester.pumpAndSettle();
      final selector = find.descendant(
        of: choice,
        matching: find.byType(Select<Enum>),
      );
      expect(tester.widget<Select<Enum>>(selector).enabled, isFalse);
      await tester.ensureVisible(choice);
      await tester.pumpAndSettle();
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(find.text('Ocean'), findsNothing);
      expect(preview.document.themeProperties, {'palette': 'rose'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'theme builders resolve the authored document on open and reload',
    (tester) async {
      final authored = studioTestDocument.copyWith(
        themeProperties: {'palette': 'nord'},
      );
      harness.file.writeAsStringSync(encodeSceneDocument(authored));
      SceneDocument? received;
      await harness.openStudio(
        tester,
        themeBuilder: ({Color? seed, SceneDocument? document}) {
          received = document;
          return buildStudioTestTheme(seed: seed, document: document);
        },
      );
      expect(received!.themeProperties, {'palette': 'nord'});
      expect(
        tester
            .widget<StudioPreview>(find.byType(StudioPreview))
            .theme
            .document
            .themeProperties,
        {'palette': 'nord'},
      );
      await tester.enterText(find.byKey(const ValueKey('field-X')), '256');
      await tester.pump();
      await tester.tap(find.text('Apply to preview'));
      await tester.pumpAndSettle();
      final reload = tester.binding.reassembleApplication();
      await tester.pumpAndSettle();
      await reload;
      expect(received!.nodes.first.rect.x, 0.2);
      expect(received!.themeProperties, {'palette': 'nord'});
      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('preview dependencies survive edits and refresh on hot reload', (
    tester,
  ) async {
    var componentCreations = 0;
    await harness.openStudio(
      tester,
      themeBuilder: ({Color? seed, SceneDocument? document}) {
        final theme = buildStudioTestTheme(seed: seed, document: document);
        return ThemeDefinition(
          id: theme.id,
          document: theme.document,
          bundle: theme.bundle,
          components: (_) {
            componentCreations++;
            return StudioTestComponents();
          },
        );
      },
    );
    final theme = tester
        .widget<StudioPreview>(find.byType(StudioPreview))
        .theme;
    await tester.enterText(find.byKey(const ValueKey('field-X')), '256');
    await tester.pump();
    await tester.tap(find.text('Apply to preview'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toolbar-undo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toolbar-redo')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('State: Login'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('preview-panel')),
      const Offset(20, 10),
    );
    await tester.pumpAndSettle();
    final preview = tester.widget<StudioPreview>(find.byType(StudioPreview));
    expect(preview.theme, same(theme));
    expect(componentCreations, 1);

    final reload = tester.binding.reassembleApplication();
    await tester.pumpAndSettle();
    await reload;
    final refreshed = tester.widget<StudioPreview>(find.byType(StudioPreview));
    expect(refreshed.theme, isNot(same(theme)));
    expect(refreshed.document, same(preview.document));
    expect(componentCreations, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed initial load disables editor actions and reload recovers',
    (tester) async {
      harness.file.writeAsStringSync('invalid scene');
      await harness.openStudio(tester);
      expect(find.byType(StudioPreview), findsNothing);
      expect(find.byType(NodeInspector), findsNothing);
      for (final key in ['toolbar-settings', 'toolbar-undo', 'toolbar-redo']) {
        expect(
          tester.widget<OutlineButton>(find.byKey(ValueKey(key))).onPressed,
          isNull,
        );
      }
      expect(
        tester
            .widget<PrimaryButton>(
              find.widgetWithText(PrimaryButton, 'Save scene'),
            )
            .onPressed,
        isNull,
      );
      harness.file.writeAsStringSync(encodeSceneDocument(studioTestDocument));
      await tester.tap(find.byKey(const ValueKey('studio-scene-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reload from disk'));
      await tester.pumpAndSettle();
      expect(find.byType(StudioPreview), findsOneWidget);
      expect(find.byType(NodeInspector), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'load JSON handles cancellation, invalid files and unsaved edits',
    (tester) async {
      await harness.openStudio(tester);
      Future<void> tapLoadJson() async {
        await tester.tap(find.byKey(const ValueKey('studio-scene-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Load JSON'));
        await tester.pumpAndSettle();
      }

      await tapLoadJson();
      expect(find.text('Saved'), findsOneWidget);
      final imported = File('${harness.directory.path}/imported.json')
        ..writeAsStringSync('invalid');
      harness.picker.selected = StudioTestPickedFile(imported);
      await tapLoadJson();
      expect(find.textContaining('FormatException'), findsOneWidget);
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).document.id,
        'test',
      );
      imported.writeAsStringSync(
        encodeSceneDocument(studioTestDocument.copyWith(id: 'imported')),
      );
      await tester.enterText(find.byKey(const ValueKey('field-X')), '256');
      await tapLoadJson();
      expect(find.text('Unsaved scene changes'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      await tapLoadJson();
      expect(
        tester.widget<StudioPreview>(find.byType(StudioPreview)).document.id,
        'imported',
      );
      expect(
        find.text('test / imported.json', findRichText: true),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const ValueKey('field-X')), '384');
      await tester.tap(find.text('Save scene'));
      await tester.pumpAndSettle();
      expect(
        decodeSceneDocument(imported.readAsStringSync()).nodes.first.rect.x,
        0.3,
      );
      expect(
        decodeSceneDocument(harness.file.readAsStringSync()).nodes.first.rect.x,
        0.2,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reload requires explicit discard and retains node selection', (
    tester,
  ) async {
    await harness.openStudio(tester);
    await tester.tap(find.byKey(const ValueKey('layer-label')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('field-X')), '256');
    await tester.tap(find.byKey(const ValueKey('studio-scene-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reload from disk'));
    await tester.pumpAndSettle();
    expect(find.text('Discard edits and reload?'), findsOneWidget);
    await tester.tap(find.text('Discard and reload'));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);
    expect(
      tester.widget<StudioPreview>(find.byType(StudioPreview)).selectedId,
      'label',
    );
    expect(tester.takeException(), isNull);
  });
}
