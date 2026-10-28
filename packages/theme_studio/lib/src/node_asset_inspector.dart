import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'scene_editor.dart';
import 'studio_form.dart';

class NodeAssetInspector extends StatelessWidget {
  const NodeAssetInspector({required this.editor, super.key});
  final SceneEditor editor;
  void _updateAsset(SceneAsset Function(SceneAsset) update) {
    if (!editor.applyDraft()) return;
    editor.updateNode(
      editor.selectedNode.copyWith(asset: update(editor.selectedNode.asset!)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asset = editor.selectedNode.asset!;
    return StudioFormSection(
      title: asset.kind == SceneAssetKind.svg ? 'SVG icon' : 'Image',
      children: [
        Text(asset.path.split('/').last).xSmall().muted(),
        StudioEnumSelect(
          key: const ValueKey('asset-fit'),
          label: 'Fit',
          value: asset.fit,
          values: SceneAssetFit.values,
          onChanged: (value) =>
              _updateAsset((asset) => asset.copyWith(fit: value)),
        ),
        StudioSwitchRow(
          label: 'Override color',
          value: asset.tint != null,
          onChanged: (enabled) => _updateAsset(
            (asset) => asset.copyWith(tint: enabled ? 0xffffffff : null),
          ),
        ),
        if (asset.tint != null)
          ColorInput(
            key: const ValueKey('node-asset-tint'),
            value: ColorDerivative.fromColor(Color(asset.tint!)),
            onChanged: (value) => _updateAsset(
              (asset) => asset.copyWith(tint: value.toColor().toARGB32()),
            ),
          ),
      ],
    );
  }
}
