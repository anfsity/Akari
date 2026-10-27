import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

class StudioWorkspaceScope extends InheritedWidget {
  const StudioWorkspaceScope({
    required this.presenting,
    required super.child,
    super.key,
  });
  final bool presenting;
  @override
  bool updateShouldNotify(StudioWorkspaceScope old) =>
      old.presenting != presenting;
}

/// Panel controllers own docked widths. Global keys carry panel state between
/// dock and floating hosts; hiding a panel keeps its subtree mounted offstage.
class StudioWorkspace extends StatefulWidget {
  const StudioWorkspace({
    required this.toolbar,
    required this.sidebar,
    required this.canvas,
    required this.inspector,
    required this.statusBar,
    required this.onSave,
    super.key,
  });
  final Widget toolbar;
  final Widget sidebar;
  final Widget canvas;
  final Widget inspector;
  final Widget statusBar;
  final VoidCallback onSave;
  @override
  State<StudioWorkspace> createState() => _StudioWorkspaceState();
}

class _StudioWorkspaceState extends State<StudioWorkspace> {
  final _sidebar = AbsoluteResizablePaneController(260);
  final _inspector = AbsoluteResizablePaneController(300);
  final _sidebarKey = GlobalKey();
  final _inspectorKey = GlobalKey();
  bool _sidebarVisible = true;
  bool _inspectorVisible = true;
  bool _sidebarFloating = false;
  bool _inspectorFloating = false;
  bool _presenting = false;

  void _updatePanels() {
    _presenting || !_sidebarVisible || _sidebarFloating
        ? _sidebar.collapse()
        : _sidebar.expand();
    _presenting || !_inspectorVisible || _inspectorFloating
        ? _inspector.collapse()
        : _inspector.expand();
  }

  void _toggleSidebar() => setState(() {
    _sidebarVisible = !_sidebarVisible;
    _updatePanels();
  });
  void _toggleInspector() => setState(() {
    _inspectorVisible = !_inspectorVisible;
    _updatePanels();
  });
  void _togglePresentation() => setState(() {
    FocusManager.instance.primaryFocus?.unfocus();
    _presenting = !_presenting;
    _updatePanels();
  });
  void _toggleSidebarDock() => setState(() {
    _sidebarFloating = !_sidebarFloating;
    _updatePanels();
  });
  void _toggleInspectorDock() => setState(() {
    _inspectorFloating = !_inspectorFloating;
    _updatePanels();
  });
  @override
  void dispose() {
    _sidebar.dispose();
    _inspector.dispose();
    super.dispose();
  }

  Widget _panelHeader(
    String title,
    VoidCallback onCollapse,
    VoidCallback onFloat,
  ) {
    final left = title == 'Sidebar';
    final collapse = _button(
      left ? 'toggle-sidebar' : 'toggle-inspector',
      left ? 'Collapse project panel' : 'Collapse properties panel',
      left ? LucideIcons.chevronLeft : LucideIcons.chevronRight,
      onCollapse,
    );
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          if (left) collapse,
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: onCollapse,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(left ? 'Project' : 'Properties').small().semiBold(),
              ),
            ),
          ),
          _button(
            'float-$title',
            'Float panel',
            LucideIcons.externalLink,
            onFloat,
          ),
          if (!left) collapse,
        ],
      ),
    );
  }

  Widget _buildDockedPanel(
    AbsoluteResizablePaneController controller,
    String title,
    Widget child,
    bool floating,
    VoidCallback onToggle,
    VoidCallback onFloat,
  ) => Stack(
    fit: StackFit.expand,
    children: [
      _pane(
        controller,
        floating
            ? const SizedBox()
            : Column(
                children: [
                  _panelHeader(title, onToggle, onFloat),
                  const Divider(),
                  Expanded(child: child),
                ],
              ),
      ),
      if (controller.collapsed && !_presenting)
        Align(
          alignment: title == 'Sidebar'
              ? Alignment.topLeft
              : Alignment.topRight,
          child: _button(
            title == 'Sidebar' ? 'toggle-sidebar' : 'toggle-inspector',
            'Show panel',
            title == 'Sidebar'
                ? LucideIcons.chevronRight
                : LucideIcons.chevronLeft,
            onToggle,
          ),
        ),
    ],
  );

  Widget _pane(AbsoluteResizablePaneController controller, Widget child) =>
      OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: controller.value,
        maxWidth: controller.value,
        child: Visibility(
          visible: !controller.collapsed,
          maintainState: true,
          child: child,
        ),
      );

  Widget _button(
    String key,
    String label,
    IconData icon,
    VoidCallback action,
  ) => Tooltip(
    tooltip: (_) => Text(label),
    child: GhostButton(
      key: ValueKey(key),
      onPressed: action,
      density: ButtonDensity.icon,
      child: Icon(icon, size: 16),
    ),
  );

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyS, control: true):
          widget.onSave,
      const SingleActivator(LogicalKeyboardKey.keyB, control: true):
          _toggleSidebar,
      const SingleActivator(
        LogicalKeyboardKey.keyB,
        control: true,
        shift: true,
      ): _toggleInspector,
      const SingleActivator(
        LogicalKeyboardKey.keyP,
        control: true,
        shift: true,
      ): _togglePresentation,
      if (_presenting)
        const SingleActivator(LogicalKeyboardKey.escape): _togglePresentation,
    },
    child: StudioWorkspaceScope(
      presenting: _presenting,
      child: Scaffold(
        child: ListenableBuilder(
          listenable: Listenable.merge([_sidebar, _inspector]),
          builder: (context, _) {
            final sidebar = KeyedSubtree(
              key: _sidebarKey,
              child: widget.sidebar,
            );
            final inspector = KeyedSubtree(
              key: _inspectorKey,
              child: widget.inspector,
            );
            return LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: math.max(
                      _presenting
                          ? 320
                          : math.max(
                              640,
                              320 +
                                  (_sidebar.collapsed ? 0 : _sidebar.value) +
                                  (_inspector.collapsed ? 0 : _inspector.value),
                            ),
                      constraints.maxWidth,
                    ),
                    height: math.max(
                      _presenting ? 200 : 720,
                      constraints.maxHeight,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Column(
                          children: [
                            Visibility(
                              visible: !_presenting,
                              maintainState: true,
                              child: Row(
                                children: [
                                  Expanded(child: widget.toolbar),
                                  _button(
                                    'presentation-mode',
                                    'Presentation · Ctrl+Shift+P',
                                    LucideIcons.maximize,
                                    _togglePresentation,
                                  ),
                                  const Gap(8),
                                ],
                              ),
                            ),
                            if (!_presenting) const Divider(),
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ResizablePanel.horizontal(
                                    key: const ValueKey('workspace-panels'),
                                    draggerThickness: _presenting ? 0 : 10,
                                    children: [
                                      ResizablePane.controlled(
                                        key: const ValueKey('sidebar-pane'),
                                        controller: _sidebar,
                                        minSize: 240,
                                        maxSize: 360,
                                        collapsedSize:
                                            _sidebar.collapsed && !_presenting
                                            ? 32
                                            : 0,
                                        child: _buildDockedPanel(
                                          _sidebar,
                                          'Sidebar',
                                          sidebar,
                                          _sidebarFloating,
                                          _toggleSidebar,
                                          _toggleSidebarDock,
                                        ),
                                      ),
                                      ResizablePane.flex(
                                        minSize: 300,
                                        child: widget.canvas,
                                      ),
                                      ResizablePane.controlled(
                                        key: const ValueKey('inspector-pane'),
                                        controller: _inspector,
                                        minSize: 280,
                                        maxSize: 420,
                                        collapsedSize:
                                            _inspector.collapsed && !_presenting
                                            ? 32
                                            : 0,
                                        child: _buildDockedPanel(
                                          _inspector,
                                          'Inspector',
                                          inspector,
                                          _inspectorFloating,
                                          _toggleInspector,
                                          _toggleInspectorDock,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_sidebarFloating)
                                    Visibility(
                                      key: const ValueKey(
                                        'floating-host-Sidebar',
                                      ),
                                      maintainState: true,
                                      visible: !_presenting && _sidebarVisible,
                                      child: _FloatingPanel(
                                        title: 'Sidebar',
                                        initialOffset: const Offset(16, 16),
                                        onDock: _toggleSidebarDock,
                                        child: sidebar,
                                      ),
                                    ),
                                  if (_inspectorFloating)
                                    Visibility(
                                      key: const ValueKey(
                                        'floating-host-Inspector',
                                      ),
                                      maintainState: true,
                                      visible:
                                          !_presenting && _inspectorVisible,
                                      child: _FloatingPanel(
                                        title: 'Inspector',
                                        initialOffset: const Offset(460, 16),
                                        onDock: _toggleInspectorDock,
                                        child: inspector,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (!_presenting) const Divider(),
                            Visibility(
                              visible: !_presenting,
                              maintainState: true,
                              child: widget.statusBar,
                            ),
                          ],
                        ),
                        if (_presenting)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: OutlineButton(
                              key: const ValueKey('exit-presentation'),
                              onPressed: _togglePresentation,
                              child: const Text('Exit · Esc'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _FloatingPanel extends StatefulWidget {
  const _FloatingPanel({
    required this.title,
    required this.initialOffset,
    required this.onDock,
    required this.child,
  });
  final String title;
  final Offset initialOffset;
  final VoidCallback onDock;
  final Widget child;
  @override
  State<_FloatingPanel> createState() => _FloatingPanelState();
}

class _FloatingPanelState extends State<_FloatingPanel> {
  late Offset _offset = widget.initialOffset;
  Size _size = const Size(300, 520);
  Offset _dragStart = Offset.zero;
  Offset _dragOrigin = Offset.zero;
  Size _resizeOrigin = Size.zero;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = math.min(_size.width, constraints.maxWidth);
      final height = math.min(_size.height, constraints.maxHeight);
      final offset = Offset(
        _offset.dx.clamp(0, constraints.maxWidth - width),
        _offset.dy.clamp(0, constraints.maxHeight - height),
      );
      return Stack(
        children: [
          Positioned(
            left: offset.dx,
            top: offset.dy,
            width: width,
            height: height,
            child: Container(
              key: ValueKey('floating-${widget.title}'),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.background,
                border: Border.all(color: Theme.of(context).colorScheme.border),
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(color: Color(0x40000000), blurRadius: 16),
                ],
              ),
              child: Column(
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.move,
                    child: GestureDetector(
                      key: ValueKey('float-drag-${widget.title}'),
                      behavior: HitTestBehavior.opaque,
                      dragStartBehavior: DragStartBehavior.down,
                      onPanStart: (details) {
                        _dragStart = details.globalPosition;
                        _dragOrigin = offset;
                      },
                      onPanUpdate: (details) => setState(() {
                        final target =
                            _dragOrigin + details.globalPosition - _dragStart;
                        _offset = Offset(
                          target.dx.clamp(0, constraints.maxWidth - width),
                          target.dy.clamp(0, constraints.maxHeight - height),
                        );
                      }),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(widget.title).small().semiBold(),
                            ),
                            OutlineButton(
                              key: ValueKey('dock-${widget.title}'),
                              density: ButtonDensity.compact,
                              onPressed: widget.onDock,
                              child: const Text('Dock').small(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Divider(),
                  Expanded(child: widget.child),
                  Align(
                    alignment: Alignment.centerRight,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeUpLeftDownRight,
                      child: GestureDetector(
                        key: ValueKey('float-resize-${widget.title}'),
                        behavior: HitTestBehavior.opaque,
                        dragStartBehavior: DragStartBehavior.down,
                        onPanStart: (details) {
                          _dragStart = details.globalPosition;
                          _resizeOrigin = Size(width, height);
                        },
                        onPanUpdate: (details) => setState(() {
                          final delta = details.globalPosition - _dragStart;
                          _size = Size(
                            (_resizeOrigin.width + delta.dx).clamp(
                              math.min(240, constraints.maxWidth - offset.dx),
                              math.min(600, constraints.maxWidth - offset.dx),
                            ),
                            (_resizeOrigin.height + delta.dy).clamp(
                              math.min(260, constraints.maxHeight - offset.dy),
                              math.min(900, constraints.maxHeight - offset.dy),
                            ),
                          );
                        }),
                        child: const SizedBox(
                          width: 24,
                          height: 16,
                          child: Icon(LucideIcons.grip, size: 12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}
