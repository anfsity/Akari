import 'dart:math' as math;

import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Workspace layout owns panel sizing and scrolling. Its slots keep editor
/// actions and panel contents out of the responsive layout tree.
class StudioWorkspace extends StatelessWidget {
  const StudioWorkspace({
    required this.toolbar,
    required this.sidebar,
    required this.canvas,
    required this.inspector,
    required this.statusBar,
    super.key,
  });

  final Widget toolbar;
  final Widget sidebar;
  final Widget canvas;
  final Widget inspector;
  final Widget statusBar;

  @override
  Widget build(BuildContext context) => Scaffold(
    child: _WorkspaceViewport(
      child: Column(
        children: [
          toolbar,
          const Divider(),
          Expanded(
            child: _WorkspacePanels(
              sidebar: sidebar,
              canvas: canvas,
              inspector: inspector,
            ),
          ),
          const Divider(),
          statusBar,
        ],
      ),
    ),
  );
}

class _WorkspaceViewport extends StatelessWidget {
  const _WorkspaceViewport({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: math.max(1100, constraints.maxWidth),
          height: math.max(720, constraints.maxHeight),
          child: child,
        ),
      ),
    ),
  );
}

class _WorkspacePanels extends StatelessWidget {
  const _WorkspacePanels({
    required this.sidebar,
    required this.canvas,
    required this.inspector,
  });

  final Widget sidebar;
  final Widget canvas;
  final Widget inspector;

  @override
  Widget build(BuildContext context) => ResizablePanel.horizontal(
    key: const ValueKey('workspace-panels'),
    draggerThickness: 10,
    children: [
      ResizablePane(
        key: const ValueKey('sidebar-pane'),
        initialSize: 220,
        minSize: 200,
        maxSize: 360,
        child: sidebar,
      ),
      ResizablePane.flex(minSize: 300, child: canvas),
      ResizablePane(
        key: const ValueKey('inspector-pane'),
        initialSize: 300,
        minSize: 280,
        maxSize: 420,
        child: inspector,
      ),
    ],
  );
}
