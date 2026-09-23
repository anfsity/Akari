import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mozais_scene_schema/mozais_scene_schema.dart';

import 'editor_controller.dart';
import 'editor_strings.dart';
import 'editor_widgets.dart';
import 'file_picker_dialog.dart';

/// Edits the document-level canvas and background.
class DocumentPanel extends StatelessWidget {
  const DocumentPanel({required this.controller, super.key});

  final SceneEditorController controller;

  @override
  Widget build(BuildContext context) {
    final document = controller.document;
    if (document == null) {
      return const SizedBox.shrink();
    }
    final strings = EditorStringsScope.of(context);
    final background = document.background;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SectionCard(
          title: strings.canvas,
          children: [
            EnumDropdown<SceneCanvasFit>(
              label: strings.canvasFit,
              value: document.canvas.fit,
              values: SceneCanvasFit.values,
              onChanged: (value) => controller.updateDocument(
                (document) => document.copyWith(
                  canvas: document.canvas.copyWith(fit: value),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SwitchRow(
              label: strings.useSafeArea,
              value: document.canvas.useSafeArea,
              onChanged: (value) => controller.updateDocument(
                (document) => document.copyWith(
                  canvas: document.canvas.copyWith(useSafeArea: value),
                ),
              ),
            ),
          ],
        ),
        SectionCard(
          title: strings.background,
          children: [
            EnumDropdown<SceneBackgroundKind>(
              label: strings.backgroundKind,
              value: background.kind,
              values: SceneBackgroundKind.values,
              onChanged: (value) => controller.updateDocument(
                (document) => document.copyWith(
                  background: document.background.copyWith(kind: value),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _AssetRow(controller: controller, background: background),
            if (background.kind == SceneBackgroundKind.video)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  strings.noVideoRenderer,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 8),
            _ColorField(
              label: strings.backgroundColor,
              value: background.color,
              onChanged: (value) => controller.updateDocument(
                (document) => document.copyWith(
                  background: document.background.copyWith(color: value),
                ),
              ),
            ),
            LabeledSlider(
              label: strings.scrimOpacity,
              value: background.scrimOpacity,
              min: 0,
              max: 1,
              onChanged: (value) => controller.updateDocument(
                (document) => document.copyWith(
                  background: document.background.copyWith(scrimOpacity: value),
                ),
              ),
            ),
            LabeledSlider(
              label: strings.blurSigma,
              value: background.blurSigma,
              min: 0,
              max: 64,
              onChanged: (value) => controller.updateDocument(
                (document) => document.copyWith(
                  background: document.background.copyWith(blurSigma: value),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({required this.controller, required this.background});

  final SceneEditorController controller;
  final SceneBackground background;

  Future<void> _import(BuildContext context) async {
    final file = await pickFile(context, initialDirectory: _homeDirectory());
    if (file != null) {
      await controller.importBackgroundAsset(file);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = EditorStringsScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(width: 80, child: Text(strings.backgroundAsset)),
            Expanded(
              child: Text(
                background.asset ?? strings.none,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton(
            onPressed: () => _import(context),
            child: Text(strings.importBackground),
          ),
        ),
      ],
    );
  }
}

class _ColorField extends StatelessWidget {
  const _ColorField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final hex = encodeSceneColor(value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label)),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Color(value),
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              key: ValueKey(hex),
              initialValue: hex,
              decoration: const InputDecoration(isDense: true),
              onFieldSubmitted: (text) {
                final parsed = _parseColor(text);
                if (parsed != null) {
                  onChanged(parsed);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

Directory? _homeDirectory() {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    return null;
  }
  final directory = Directory(home);
  return directory.existsSync() ? directory : null;
}

int? _parseColor(String text) {
  try {
    return decodeSceneColor(text.trim());
  } on FormatException {
    return null;
  }
}
