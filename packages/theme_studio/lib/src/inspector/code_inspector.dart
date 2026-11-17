import 'package:flutter/services.dart';
import 'package:scene/scene.dart';
import 'package:scene_codegen/scene_codegen.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../authoring/scene_editor.dart';

enum _CodeFormat { json, dart }

/// Inspection reads committed authoring state and shares Dart generation with
/// build_runner, so copied constructors cannot drift from the compiled scene.
class CodeInspector extends StatefulWidget {
  const CodeInspector({required this.editor, super.key});

  final SceneEditor editor;

  @override
  State<CodeInspector> createState() => _CodeInspectorState();
}

class _CodeInspectorState extends State<CodeInspector> {
  _CodeFormat _format = _CodeFormat.json;
  bool _wholeScene = false;

  Widget _buildSegmentedControl<T>({
    required BuildContext context,
    required T value,
    required List<T> values,
    required String Function(T) getLabel,
    required ValueChanged<T> onChanged,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.muted.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(theme.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          spacing: 2,
          children: [
            for (final option in values)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: value == option,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(option),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        alignment: Alignment.center,
                        decoration: value == option
                            ? BoxDecoration(
                                color: colors.background,
                                borderRadius: BorderRadius.circular(
                                  (theme.radiusMd - 2).clamp(
                                    0,
                                    double.infinity,
                                  ),
                                ),
                                border: Border.all(
                                  color: colors.border.withValues(alpha: 0.6),
                                ),
                              )
                            : null,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: value == option
                              ? Text(
                                  getLabel(option),
                                  maxLines: 1,
                                ).xSmall().medium()
                              : Text(
                                  getLabel(option),
                                  maxLines: 1,
                                ).xSmall().muted(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.editor,
    builder: (context, _) {
      final document = widget.editor.document;
      final hasSelection = widget.editor.selectedIds.isNotEmpty;
      final node = hasSelection ? widget.editor.selectedNode : null;
      final String? source = switch ((_format, _wholeScene)) {
        (_CodeFormat.json, true) => widget.editor.encodedDocument,
        (_CodeFormat.json, false) => node == null ? null : encodeSceneNode(node),
        (_CodeFormat.dart, true) => generateSceneFromDocument(document),
        (_CodeFormat.dart, false) =>
          node == null ? null : generateSceneNode(node).trim(),
      };
      final canvas = document.canvas;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 2,
                        children: [
                          Text(
                            node?.id ?? 'No selection',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ).small().semiBold(),
                          Text(
                            node == null
                                ? 'Whole scene'
                                : '${node.componentId} · '
                                      '${(node.rect.width * canvas.referenceWidth).toStringAsFixed(1)} × '
                                      '${(node.rect.height * canvas.referenceHeight).toStringAsFixed(1)} px',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ).xSmall().muted(),
                        ],
                      ),
                    ),
                    const Gap(8),
                    OutlineButton(
                      density: ButtonDensity.compact,
                      leading: const Icon(LucideIcons.copy, size: 13),
                      onPressed: source == null
                          ? null
                          : () =>
                                Clipboard.setData(ClipboardData(text: source)),
                      child: const Text('Copy code').xSmall(),
                    ),
                  ],
                ),
                Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      flex: 4,
                      child: _buildSegmentedControl<_CodeFormat>(
                        context: context,
                        value: _format,
                        values: _CodeFormat.values,
                        getLabel: (format) =>
                            format == _CodeFormat.json ? 'JSON' : 'Dart',
                        onChanged: (format) => setState(() => _format = format),
                      ),
                    ),
                    Expanded(
                      flex: 5,
                      child: _buildSegmentedControl<bool>(
                        context: context,
                        value: _wholeScene,
                        values: const [false, true],
                        getLabel: (wholeScene) =>
                            wholeScene ? 'Scene' : 'Selection',
                        onChanged: (wholeScene) =>
                            setState(() => _wholeScene = wholeScene),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: source == null
                ? const Center(child: Text('Select a layer or switch to Scene.'))
                : LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: constraints.maxWidth - 24,
                          ),
                          child: SelectableText(
                            source,
                            key: const ValueKey('inspect-code-source'),
                            style: Theme.of(context).typography.mono.copyWith(
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      );
    },
  );
}
