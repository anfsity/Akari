import 'package:flutter/services.dart';
import 'package:scene/scene.dart';
import 'package:scene_codegen/scene_codegen.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'scene_editor.dart';

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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.editor,
    builder: (context, _) {
      final document = widget.editor.document;
      final node = widget.editor.selectedNode;
      final source = switch ((_format, _wholeScene)) {
        (_CodeFormat.json, true) => widget.editor.encodedDocument,
        (_CodeFormat.json, false) => encodeSceneNode(node),
        (_CodeFormat.dart, true) => generateSceneFromDocument(document),
        (_CodeFormat.dart, false) => generateSceneNode(node).trim(),
      };
      final canvas = document.canvas;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 2,
              children: [
                Text(
                  node.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ).small().semiBold(),
                Text(
                  '${node.componentId} · '
                  '${(node.rect.width * canvas.referenceWidth).toStringAsFixed(1)} × '
                  '${(node.rect.height * canvas.referenceHeight).toStringAsFixed(1)} px',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ).xSmall().muted(),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 6,
              children: [
                Row(
                  spacing: 4,
                  children: [
                    for (final format in _CodeFormat.values)
                      Expanded(
                        child: Button(
                          style: _format == format
                              ? const ButtonStyle.secondary(
                                  density: ButtonDensity.dense,
                                )
                              : const ButtonStyle.ghost(
                                  density: ButtonDensity.dense,
                                ),
                          onPressed: () => setState(() => _format = format),
                          child: Text(
                            format == _CodeFormat.json ? 'JSON' : 'Dart',
                          ).small(),
                        ),
                      ),
                  ],
                ),
                Row(
                  spacing: 4,
                  children: [
                    for (final wholeScene in [false, true])
                      Expanded(
                        child: Button(
                          style: _wholeScene == wholeScene
                              ? const ButtonStyle.secondary(
                                  density: ButtonDensity.dense,
                                )
                              : const ButtonStyle.ghost(
                                  density: ButtonDensity.dense,
                                ),
                          onPressed: () =>
                              setState(() => _wholeScene = wholeScene),
                          child: Text(
                            wholeScene ? 'Scene' : 'Selection',
                          ).small(),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: LayoutBuilder(
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
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: OutlineButton(
                density: ButtonDensity.dense,
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: source)),
                child: const Text('Copy code').small(),
              ),
            ),
          ),
        ],
      );
    },
  );
}
