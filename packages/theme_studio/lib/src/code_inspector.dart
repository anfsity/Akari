import 'dart:convert';

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
      final json = sceneDocumentToMap(document);
      final source = switch ((_format, _wholeScene)) {
        (_CodeFormat.json, true) => encodeSceneDocument(document),
        (_CodeFormat.json, false) => const JsonEncoder.withIndent('  ').convert(
          (json['nodes'] as List).firstWhere((entry) => entry['id'] == node.id),
        ),
        (_CodeFormat.dart, true) => generateScene(
          encodeSceneDocument(document),
        ),
        (_CodeFormat.dart, false) => generateSceneNode(node).trim(),
      };
      final canvas = document.canvas;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(node.id, overflow: TextOverflow.ellipsis).semiBold(),
                Text(node.componentId).small().muted(),
                const Gap(8),
                Text(
                  '${(node.rect.width * canvas.referenceWidth).toStringAsFixed(1)} × '
                  '${(node.rect.height * canvas.referenceHeight).toStringAsFixed(1)} px',
                ).small().muted(),
                const Gap(12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final format in _CodeFormat.values)
                      Button(
                        style: _format == format
                            ? const ButtonStyle.secondary()
                            : const ButtonStyle.ghost(),
                        onPressed: () => setState(() => _format = format),
                        child: Text(
                          format == _CodeFormat.json ? 'JSON' : 'Dart',
                        ),
                      ),
                  ],
                ),
                const Gap(8),
                Row(
                  children: [
                    for (final wholeScene in [false, true])
                      Expanded(
                        child: Button(
                          style: _wholeScene == wholeScene
                              ? const ButtonStyle.secondary()
                              : const ButtonStyle.ghost(),
                          onPressed: () =>
                              setState(() => _wholeScene = wholeScene),
                          child: Text(wholeScene ? 'Scene' : 'Selection'),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                source,
                key: const ValueKey('inspect-code-source'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlineButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: source)),
              child: const Text('Copy code'),
            ),
          ),
        ],
      );
    },
  );
}
