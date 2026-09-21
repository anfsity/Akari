import 'package:flutter/material.dart';

import 'editor_controller.dart';
import 'inspector_panel.dart';
import 'node_list_panel.dart';
import 'scene_preview.dart';

class SceneEditorApp extends StatelessWidget {
  const SceneEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mozais Scene Editor',
      theme: ThemeData.dark(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: const EditorScreen(),
    );
  }
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final SceneEditorController _controller;
  late final TextEditingController _pathController;

  @override
  void initState() {
    super.initState();
    _controller = SceneEditorController();
    final path = defaultScenePath() ?? '';
    _controller.setPath(path);
    _pathController = TextEditingController(text: path);
    if (path.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _controller.open());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mozais Scene Editor'),
        actions: [
          SizedBox(
            width: 420,
            child: TextField(
              controller: _pathController,
              decoration: const InputDecoration(
                hintText: 'path/to/scene.json',
                isDense: true,
              ),
              onChanged: _controller.setPath,
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _controller.open,
            child: const Text('Open'),
          ),
          TextButton(
            onPressed: _controller.save,
            child: const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Row(
          children: [
            SizedBox(
              width: 240,
              child: NodeListPanel(controller: _controller),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: ScenePreview(controller: _controller)),
            const VerticalDivider(width: 1),
            SizedBox(
              width: 360,
              child: InspectorPanel(controller: _controller),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => _StatusBar(controller: _controller),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.controller});

  final SceneEditorController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          if (controller.dirty)
            const Text('unsaved changes', style: TextStyle(color: Colors.orange)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              controller.status,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
