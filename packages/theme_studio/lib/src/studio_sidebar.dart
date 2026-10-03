import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'scene_editor.dart';

class StudioSidebar extends StatelessWidget {
  const StudioSidebar({
    required this.scenePaths,
    required this.assetPaths,
    required this.editor,
    required this.loadingFile,
    required this.onLoadJson,
    required this.onSwitchScene,
    required this.onImportAsset,
    required this.onApplyBackground,
    super.key,
  });

  final List<String> scenePaths;
  final List<String> assetPaths;
  final SceneEditor? editor;
  final bool loadingFile;
  final VoidCallback onLoadJson;
  final ValueChanged<String> onSwitchScene;
  final VoidCallback onImportAsset;
  final ValueChanged<String> onApplyBackground;

  @override
  Widget build(BuildContext context) {
    final session = editor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ResizablePanel.vertical(
            key: const ValueKey('sidebar-panels'),
            draggerThickness: 10,
            children: [
              ResizablePane.flex(
                key: const ValueKey('scenes-pane'),
                initialFlex: 0.3,
                minSize: 128,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _SidebarHeading('SCENES'),
                    Expanded(
                      child: _SceneList(
                        paths: scenePaths,
                        loadingFile: loadingFile,
                        onLoadJson: onLoadJson,
                        onSwitchScene: onSwitchScene,
                      ),
                    ),
                  ],
                ),
              ),
              ResizablePane.flex(
                key: const ValueKey('layers-pane'),
                initialFlex: 0.4,
                minSize: 100,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _SidebarHeading('LAYERS'),
                    if (session != null)
                      Expanded(child: _LayerList(editor: session)),
                  ],
                ),
              ),
              ResizablePane.flex(
                key: const ValueKey('assets-pane'),
                initialFlex: 0.3,
                minSize: 128,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _SidebarHeading('ASSETS'),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: OutlineButton(
                        onPressed: loadingFile ? null : onImportAsset,
                        child: const Text('Import asset'),
                      ),
                    ),
                    Expanded(
                      child: _AssetList(
                        paths: assetPaths,
                        onApplyBackground: session == null
                            ? null
                            : onApplyBackground,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        if (session != null) _NodeActions(editor: session),
      ],
    );
  }
}

class _SidebarHeading extends StatelessWidget {
  const _SidebarHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(title).small().muted(),
  );
}

class _SceneList extends StatelessWidget {
  const _SceneList({
    required this.paths,
    required this.loadingFile,
    required this.onLoadJson,
    required this.onSwitchScene,
  });

  final List<String> paths;
  final bool loadingFile;
  final VoidCallback onLoadJson;
  final ValueChanged<String> onSwitchScene;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: OutlineButton(
          onPressed: loadingFile ? null : onLoadJson,
          child: const Text('Load JSON'),
        ),
      ),
      const Gap(8),
      Expanded(
        child: ListView.builder(
          itemCount: paths.length,
          itemBuilder: (context, index) {
            final path = paths[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: GhostButton(
                onPressed: () => onSwitchScene(path),
                child: Text(
                  File(path).uri.pathSegments.last,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          },
        ),
      ),
    ],
  );
}

class _AssetList extends StatelessWidget {
  const _AssetList({required this.paths, required this.onApplyBackground});

  final List<String> paths;
  final ValueChanged<String>? onApplyBackground;

  @override
  Widget build(BuildContext context) {
    final applyBackground = onApplyBackground;
    return ListView.builder(
      itemCount: paths.length,
      itemBuilder: (context, index) {
        final asset = paths[index];
        return Row(
          children: [
            Expanded(
              child: GhostButton(
                onPressed: () => Clipboard.setData(ClipboardData(text: asset)),
                child: Text(
                  asset.split('/').last,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (applyBackground != null)
              GhostButton(
                onPressed: () => applyBackground(asset),
                child: const Text('Use image'),
              ),
          ],
        );
      },
    );
  }
}

class _LayerList extends StatelessWidget {
  const _LayerList({required this.editor});

  final SceneEditor editor;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: editor,
    builder: (context, _) {
      final nodes = editor.document.paintOrder.reversed.toList();
      return ListView.builder(
        itemCount: nodes.length,
        itemBuilder: (context, index) {
          final node = nodes[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Button(
              key: ValueKey('layer-${node.id}'),
              style: node.id == editor.selectedId
                  ? const ButtonStyle.secondary()
                  : const ButtonStyle.ghost(),
              onPressed: () => editor.selectNode(node.id),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(node.id, overflow: TextOverflow.ellipsis),
                    Text(node.componentId).small().muted(),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

class _NodeActions extends StatelessWidget {
  const _NodeActions({required this.editor});

  final SceneEditor editor;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: editor,
    builder: (context, _) => Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlineButton(
            onPressed: editor.duplicateSelectedNode,
            child: const Text('Duplicate node'),
          ),
          const Gap(8),
          OutlineButton(
            onPressed: editor.canDeleteNode ? editor.deleteSelectedNode : null,
            child: const Text('Delete node'),
          ),
          if (!editor.canDeleteNode) ...[
            const Gap(8),
            const Text('A scene needs at least one node.').small().muted(),
          ],
        ],
      ),
    ),
  );
}
