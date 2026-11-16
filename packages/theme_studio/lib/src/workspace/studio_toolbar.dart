import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../authoring/scene_editor.dart';

class StudioToolbar extends StatelessWidget {
  const StudioToolbar({
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
    this.readOnly = false,
    super.key,
  });

  final bool readOnly;
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

  void _openSceneMenu(BuildContext context) {
    showDropdown<void>(
      context: context,
      alignment: Alignment.topLeft,
      anchorAlignment: Alignment.bottomLeft,
      builder: (_) => DropdownMenu(
        children: [
          const MenuLabel(child: Text('Scenes')),
          for (final path in scenePaths)
            MenuButton(
              leading: Icon(
                path == scenePath ? LucideIcons.check : LucideIcons.fileJson,
                size: 16,
              ),
              onPressed: (_) => onSwitchScene(path),
              child: Text(path.split('/').last),
            ),
          const MenuDivider(),
          MenuButton(
            key: const ValueKey('new-scene'),
            leading: const Icon(LucideIcons.filePlus2, size: 16),
            enabled: !readOnly && editor != null,
            onPressed: (_) => onCreateScene(),
            child: const Text('New scene'),
          ),
          MenuButton(
            key: const ValueKey('create-theme'),
            leading: const Icon(LucideIcons.folderPlus, size: 16),
            enabled: !readOnly && editor != null,
            onPressed: (_) => onCreateTheme(),
            child: const Text('Create theme'),
          ),
        ],
      ),
    );
  }

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
      return Padding(
        key: const ValueKey('studio-toolbar'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.06),
                border: Border.all(
                  color: colors.primary.withValues(alpha: .15),
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('T', style: TextStyle(color: colors.primary)).small(),
            ),
            const Gap(8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => Tooltip(
                  tooltip: (_) =>
                      Text('$themeId / ${scenePath.split('/').last}'),
                  child: GhostButton(
                    key: const ValueKey('studio-scene-menu'),
                    density: ButtonDensity.compact,
                    onPressed: () => _openSceneMenu(context),
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
                        if (constraints.maxWidth >= 260) ...[
                          const Gap(10),
                          const Text('/').small().muted(),
                          const Gap(10),
                          Flexible(
                            child: Text(
                              scenePath.split('/').last,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ).small().muted(),
                          ),
                        ],
                        const Gap(8),
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
            const Gap(12),
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
