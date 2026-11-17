import 'dart:async';

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
  String? _copiedSource;
  Timer? _copyTimer;

  Future<void> _copyCode(String source) async {
    await Clipboard.setData(ClipboardData(text: source));
    if (!mounted) return;
    _copyTimer?.cancel();
    setState(() => _copiedSource = source);
    _copyTimer = Timer(const Duration(milliseconds: 1500), () {
      setState(() => _copiedSource = null);
    });
  }

  @override
  void dispose() {
    _copyTimer?.cancel();
    super.dispose();
  }

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
                  child: Button(
                    style:
                        const ButtonStyle.ghost(density: ButtonDensity.compact)
                            .copyWith(
                              decoration: (context, states, decoration) =>
                                  (decoration as BoxDecoration).copyWith(
                                    color: value == option
                                        ? colors.background
                                        : decoration.color,
                                    border: value == option
                                        ? Border.all(
                                            color: colors.border.withValues(
                                              alpha: .6,
                                            ),
                                          )
                                        : null,
                                  ),
                            ),
                    onPressed: () => onChanged(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Center(
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
        (_CodeFormat.json, false) =>
          node == null ? null : encodeSceneNode(node),
        (_CodeFormat.dart, true) => generateSceneFromDocument(document),
        (_CodeFormat.dart, false) =>
          node == null ? null : generateSceneNode(node).trim(),
      };
      final nodeSize = node == null
          ? null
          : widget.editor.getNodePixelSize(node);
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
                                      '${nodeSize!.width.toStringAsFixed(1)} × '
                                      '${nodeSize.height.toStringAsFixed(1)} px',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ).xSmall().muted(),
                        ],
                      ),
                    ),
                    const Gap(8),
                    GhostButton(
                      key: const ValueKey('inspect-copy-code'),
                      density: ButtonDensity.dense,
                      leading: Icon(
                        source != null && _copiedSource == source
                            ? LucideIcons.check
                            : LucideIcons.copy,
                        size: 14,
                      ),
                      onPressed: source == null
                          ? null
                          : () => _copyCode(source),
                      child: SizedBox(
                        width: 80,
                        child: AnimatedSwitcher(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 120),
                          child: Text(
                            source != null && _copiedSource == source
                                ? 'Copied'
                                : 'Copy code',
                            maxLines: 1,
                            softWrap: false,
                            key: ValueKey(
                              source != null && _copiedSource == source,
                            ),
                          ).small(),
                        ),
                      ),
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
                ? const Center(
                    child: Text('Select a layer or switch to Scene.'),
                  )
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
                            style: Theme.of(context).typography.mono
                                .copyWith(fontSize: 12),
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
