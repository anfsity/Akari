import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'studio_canvas_presets.dart';
import 'studio_preferences.dart';
import 'studio_preview.dart';
import 'studio_preview_host.dart';

/// Each board has its own simulated input host. Only output size varies; the
/// authored reference canvas stays identical to production in every board.
class StudioComparison extends StatelessWidget {
  const StudioComparison({
    required this.theme,
    required this.document,
    required this.preferences,
    required this.dormant,
    required this.scenario,
    this.assetImageResolver,
    this.assetSvgLoader,
    this.assetFontLoader,
    super.key,
  });
  final ThemeDefinition theme;
  final SceneDocument document;
  final StudioPreferences preferences;
  final bool dormant;
  final StudioPreviewScenario scenario;
  final SceneImageProviderResolver? assetImageResolver;
  final SceneSvgLoader? assetSvgLoader;
  final SceneFontLoader? assetFontLoader;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => GridView.count(
      key: const ValueKey('comparison-boards'),
      crossAxisCount: constraints.maxWidth >= 620 ? 2 : 1,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        for (final preset in [
          StudioCanvasPreset.fullHd,
          StudioCanvasPreset.uhd,
          StudioCanvasPreset.ultrawide,
          StudioCanvasPreset.portrait,
        ])
          Container(
            key: ValueKey('comparison-${preset.name}'),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    '${preset.label} · ${preset.width} × ${preset.height}',
                  ).small(),
                ),
                Expanded(
                  child: StudioPreview(
                    key: ValueKey(preset),
                    theme: theme,
                    document: document,
                    viewportSize: Size(
                      preset.width.toDouble(),
                      preset.height.toDouble(),
                    ),
                    assetImageResolver: assetImageResolver,
                    assetSvgLoader: assetSvgLoader,
                    assetFontLoader: assetFontLoader,
                    selectedId: document.nodes.first.id,
                    selectedIds: const {},
                    dormant: dormant,
                    scenario: scenario,
                    readOnly: true,
                    preferences: preferences,
                    tool: StudioCanvasTool.move,
                    onSelect: (_) {},
                    onStartDrag: (_) => null,
                    onCommitDrag: (_) {},
                    onDragNodeChanged: (_) {},
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
