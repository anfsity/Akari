import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../authoring/scene_editor.dart';
import '../authoring/studio_theme_project.dart';
import '../inspector/studio_form.dart';
import 'studio_workspace.dart';

class StudioToolbar extends StatelessWidget {
  const StudioToolbar({
    required this.projects,
    required this.selectedProject,
    required this.onSwitchTheme,
    required this.themeId,
    required this.scenePath,
    required this.scenePaths,
    required this.onSwitchScene,
    required this.editor,
    required this.preferencesReady,
    required this.onOpenSettings,
    required this.onSave,
    required this.onCreateTheme,
    required this.onCreateScene,
    required this.onReload,
    required this.onLoadJson,
    this.loadingFile = false,
    this.readOnly = false,
    super.key,
  });

  final bool readOnly;
  final bool loadingFile;
  final List<StudioThemeProject> projects;
  final StudioThemeProject selectedProject;
  final ValueChanged<StudioThemeProject> onSwitchTheme;
  final String themeId;
  final String scenePath;
  final List<String> scenePaths;
  final ValueChanged<String> onSwitchScene;
  final SceneEditor? editor;
  final bool preferencesReady;
  final VoidCallback onOpenSettings;
  final VoidCallback onSave;
  final VoidCallback onCreateTheme;
  final VoidCallback onCreateScene;
  final VoidCallback onReload;
  final VoidCallback onLoadJson;

  void _openSceneMenu(BuildContext context) {
    final themesIndex = scenePath.indexOf('/themes/');
    final displayPath = themesIndex >= 0
        ? scenePath.substring(themesIndex + 1)
        : scenePath;
    final groupId = Object();
    showOverlay<void>(
      context,
      PopoverConfiguration(
        alignment: Alignment.topLeft,
        anchorAlignment: Alignment.bottomLeft,
        offset: const Offset(0, 6),
        regionGroupId: groupId,
      ),
      builder: (popoverContext) {
        final theme = Theme.of(popoverContext);
        final colors = theme.colorScheme;
        return SurfaceCard(
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            width: 312,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('File path').xSmall().muted(),
                const Gap(6),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.background,
                    border: Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(theme.radiusMd),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: SelectableText(
                      displayPath,
                      style: theme.typography.mono.copyWith(fontSize: 12),
                    ),
                  ),
                ),
                const Gap(12),
                Row(
                  children: [
                    const Text('Current theme').small().muted(),
                    const Gap(12),
                    Expanded(
                      child: StudioSelect<StudioThemeProject>(
                        key: const ValueKey('toolbar-theme-select'),
                        value: selectedProject,
                        values: projects,
                        formatValue: (project) => project.packageName,
                        regionGroupId: groupId,
                        onChanged: (project) {
                          if (!identical(project, selectedProject)) {
                            closeOverlay(popoverContext);
                            onSwitchTheme(project);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const Gap(12),
                const Text('Scenes').xSmall().muted(),
                const Gap(6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 132),
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      for (var i = 0; i < scenePaths.length; i++) ...[
                        if (i > 0) const Gap(2),
                        GhostButton(
                          density: ButtonDensity.dense,
                          onPressed: () {
                            closeOverlay(popoverContext);
                            onSwitchScene(scenePaths[i]);
                          },
                          child: Row(
                            children: [
                              Icon(
                                scenePaths[i] == scenePath
                                    ? LucideIcons.check
                                    : LucideIcons.fileJson,
                                size: 14,
                                color: scenePaths[i] == scenePath
                                    ? colors.primary
                                    : colors.mutedForeground,
                              ),
                              const Gap(8),
                              Expanded(
                                child: scenePaths[i] == scenePath
                                    ? Text(
                                        scenePaths[i].split('/').last,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ).small().medium()
                                    : Text(
                                        scenePaths[i].split('/').last,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ).small().muted(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Gap(12),
                const Divider(),
                const Gap(12),
                Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: _buildPopoverButton(
                        key: 'new-scene',
                        label: 'New scene',
                        icon: LucideIcons.filePlus2,
                        enabled: !readOnly && editor != null,
                        onPressed: () {
                          closeOverlay(popoverContext);
                          onCreateScene();
                        },
                      ),
                    ),
                    Expanded(
                      child: _buildPopoverButton(
                        key: 'create-theme',
                        label: 'Create theme',
                        icon: LucideIcons.folderPlus,
                        enabled: !readOnly && editor != null,
                        onPressed: () {
                          closeOverlay(popoverContext);
                          onCreateTheme();
                        },
                      ),
                    ),
                  ],
                ),
                const Gap(8),
                Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: _buildPopoverButton(
                        key: 'toolbar-reload-disk',
                        label: 'Reload from disk',
                        icon: LucideIcons.rotateCcw,
                        onPressed: () {
                          closeOverlay(popoverContext);
                          onReload();
                        },
                      ),
                    ),
                    Expanded(
                      child: _buildPopoverButton(
                        key: 'toolbar-load-json',
                        label: 'Load JSON',
                        icon: LucideIcons.folderOpen,
                        enabled: !loadingFile,
                        onPressed: () {
                          closeOverlay(popoverContext);
                          onLoadJson();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPopoverButton({
    required String key,
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    bool enabled = true,
  }) => OutlineButton(
    key: ValueKey(key),
    density: ButtonDensity.dense,
    alignment: Alignment.center,
    enabled: enabled,
    leading: Icon(icon, size: 14),
    onPressed: onPressed,
    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis).small(),
  );

  Widget _buildAction({
    required String key,
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) => Tooltip(
    tooltip: (_) => Text(label),
    child: Semantics(
      label: label,
      child: ComponentTheme<OutlineButtonTheme>(
        data: OutlineButtonTheme(
          decoration: (context, states, value) =>
              ButtonVariance.ghost.decoration(context, states),
        ),
        child: OutlineButton(
          key: ValueKey(key),
          density: ButtonDensity.icon,
          onPressed: onPressed,
          child: Icon(icon, size: 16),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([editor, editor?.inspector]),
    builder: (context, _) {
      final session = editor;
      final hasDraft = session != null && session.inspector.hasDraft;
      final canUndo = session != null && session.canUndo;
      final canRedo = session != null && session.canRedo;
      final isDirty = session != null && session.isDirty;
      final colors = Theme.of(context).colorScheme;
      final workspaceControls = context
          .dependOnInheritedWidgetOfExactType<StudioWorkspaceScope>()
          ?.workspaceControls;
      return Padding(
        key: const ValueKey('studio-toolbar'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Flexible(
              child: LayoutBuilder(
                builder: (context, constraints) => Tooltip(
                  tooltip: (_) =>
                      Text('$themeId / ${scenePath.split('/').last}'),
                  child: GhostButton(
                    key: const ValueKey('studio-scene-menu'),
                    density: ButtonDensity.compact,
                    onPressed: () => _openSceneMenu(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              themeId,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ).small().semiBold(),
                          ),
                          if (constraints.maxWidth >= 240) ...[
                            const Gap(6),
                            const Text('/').small().muted(),
                            const Gap(6),
                            Flexible(
                              child: Text(
                                scenePath.split('/').last,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ).small().muted(),
                            ),
                          ],
                          const Gap(6),
                          Icon(
                            LucideIcons.chevronDown,
                            size: 14,
                            color: colors.mutedForeground,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            const Gap(12),
            if (workspaceControls != null) ...[
              workspaceControls,
              const Gap(8),
              const SizedBox(height: 18, child: VerticalDivider()),
              const Gap(8),
            ],
            // Undo clears an uncommitted inspector draft before it consumes
            // a scene history entry.
            _buildAction(
              key: 'toolbar-undo',
              label: 'Undo',
              icon: LucideIcons.undo2,
              onPressed: !readOnly && (hasDraft || canUndo)
                  ? session.undo
                  : null,
            ),
            const Gap(2),
            _buildAction(
              key: 'toolbar-redo',
              label: 'Redo',
              icon: LucideIcons.redo2,
              onPressed: !readOnly && canRedo ? session.redo : null,
            ),
            const Gap(8),
            const SizedBox(height: 18, child: VerticalDivider()),
            const Gap(8),
            _buildAction(
              key: 'toolbar-settings',
              label: 'Settings',
              icon: LucideIcons.settings2,
              onPressed: !readOnly && session != null && preferencesReady
                  ? onOpenSettings
                  : null,
            ),
            const Gap(8),
            Tooltip(
              tooltip: (_) =>
                  Text(hasDraft || isDirty ? 'Unsaved changes' : 'Saved'),
              child: Text(hasDraft || isDirty ? 'Unsaved changes' : 'Saved')
                  .xSmall()
                  .muted(),
            ),
            const Gap(10),
            PrimaryButton(
              key: const ValueKey('toolbar-save'),
              density: ButtonDensity.dense,
              onPressed: session == null ? null : onSave,
              child: const Text('Save scene').small(),
            ),
          ],
        ),
      );
    },
  );
}
