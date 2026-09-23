import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mozais_greeter_ui/mozais_greeter_ui.dart';
import 'package:mozais_scene/mozais_scene.dart';
import 'package:mozais_scene_editor/src/editor_controller.dart';
import 'package:mozais_scene_editor/src/editor_settings.dart';
import 'package:mozais_scene_editor/src/editor_settings_controller.dart';
import 'package:mozais_scene_editor/src/editor_settings_scope.dart';
import 'package:mozais_scene_editor/src/editor_settings_store.dart';
import 'package:mozais_scene_editor/src/editor_strings.dart';
import 'package:mozais_scene_editor/src/english_strings.dart';
import 'package:mozais_scene_editor/src/inspector_panel.dart';
import 'package:mozais_scene_editor/src/node_list_panel.dart';
import 'package:mozais_scene_editor/src/scene_preview.dart';

const _asset = 'assets/(139810879)年越し三人娘 『OIOI × 東方Project』.jpg';

String _sceneJson(int nodes, double blurSigma) {
  final buffer = StringBuffer('''
{
  "id": "perf",
  "version": 1,
  "canvas": {"fit": "cover", "useSafeArea": false},
  "background": {"kind": "image", "asset": "$_asset", "color": "#000000", "scrimOpacity": 0.5, "blurSigma": $blurSigma},
  "nodes": [
''');
  for (var i = 0; i < nodes; i++) {
    buffer.write('''
    {
      "id": "node$i",
      "kind": "glassPanel",
      "rect": {"x": ${(i % 5) * 0.18}, "y": ${(i ~/ 5) * 0.18}, "width": 0.16, "height": 0.16}
    }${i == nodes - 1 ? '' : ','}
''');
  }
  buffer.write('  ]\n}\n');
  return buffer.toString();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final mode in PreviewMode.values) {
    testWidgets('${mode.name} full editor frame timings', (tester) async {
      final directory = Directory.systemTemp.createTempSync('mozais_editor_perf');
      final file = File('${directory.path}/perf.scene.json')
        ..writeAsStringSync(_sceneJson(24, 48));
      final controller = SceneEditorController(Directory('${directory.path}/assets'))
        ..setPath(file.path);
      await controller.open();
      final settings = EditorSettingsController(
        EditorSettingsStore(File('${directory.path}/settings.json')),
        initial: EditorSettings.defaults,
      );
      final feature = GreeterFeature(gateway: DemoGreeterGateway());

      await tester.pumpWidget(
        EditorStringsScope(
          strings: const EnglishStrings(),
          child: EditorSettingsScope(
            controller: settings,
            child: MaterialApp(
              home: Scaffold(
                body: Row(
                  children: [
                    SizedBox(
                      width: 240,
                      child: ListenableBuilder(
                        listenable: Listenable.merge([
                          controller.nodesListenable,
                          controller.selectionListenable,
                        ]),
                        builder: (context, _) =>
                            NodeListPanel(controller: controller),
                      ),
                    ),
                    Expanded(
                      child: ListenableBuilder(
                        listenable: Listenable.merge([
                          controller.documentListenable,
                          controller.selectionListenable,
                          controller.predicatesListenable,
                        ]),
                        builder: (context, _) => ScenePreview(
                          controller: controller,
                          feature: feature,
                          mode: mode,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 300,
                      child: InspectorPanel(controller: controller),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      Future<Map<String, Object?>> measure(
        String label,
        Future<void> Function(int index) step,
        int iterations,
      ) async {
        final timings = <FrameTiming>[];
        void onTimings(List<FrameTiming> batch) => timings.addAll(batch);
        SchedulerBinding.instance.addTimingsCallback(onTimings);
        for (var i = 0; i < iterations; i++) {
          await step(i);
          await tester.pump(const Duration(milliseconds: 16));
          await Future<void>.delayed(const Duration(milliseconds: 24));
        }
        SchedulerBinding.instance.removeTimingsCallback(onTimings);
        final measured = timings.length > 5 ? timings.sublist(5) : timings;
        final report = <String, Object?>{
          'mode': mode.name,
          'case': label,
          'p50_build_ms': _percentile(
            measured.map((t) => t.buildDuration.inMicroseconds / 1000),
            0.50,
          ),
          'p95_build_ms': _percentile(
            measured.map((t) => t.buildDuration.inMicroseconds / 1000),
            0.95,
          ),
          'p50_raster_ms': _percentile(
            measured.map((t) => t.rasterDuration.inMicroseconds / 1000),
            0.50,
          ),
          'p95_raster_ms': _percentile(
            measured.map((t) => t.rasterDuration.inMicroseconds / 1000),
            0.95,
          ),
          'sample_count': measured.length,
        };
        // ignore: avoid_print
        print('EDITOR_PERF ${jsonEncode(report)}');
        binding.reportData = report;
        return report;
      }

      final ids = controller.document!.nodes.map((node) => node.id).toList();

      await measure('document-edit', (i) async {
        controller.updateDocument(
          (document) => document.copyWith(
            background: document.background.copyWith(
              blurSigma: 20 + (i % 30).toDouble(),
            ),
          ),
        );
      }, 60);

      await measure('selection', (i) async {
        controller.select(ids[i % ids.length]);
      }, 120);

      await measure('node-edit', (i) async {
        controller.updateSelected(
          (node) => node.copyWith(z: i),
        );
      }, 60);

      await measure('predicate', (i) async {
        controller.togglePredicate(ScenePredicate.isDormant);
      }, 60);

      feature.dispose();
      settings.dispose();
      directory.deleteSync(recursive: true);
    });
  }
}

double _percentile(Iterable<double> values, double percentile) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) {
    return 0;
  }
  final index = ((sorted.length - 1) * percentile).round();
  return sorted[index];
}
