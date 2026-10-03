import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'scene_editor.dart';
import 'studio_preferences.dart';
import 'studio_preview.dart';

class StudioCanvas extends StatefulWidget {
  const StudioCanvas({
    required this.editor,
    required this.theme,
    required this.preferences,
    required this.dormant,
    required this.onToggleDormant,
    super.key,
  });

  final SceneEditor? editor;
  final ThemeDefinition theme;
  final StudioPreferences preferences;
  final bool dormant;
  final VoidCallback onToggleDormant;

  @override
  State<StudioCanvas> createState() => _StudioCanvasState();
}

class _StudioCanvasState extends State<StudioCanvas> {
  StudioCanvasTool _tool = StudioCanvasTool.move;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.muted.withValues(alpha: 0.3),
    child: ListenableBuilder(
      listenable: Listenable.merge([widget.editor]),
      builder: (context, _) {
        final session = widget.editor;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PreviewHeader(
              dormant: widget.dormant,
              onToggleDormant: widget.onToggleDormant,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tool in StudioCanvasTool.values)
                    Button(
                      style: tool == _tool
                          ? const ButtonStyle.primary()
                          : const ButtonStyle.outline(),
                      onPressed: () => setState(() => _tool = tool),
                      child: Text(tool.label),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: session == null
                    ? const Center(child: Text('Unable to open scene'))
                    : StudioPreview(
                        key: ObjectKey(session),
                        theme: widget.theme,
                        document: session.document,
                        selectedId: session.selectedId,
                        dormant: widget.dormant,
                        preferences: widget.preferences,
                        tool: _tool,
                        onSelect: session.selectNode,
                        onStartDrag: (id) => session.selectNode(id)
                            ? session.selectedNode
                            : null,
                        onCommitDrag: session.updateNode,
                        onDragNodeChanged: session.inspector.updatePreviewNode,
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                session == null
                    ? 'Choose a valid scene document.'
                    : '${session.document.canvas.referenceWidth} × ${session.document.canvas.referenceHeight}  ·  ${_tool.hint}  ·  Simulated data',
                textAlign: TextAlign.center,
              ).small().muted(),
            ),
          ],
        );
      },
    ),
  );
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({required this.dormant, required this.onToggleDormant});

  final bool dormant;
  final VoidCallback onToggleDormant;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        const Text('Preview').semiBold(),
        const Spacer(),
        OutlineButton(
          onPressed: onToggleDormant,
          child: Text(dormant ? 'State: Dormant' : 'State: Login'),
        ),
      ],
    ),
  );
}
