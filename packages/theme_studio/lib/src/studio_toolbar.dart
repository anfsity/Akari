import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'scene_editor.dart';

class StudioToolbar extends StatelessWidget {
  const StudioToolbar({
    required this.themeId,
    required this.editor,
    required this.preferencesReady,
    required this.onOpenSettings,
    required this.onSave,
    super.key,
  });

  final String themeId;
  final SceneEditor? editor;
  final bool preferencesReady;
  final VoidCallback onOpenSettings;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([editor, editor?.inspector]),
    builder: (context, _) {
      final session = editor;
      final hasDraft = session?.inspector.hasDraft == true;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            const Icon(LucideIcons.panelsTopLeft, size: 20),
            const Gap(12),
            const Text('Theme Studio').semiBold(),
            const Gap(16),
            Text(themeId).muted(),
            const Spacer(),
            OutlineButton(
              onPressed: session != null && preferencesReady
                  ? onOpenSettings
                  : null,
              child: const Text('Settings'),
            ),
            const Gap(16),
            Text(
              hasDraft || session?.isDirty == true
                  ? 'Unsaved changes'
                  : 'Saved',
            ).small().muted(),
            const Gap(16),
            OutlineButton(
              onPressed: hasDraft || session?.canUndo == true
                  ? session?.undo
                  : null,
              child: const Text('Undo'),
            ),
            const Gap(8),
            OutlineButton(
              onPressed: session?.canRedo == true ? session?.redo : null,
              child: const Text('Redo'),
            ),
            const Gap(16),
            PrimaryButton(
              onPressed: session == null ? null : onSave,
              child: const Text('Save scene'),
            ),
          ],
        ),
      );
    },
  );
}
