import 'dart:io';

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:theme_sdk/theme_sdk.dart';

import '../resources/confined_path.dart';
import '../ui/studio_form.dart';

Future<bool?> confirmUnsavedSceneSwitch(BuildContext context) =>
    showOverlay<bool>(
      context,
      const DialogConfiguration(),
      builder: (context) => AlertDialog(
        title: const Text('Unsaved scene changes'),
        content: const Text(
          'Save this scene before opening another project or scene?',
        ),
        actions: [
          OutlineButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          OutlineButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Discard and switch'),
          ),
          PrimaryButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save and switch'),
          ),
        ],
      ),
    ).future;

class StudioNewSceneDialog extends StatefulWidget {
  const StudioNewSceneDialog({
    required this.directoryPath,
    required this.canvas,
    super.key,
  });

  final String directoryPath;
  final SceneCanvas canvas;

  @override
  State<StudioNewSceneDialog> createState() => _StudioNewSceneDialogState();
}

class _StudioNewSceneDialogState extends State<StudioNewSceneDialog> {
  final _name = TextEditingController(text: 'new-scene');
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _create() {
    final id = _name.text.trim();
    if (!RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(id)) {
      setState(() => _error = 'Use a lower-case scene name.');
      return;
    }
    final file = findConfinedFile(
      Directory(widget.directoryPath),
      'lib/$id.scene.json',
    );
    if (file == null) {
      setState(
        () => _error = 'Scene files must stay inside the current theme.',
      );
      return;
    }
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      setState(() => _error = 'This scene already exists.');
      return;
    }
    try {
      final source = encodeSceneDocument(
        SceneDocument(
          id: id,
          version: currentSceneVersion,
          canvas: widget.canvas,
          background: const SceneBackground(kind: SceneBackgroundKind.solid),
          nodes: const [
            SceneNode(
              id: 'artboard',
              componentId: 'frame',
              layout: SceneLayout(),
              rect: SceneRect(x: 0, y: 0, width: 1, height: 1),
            ),
          ],
        ),
      );
      writeFileAtomically(file, '$source\n', tempName: '$id.scene.json');
      Navigator.of(context).pop(file.path);
    } on FileSystemException catch (failure) {
      setState(() => _error = failure.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New scene'),
    content: SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Start with an empty artboard in the current theme.'),
          const Gap(12),
          TextField(key: const ValueKey('new-scene-name'), controller: _name),
          if (_error != null) StudioFormError(_error!),
        ],
      ),
    ),
    actions: [
      OutlineButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      PrimaryButton(
        key: const ValueKey('confirm-new-scene'),
        onPressed: _create,
        child: const Text('Create scene'),
      ),
    ],
  );
}
