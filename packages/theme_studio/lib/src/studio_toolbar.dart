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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([editor, editor?.inspector]),
    builder: (context, _) {
      final session = editor;
      final hasDraft = session != null && session.inspector.hasDraft;
      final canUndo = session != null && session.canUndo;
      final canRedo = session != null && session.canRedo;
      final isDirty = session != null && session.isDirty;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.panelsTopLeft, size: 20),
                const Gap(12),
                const Text('Theme Studio').semiBold(),
                const Gap(16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(
                    themeId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ).muted(),
                ),
              ],
            ),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlineButton(
                      key: const ValueKey('create-theme'),
                      onPressed: !readOnly && session != null
                          ? onCreateTheme
                          : null,
                      child: const Text('Create theme'),
                    ),
                    const Gap(8),
                    OutlineButton(
                      onPressed:
                          !readOnly && session != null && preferencesReady
                          ? onOpenSettings
                          : null,
                      child: const Text('Settings'),
                    ),
                  ],
                ),
                Text(hasDraft || isDirty ? 'Unsaved changes' : 'Saved')
                    .small()
                    .muted(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // When an inspector field has an uncommitted draft, Undo resets the
                    // draft to the current revision without popping an undo stack entry.
                    OutlineButton(
                      onPressed: !readOnly && (hasDraft || canUndo)
                          ? session.undo
                          : null,
                      child: const Text('Undo'),
                    ),
                    const Gap(8),
                    OutlineButton(
                      onPressed: !readOnly && canRedo ? session.redo : null,
                      child: const Text('Redo'),
                    ),
                    const Gap(16),
                    PrimaryButton(
                      onPressed: session == null ? null : onSave,
                      child: const Text('Save scene'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
