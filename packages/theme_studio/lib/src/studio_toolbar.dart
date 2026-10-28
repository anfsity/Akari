import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'scene_editor.dart';

class StudioToolbar extends StatelessWidget {
  const StudioToolbar({
    required this.themeId,
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
  final SceneEditor? editor;
  final bool preferencesReady;
  final VoidCallback onOpenSettings;
  final VoidCallback onSave;
  final VoidCallback onCreateTheme;
  final VoidCallback onCreateScene;

  Widget _buildAction({
    required String key,
    required String label,
    required IconData icon,
    required bool compact,
    required VoidCallback? onPressed,
  }) => Tooltip(
    tooltip: (_) => Text(label),
    child: Semantics(
      label: compact ? label : null,
      child: OutlineButton(
        key: ValueKey(key),
        density: compact ? ButtonDensity.icon : ButtonDensity.normal,
        onPressed: onPressed,
        child: compact
            ? Icon(icon, size: 16)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [Icon(icon, size: 16), const Gap(6), Text(label)],
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
      return LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1100;
          return Padding(
            key: const ValueKey('studio-toolbar'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(LucideIcons.panelsTopLeft, size: 20),
                const Gap(10),
                if (!compact) ...[
                  const Text('Theme Studio').semiBold(),
                  const Gap(12),
                ],
                Expanded(
                  child: Text(
                    themeId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ).small().muted(),
                ),
                const Gap(12),
                _buildAction(
                  key: 'new-scene',
                  label: 'New scene',
                  icon: LucideIcons.filePlus2,
                  compact: compact,
                  onPressed: !readOnly && session != null
                      ? onCreateScene
                      : null,
                ),
                const Gap(4),
                _buildAction(
                  key: 'create-theme',
                  label: 'Create theme',
                  icon: LucideIcons.folderPlus,
                  compact: compact,
                  onPressed: !readOnly && session != null
                      ? onCreateTheme
                      : null,
                ),
                const Gap(4),
                _buildAction(
                  key: 'toolbar-settings',
                  label: 'Settings',
                  icon: LucideIcons.settings2,
                  compact: compact,
                  onPressed: !readOnly && session != null && preferencesReady
                      ? onOpenSettings
                      : null,
                ),
                const Gap(12),
                // Undo clears an uncommitted inspector draft before it consumes
                // a scene history entry, including in the compact toolbar.
                _buildAction(
                  key: 'toolbar-undo',
                  label: 'Undo',
                  icon: LucideIcons.undo2,
                  compact: compact,
                  onPressed: !readOnly && (hasDraft || canUndo)
                      ? session.undo
                      : null,
                ),
                const Gap(4),
                _buildAction(
                  key: 'toolbar-redo',
                  label: 'Redo',
                  icon: LucideIcons.redo2,
                  compact: compact,
                  onPressed: !readOnly && canRedo ? session.redo : null,
                ),
                const Gap(12),
                Text(hasDraft || isDirty ? 'Unsaved changes' : 'Saved')
                    .small()
                    .muted(),
                const Gap(12),
                PrimaryButton(
                  key: const ValueKey('toolbar-save'),
                  onPressed: session == null ? null : onSave,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!compact) ...[
                        const Icon(LucideIcons.save, size: 16),
                        const Gap(6),
                      ],
                      const Text('Save scene'),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
