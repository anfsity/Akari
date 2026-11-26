import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../authoring/scene_editor.dart';
import '../authoring/studio_theme_project.dart';
import '../inspector/code_inspector.dart';
import '../inspector/node_inspector.dart';
import '../inspector/studio_effects_inspector.dart';
import '../resources/studio_assets.dart';
import 'studio_sidebar.dart';
import 'studio_theme_selector.dart';

class StudioAppThemeOverrides extends StatelessWidget {
  const StudioAppThemeOverrides({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ComponentTheme<OutlineButtonTheme>(
      data: OutlineButtonTheme(
        decoration: (context, states, decoration) =>
            (decoration as BoxDecoration).copyWith(
              color:
                  states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.pressed)
                  ? colors.accent
                  : colors.background,
            ),
      ),
      child: ComponentTheme<SliderTheme>(
        data: SliderTheme(
          trackHeight: 4,
          trackColor: colors.muted,
          thumbColor: colors.background,
          thumbBorderColor: colors.primary.withValues(alpha: .5),
          thumbFocusedBorderColor: colors.primary,
          thumbSize: 16,
        ),
        child: ComponentTheme<ScrollbarTheme>(
          data: ScrollbarTheme(
            thickness: 4 * theme.scaling,
            color: colors.mutedForeground.withValues(alpha: .35),
            radius: const Radius.circular(8),
          ),
          child: child,
        ),
      ),
    );
  }
}

class StudioProjectSidebar extends StatelessWidget {
  const StudioProjectSidebar({
    required this.projects,
    required this.selectedProject,
    required this.onSwitchTheme,
    required this.assetPaths,
    required this.assets,
    required this.editor,
    required this.loadingFile,
    required this.readOnly,
    required this.supportsImageBackground,
    required this.onPlaceAsset,
    required this.onApplyFont,
    required this.onImportAsset,
    required this.onApplyBackground,
    super.key,
  });

  final List<StudioThemeProject> projects;
  final StudioThemeProject selectedProject;
  final ValueChanged<StudioThemeProject> onSwitchTheme;
  final List<String> assetPaths;
  final StudioAssets assets;
  final SceneEditor? editor;
  final bool loadingFile;
  final bool readOnly;
  final bool supportsImageBackground;
  final ValueChanged<SceneAsset> onPlaceAsset;
  final ValueChanged<String> onApplyFont;
  final VoidCallback onImportAsset;
  final ValueChanged<String> onApplyBackground;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      StudioThemeSelector(
        projects: projects,
        selected: selectedProject,
        onChanged: onSwitchTheme,
      ),
      const Divider(),
      Expanded(
        child: StudioSidebar(
          assetPaths: assetPaths,
          resolveAssetImage: assets.getImageProvider,
          loadAssetText: assets.loadTextAsset,
          loadFontPreview: assets.loadFontPreview,
          onPlaceAsset: onPlaceAsset,
          onApplyFont: onApplyFont,
          editor: editor,
          loadingFile: loadingFile,
          readOnly: readOnly,
          onImportAsset: onImportAsset,
          onApplyBackground: supportsImageBackground ? onApplyBackground : null,
        ),
      ),
    ],
  );
}

class StudioInspectorPane extends StatelessWidget {
  const StudioInspectorPane({
    required this.editor,
    required this.theme,
    required this.assets,
    required this.inspect,
    required this.effects,
    required this.onSelectTab,
    required this.onAssetsChanged,
    super.key,
  });

  final SceneEditor editor;
  final ThemeDefinition theme;
  final StudioAssets assets;
  final bool inspect;
  final bool effects;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onAssetsChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Tabs(
          index: inspect
              ? 2
              : effects
              ? 1
              : 0,
          expand: true,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          onChanged: onSelectTab,
          children: [
            for (final label in ['Design', 'Effects', 'Inspect code'])
              TabItem(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                  ).small(),
                ),
              ),
          ],
        ),
      ),
      const Divider(),
      Expanded(
        child: inspect
            ? CodeInspector(key: ObjectKey(editor), editor: editor)
            : effects
            ? StudioEffectsInspector(
                editor: editor,
                theme: theme,
                assets: assets,
                onAssetsChanged: onAssetsChanged,
              )
            : NodeInspector(
                editor: editor,
                controller: editor.inspector,
                componentCatalog: editor.componentCatalog,
                onApply: editor.tryApplyDraft,
              ),
      ),
    ],
  );
}
