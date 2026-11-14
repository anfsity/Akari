import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';
import 'package:theme_studio/src/authoring/scene_editor.dart';
import 'package:theme_studio/src/resources/studio_assets.dart';
import 'package:theme_studio/src/resources/studio_shader_playground.dart';
import 'package:theme_studio/src/workspace/studio_preferences.dart';
import 'package:theme_studio/src/workspace/studio_settings.dart';

void main() {
  testWidgets(
    'StudioShaderPlayground loads existing background shader without initState setState crash',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final root = Directory.systemTemp.createTempSync('studio-playground-test-');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/pubspec.yaml').writeAsStringSync(
        'name: theme_test\nflutter:\n  shaders:\n    - assets/bg.frag\n',
      );
      final shaderFile = File('${root.path}/assets/bg.frag')
        ..createSync(recursive: true)
        ..writeAsStringSync(studioShaderExample);
      final sceneFile = File('${root.path}/lib/scene.json')
        ..createSync(recursive: true);
      const doc = SceneDocument(
        id: 'test',
        version: currentSceneVersion,
        canvas: SceneCanvas(referenceWidth: 1280, referenceHeight: 720),
        background: SceneBackground(
          kind: SceneBackgroundKind.custom,
          shader: SceneShader(asset: 'packages/theme_test/assets/bg.frag'),
        ),
        nodes: [
          SceneNode(
            id: 'panel',
            componentId: 'panel',
            rect: SceneRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3),
          ),
        ],
      );
      sceneFile.writeAsStringSync(encodeSceneDocument(doc));
      final editor = SceneEditor(sceneFile);
      addTearDown(editor.dispose);
      final assets = StudioAssets(directory: root, packageName: 'theme_test');

      await tester.pumpWidget(
        ShadcnApp(
          theme: ThemeData(colorScheme: ColorSchemes.darkZinc),
          home: Scaffold(
            child: StudioShaderPlayground(
              editor: editor,
              assets: assets,
              onAssetsChanged: () {},
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(shaderFile.readAsStringSync()), findsOneWidget);
      expect(
        () => editor.validateScene(
          background: const SceneBackground(
            kind: SceneBackgroundKind.custom,
            shader: SceneShader(asset: 'invalid/bg.frag'),
          ),
        ),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'StudioSettings displays custom shader status and preserves background shader on apply',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const shader = SceneShader(
        asset: 'packages/theme_test/assets/bg.frag',
        uniforms: [
          SceneShaderUniform(
            name: 'time',
            source: SceneUniformSource.time,
          ),
        ],
      );
      const doc = SceneDocument(
        id: 'test',
        version: currentSceneVersion,
        canvas: SceneCanvas(referenceWidth: 1280, referenceHeight: 720),
        background: SceneBackground(
          kind: SceneBackgroundKind.custom,
          shader: shader,
        ),
        nodes: [
          SceneNode(
            id: 'panel',
            componentId: 'panel',
            rect: SceneRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3),
          ),
        ],
      );
      SceneBackground? appliedBackground;

      await tester.pumpWidget(
        ShadcnApp(
          theme: ThemeData(colorScheme: ColorSchemes.darkZinc),
          home: Scaffold(
            child: StudioSettings(
              document: doc,
              preferences: const StudioPreferences(),
              assetPaths: const [],
              resolveAssetImage: AssetImage.new,
              supportsImageBackground: true,
              onApply: (_, background, _) => appliedBackground = background,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('settings-nav-background')));
      await tester.pumpAndSettle();
      expect(find.text('Custom shader: bg.frag'), findsOneWidget);
      expect(find.text('Shader: ${shader.asset}'), findsOneWidget);

      await tester.tap(find.text('Apply settings'));
      await tester.pumpAndSettle();

      expect(appliedBackground?.kind, SceneBackgroundKind.custom);
      expect(appliedBackground?.shader, shader);
    },
  );
}
