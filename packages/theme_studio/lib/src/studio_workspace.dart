import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'studio_input.dart';
import 'studio_form.dart';
import 'studio_workspace_layout.dart';

class StudioWorkspaceScope extends InheritedWidget {
  const StudioWorkspaceScope({
    required this.presenting,
    required super.child,
    this.mode = StudioWorkspaceMode.design,
    super.key,
  });
  final bool presenting;
  final StudioWorkspaceMode mode;
  @override
  bool updateShouldNotify(StudioWorkspaceScope old) =>
      old.presenting != presenting || old.mode != mode;
}

/// Dock regions own widths; global keys carry panel state between regions and
/// floating windows. Hiding and switching tabs leave their contents mounted.
class StudioWorkspace extends StatefulWidget {
  const StudioWorkspace({
    required this.toolbar,
    required this.sidebar,
    required this.canvas,
    required this.inspector,
    required this.statusBar,
    required this.onSave,
    this.onOpenSettings,
    this.onCanvasKeyEvent,
    this.input = const StudioInputBindings(),
    super.key,
  });
  final Widget toolbar;
  final Widget sidebar;
  final Widget canvas;
  final Widget inspector;
  final Widget statusBar;
  final VoidCallback onSave;
  final VoidCallback? onOpenSettings;
  final KeyEventResult Function(KeyEvent)? onCanvasKeyEvent;
  final StudioInputBindings input;
  @override
  State<StudioWorkspace> createState() => _StudioWorkspaceState();
}

class _StudioWorkspaceState extends State<StudioWorkspace> {
  final _sidebar = AbsoluteResizablePaneController(
    StudioWorkspaceLayout.defaultLeftWidth,
  );
  final _inspector = AbsoluteResizablePaneController(
    StudioWorkspaceLayout.defaultRightWidth,
  );
  final _sidebarKey = GlobalKey();
  final _inspectorKey = GlobalKey();
  StudioDock _sidebarDock = StudioDock.left;
  StudioDock _inspectorDock = StudioDock.right;
  bool _sidebarVisible = true;
  bool _inspectorVisible = true;
  bool _presenting = false;
  StudioWorkspaceMode _mode = StudioWorkspaceMode.design;
  String _leftActive = 'Sidebar';
  String _rightActive = 'Inspector';
  Rect _sidebarBounds = const Rect.fromLTWH(16, 16, 300, 520);
  Rect _inspectorBounds = const Rect.fromLTWH(460, 16, 300, 520);
  Timer? _saveTimer;
  int _layoutRevision = 0;
  bool _restoring = false;
  String? _workspaceError;

  @override
  void initState() {
    super.initState();
    _sidebar.addListener(_scheduleSave);
    _inspector.addListener(_scheduleSave);
    unawaited(_restoreLayout());
  }

  StudioDock _getDock(String title) =>
      title == 'Sidebar' ? _sidebarDock : _inspectorDock;
  bool _isVisible(String title) =>
      title == 'Sidebar' ? _sidebarVisible : _inspectorVisible;
  List<String> _getPanels(StudioDock dock) => [
    for (final title in ['Sidebar', 'Inspector'])
      if (_getDock(title) == dock) title,
  ];

  List<String> _getRailPanels(StudioDock dock) => [
    for (final title in ['Sidebar', 'Inspector'])
      if (_getDock(title) == dock ||
          (_getDock(title) == StudioDock.floating &&
              !_isVisible(title) &&
              (title == 'Sidebar' ? StudioDock.left : StudioDock.right) ==
                  dock))
        title,
  ];

  StudioWorkspaceLayout _getLayout() => StudioWorkspaceLayout(
    mode: _mode,
    sidebarDock: _sidebarDock,
    inspectorDock: _inspectorDock,
    sidebarVisible: _sidebarVisible,
    inspectorVisible: _inspectorVisible,
    leftWidth: _sidebar.value,
    rightWidth: _inspector.value,
    sidebarBounds: _sidebarBounds,
    inspectorBounds: _inspectorBounds,
  );

  Future<void> _restoreLayout() async {
    final revision = _layoutRevision;
    try {
      final layout = await StudioWorkspaceLayout.load();
      if (!mounted || revision != _layoutRevision) return;
      _restoring = true;
      setState(() {
        _sidebarDock = layout.sidebarDock;
        _inspectorDock = layout.inspectorDock;
        _sidebarVisible = layout.sidebarVisible;
        _inspectorVisible = layout.inspectorVisible;
        _sidebar.size = layout.leftWidth;
        _inspector.size = layout.rightWidth;
        _sidebarBounds = layout.sidebarBounds;
        _inspectorBounds = layout.inspectorBounds;
        _mode = layout.mode;
        _updatePanels();
      });
      _restoring = false;
    } on Object {
      if (mounted) {
        setState(
          () => _workspaceError = 'Saved workspace could not be restored. Choose a workspace preset to reset it.',
        );
      }
    }
  }

  void _scheduleSave() {
    if (_restoring) return;
    _layoutRevision++;
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_saveLayout()),
    );
  }

  Future<void> _saveLayout() async {
    try {
      await _getLayout().save();
    } on Object {
      if (mounted) {
        setState(() => _workspaceError = 'Workspace could not be saved.');
      }
    }
  }

  void _updatePanels() {
    _presenting || !_getPanels(StudioDock.left).any(_isVisible)
        ? _sidebar.collapse()
        : _sidebar.expand();
    _presenting || !_getPanels(StudioDock.right).any(_isVisible)
        ? _inspector.collapse()
        : _inspector.expand();
  }

  void _togglePanel(String title) {
    setState(() {
      if (title == 'Sidebar') {
        _sidebarVisible = !_sidebarVisible;
      } else {
        _inspectorVisible = !_inspectorVisible;
      }
      if (_isVisible(title)) {
        if (_getDock(title) == StudioDock.left) _leftActive = title;
        if (_getDock(title) == StudioDock.right) _rightActive = title;
      }
      _updatePanels();
    });
    _scheduleSave();
  }

  void _togglePresentation() => setState(() {
    FocusManager.instance.primaryFocus?.unfocus();
    _presenting = !_presenting;
    _restoring = true;
    _updatePanels();
    _restoring = false;
  });

  void _setDock(String title, StudioDock dock) {
    setState(() {
      if (title == 'Sidebar') {
        _sidebarDock = dock;
        _sidebarVisible = true;
      } else {
        _inspectorDock = dock;
        _inspectorVisible = true;
      }
      if (dock == StudioDock.left) _leftActive = title;
      if (dock == StudioDock.right) _rightActive = title;
      _updatePanels();
    });
    _scheduleSave();
  }

  void _applyPreset(StudioWorkspaceMode mode) {
    setState(() {
      _mode = mode;
      _presenting = false;
      _workspaceError = null;
      _sidebarDock = mode == StudioWorkspaceMode.motion
          ? StudioDock.right
          : StudioDock.left;
      _inspectorDock = StudioDock.right;
      _sidebarVisible = _inspectorVisible = mode != StudioWorkspaceMode.focus;
      _sidebar.size = StudioWorkspaceLayout.defaultLeftWidth;
      _inspector.size = StudioWorkspaceLayout.defaultRightWidth;
      _leftActive = 'Sidebar';
      _rightActive = 'Inspector';
      _updatePanels();
    });
    _scheduleSave();
  }

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      unawaited(_saveLayout());
    }
    _sidebar.dispose();
    _inspector.dispose();
    super.dispose();
  }

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

  Widget _panelHeader(String title, StudioDock side) {
    final collapse = _button(
      title == 'Sidebar' ? 'toggle-sidebar' : 'toggle-inspector',
      'Collapse panel',
      side == StudioDock.left
          ? LucideIcons.chevronLeft
          : LucideIcons.chevronRight,
      () => _togglePanel(title),
    );
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          if (side == StudioDock.left) collapse,
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: () => _togglePanel(title),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(title == 'Sidebar' ? 'Project' : 'Properties')
                    .small()
                    .semiBold(),
              ),
            ),
          ),
          _button(
            'float-$title',
            'Float panel',
            LucideIcons.externalLink,
            () => _setDock(title, StudioDock.floating),
          ),
          if (side == StudioDock.right) collapse,
        ],
      ),
    );
  }

  Widget _buildDockGroup(
    AbsoluteResizablePaneController controller,
    StudioDock side,
    Map<String, Widget> contents,
  ) {
    final panels = _getPanels(side);
    final visible = panels.where(_isVisible).toList();
    final preferred = side == StudioDock.left ? _leftActive : _rightActive;
    final active = visible.contains(preferred)
        ? preferred
        : visible.firstOrNull;
    return Stack(
      fit: StackFit.expand,
      children: [
        OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: controller.value,
          maxWidth: controller.value,
          child: Visibility(
            visible: !controller.collapsed,
            maintainState: true,
            child: Column(
              children: [
                if (visible.length > 1)
                  Row(
                    children: [
                      for (final title in visible)
                        Expanded(
                          child: Button(
                            key: ValueKey('dock-tab-$title'),
                            style: active == title
                                ? const ButtonStyle.secondary()
                                : const ButtonStyle.ghost(),
                            onPressed: () => setState(() {
                              if (side == StudioDock.left) {
                                _leftActive = title;
                              } else {
                                _rightActive = title;
                              }
                            }),
                            child: Text(
                              title == 'Sidebar' ? 'Project' : 'Properties',
                            ).small(),
                          ),
                        ),
                    ],
                  ),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      for (final title in panels)
                        Offstage(
                          offstage: active != title || _presenting,
                          child: Column(
                            children: [
                              _panelHeader(title, side),
                              const Divider(),
                              Expanded(child: contents[title]!),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (controller.collapsed && !_presenting)
          Align(
            alignment: Alignment.topCenter,
            child: Column(
              children: [
                for (final title in _getRailPanels(side))
                  _button(
                    title == 'Sidebar' ? 'toggle-sidebar' : 'toggle-inspector',
                    'Show ${title == 'Sidebar' ? 'project' : 'properties'} panel',
                    side == StudioDock.left
                        ? LucideIcons.chevronRight
                        : LucideIcons.chevronLeft,
                    () => _togglePanel(title),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      for (final entry in <StudioCommand, VoidCallback>{
        StudioCommand.save: widget.onSave,
        StudioCommand.sidebar: () => _togglePanel('Sidebar'),
        StudioCommand.inspector: () => _togglePanel('Inspector'),
        StudioCommand.presentation: _togglePresentation,
        if (widget.onOpenSettings != null)
          StudioCommand.settings: widget.onOpenSettings!,
      }.entries)
        if (widget.input.getBinding(entry.key) case final binding?)
          binding.getActivator(repeats: false): entry.value,
      if (_presenting)
        const SingleActivator(LogicalKeyboardKey.escape): _togglePresentation,
    },
    child: StudioWorkspaceScope(
      presenting: _presenting,
      mode: _mode,
      child: Focus(
        onKeyEvent: (_, event) {
          final focused = FocusManager.instance.primaryFocus?.context;
          if (focused?.findAncestorWidgetOfExactType<EditableText>() != null) {
            return KeyEventResult.ignored;
          }
          return widget.onCanvasKeyEvent?.call(event) ?? KeyEventResult.ignored;
        },
        child: Scaffold(
          child: ListenableBuilder(
            listenable: Listenable.merge([_sidebar, _inspector]),
            builder: (context, _) {
              final contents = <String, Widget>{
                'Sidebar': KeyedSubtree(
                  key: _sidebarKey,
                  child: widget.sidebar,
                ),
                'Inspector': KeyedSubtree(
                  key: _inspectorKey,
                  child: widget.inspector,
                ),
              };
              return LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: math.max(
                        384 +
                            (_sidebar.collapsed ? 32 : _sidebar.value) +
                            (_inspector.collapsed ? 32 : _inspector.value),
                        constraints.maxWidth,
                      ),
                      height: math.max(420, constraints.maxHeight),
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
                                    SizedBox(
                                      width: 168,
                                      child: StudioEnumSelect(
                                        key: const ValueKey('workspace-preset'),
                                        value: _mode,
                                        values: StudioWorkspaceMode.values,
                                        formatValue: (value) =>
                                            '${value.name[0].toUpperCase()}${value.name.substring(1)} layout',
                                        onChanged: _applyPreset,
                                      ),
                                    ),
                                    _button(
                                      'presentation-mode',
                                      'Presentation · ${widget.input.getBinding(StudioCommand.presentation)?.getLabel() ?? 'Unbound'}',
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
                                      draggerThickness: _presenting ? 0 : 6,
                                      children: [
                                        ResizablePane.controlled(
                                          key: const ValueKey('sidebar-pane'),
                                          controller: _sidebar,
                                          minSize: 216,
                                          maxSize: 360,
                                          collapsedSize: _sidebar.collapsed
                                              ? (_presenting ||
                                                        _getPanels(
                                                          StudioDock.left,
                                                        ).isEmpty
                                                    ? 0
                                                    : 32)
                                              : null,
                                          child: _buildDockGroup(
                                            _sidebar,
                                            StudioDock.left,
                                            contents,
                                          ),
                                        ),
                                        ResizablePane.flex(
                                          minSize: 360,
                                          child: widget.canvas,
                                        ),
                                        ResizablePane.controlled(
                                          key: const ValueKey('inspector-pane'),
                                          controller: _inspector,
                                          minSize: 260,
                                          maxSize: 420,
                                          collapsedSize: _inspector.collapsed
                                              ? (_presenting ||
                                                        _getPanels(
                                                          StudioDock.right,
                                                        ).isEmpty
                                                    ? 0
                                                    : 32)
                                              : null,
                                          child: _buildDockGroup(
                                            _inspector,
                                            StudioDock.right,
                                            contents,
                                          ),
                                        ),
                                      ],
                                    ),
                                    for (final title in [
                                      'Sidebar',
                                      'Inspector',
                                    ])
                                      if (_getDock(title) ==
                                          StudioDock.floating)
                                        Visibility(
                                          key: ValueKey('floating-host-$title'),
                                          visible:
                                              !_presenting && _isVisible(title),
                                          maintainState: true,
                                          child: _FloatingPanel(
                                            title: title,
                                            initialBounds: title == 'Sidebar'
                                                ? _sidebarBounds
                                                : _inspectorBounds,
                                            onDock: () => _setDock(
                                              title,
                                              title == 'Sidebar'
                                                  ? StudioDock.left
                                                  : StudioDock.right,
                                            ),
                                            onDockTo: (side) =>
                                                _setDock(title, side),
                                            onChanged: (bounds) {
                                              if (title == 'Sidebar') {
                                                _sidebarBounds = bounds;
                                              } else {
                                                _inspectorBounds = bounds;
                                              }
                                              _scheduleSave();
                                            },
                                            child: contents[title]!,
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
                              if (_workspaceError != null)
                                Text(_workspaceError!).small(),
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
    ),
  );
}

class _FloatingPanel extends StatefulWidget {
  const _FloatingPanel({
    required this.title,
    required this.initialBounds,
    required this.onChanged,
    required this.onDockTo,
    required this.onDock,
    required this.child,
  });
  final String title;
  final Rect initialBounds;
  final ValueChanged<Rect> onChanged;
  final ValueChanged<StudioDock> onDockTo;
  final VoidCallback onDock;
  final Widget child;
  @override
  State<_FloatingPanel> createState() => _FloatingPanelState();
}

class _FloatingPanelState extends State<_FloatingPanel> {
  late Offset _offset = widget.initialBounds.topLeft;
  late Size _size = widget.initialBounds.size;
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
                      onPanEnd: (_) {
                        widget.onChanged(_offset & Size(width, height));
                        if (_offset.dx <= 8) widget.onDockTo(StudioDock.left);
                        if (_offset.dx + width >= constraints.maxWidth - 8) {
                          widget.onDockTo(StudioDock.right);
                        }
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
                            Tooltip(
                              tooltip: (_) => const Text('Dock left'),
                              child: GhostButton(
                                key: ValueKey('dock-left-${widget.title}'),
                                onPressed: () =>
                                    widget.onDockTo(StudioDock.left),
                                density: ButtonDensity.icon,
                                child: const Icon(
                                  LucideIcons.panelLeft,
                                  size: 14,
                                ),
                              ),
                            ),
                            Tooltip(
                              tooltip: (_) => const Text('Dock right'),
                              child: GhostButton(
                                key: ValueKey('dock-right-${widget.title}'),
                                onPressed: () =>
                                    widget.onDockTo(StudioDock.right),
                                density: ButtonDensity.icon,
                                child: const Icon(
                                  LucideIcons.panelRight,
                                  size: 14,
                                ),
                              ),
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
                        onPanEnd: (_) => widget.onChanged(offset & _size),
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
