import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../model/studio_input.dart';
import '../model/studio_workspace_layout.dart';
import '../ui/studio_form.dart';
import 'studio_floating_panel.dart';
import 'studio_toolbar.dart';
import 'studio_workspace_dock.dart';

export '../model/studio_workspace_layout.dart' show StudioWorkspaceScope;

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
    unawaited(_loadLayout());
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

  Future<void> _loadLayout() async {
    final revision = _layoutRevision;
    try {
      final layout = await StudioWorkspaceLayout.load();
      if (!mounted || revision != _layoutRevision) return;
      _restoring = true;
      try {
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
      } finally {
        _restoring = false;
      }
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
    try {
      _updatePanels();
    } finally {
      _restoring = false;
    }
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
      final layout = _getLayout();
      unawaited(layout.save().catchError((Object _) {}));
    }
    _sidebar.dispose();
    _inspector.dispose();
    super.dispose();
  }

  double _getDockExtent(
    AbsoluteResizablePaneController controller,
    StudioDock side,
  ) {
    if (!controller.collapsed) return controller.value;
    return _presenting || _getRailPanels(side).isEmpty ? 0 : 32;
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
    return WorkspaceDockPanel(
      controller: controller,
      side: side,
      presenting: _presenting,
      panels: panels,
      visible: visible,
      active: active,
      railPanels: _getRailPanels(side),
      contents: contents,
      onSelectTab: (panel) => setState(() {
        if (side == StudioDock.left) {
          _leftActive = panel;
        } else {
          _rightActive = panel;
        }
      }),
      onFloat: (panel) => _setDock(panel, StudioDock.floating),
      onTogglePanel: _togglePanel,
    );
  }

  static bool _hasModifier(StudioKeyBinding binding) =>
      binding.control || binding.alt || binding.meta;

  Map<StudioCommand, VoidCallback> _buildWorkspaceCommands() => {
    StudioCommand.save: widget.onSave,
    StudioCommand.sidebar: () => _togglePanel('Sidebar'),
    StudioCommand.inspector: () => _togglePanel('Inspector'),
    StudioCommand.presentation: _togglePresentation,
    if (widget.onOpenSettings != null)
      StudioCommand.settings: widget.onOpenSettings!,
  };

  KeyEventResult _handleWorkspaceKeyEvent(
    KeyEvent event,
    Map<StudioCommand, VoidCallback> workspaceCommands,
  ) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    for (final entry in workspaceCommands.entries) {
      if (widget.input.getBinding(entry.key) case final binding?
          when !_hasModifier(binding) &&
              binding
                  .getActivator(repeats: false)
                  .accepts(event, HardwareKeyboard.instance)) {
        entry.value();
        return KeyEventResult.handled;
      }
    }
    return widget.onCanvasKeyEvent?.call(event) ?? KeyEventResult.ignored;
  }

  Widget _buildDockedPanels(Map<String, Widget> contents) =>
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
                ? _getDockExtent(_sidebar, StudioDock.left)
                : null,
            child: _buildDockGroup(_sidebar, StudioDock.left, contents),
          ),
          ResizablePane.flex(minSize: 360, child: widget.canvas),
          ResizablePane.controlled(
            key: const ValueKey('inspector-pane'),
            controller: _inspector,
            minSize: 260,
            maxSize: 420,
            collapsedSize: _inspector.collapsed
                ? _getDockExtent(_inspector, StudioDock.right)
                : null,
            child: _buildDockGroup(_inspector, StudioDock.right, contents),
          ),
        ],
      );

  Iterable<Widget> _buildFloatingPanels(Map<String, Widget> contents) => [
    for (final title in ['Sidebar', 'Inspector'])
      if (_getDock(title) == StudioDock.floating)
        Visibility(
          key: ValueKey('floating-host-$title'),
          visible: !_presenting && _isVisible(title),
          maintainState: true,
          child: WorkspaceFloatingPanel(
            title: title,
            initialBounds: title == 'Sidebar'
                ? _sidebarBounds
                : _inspectorBounds,
            onDock: () => _setDock(
              title,
              title == 'Sidebar' ? StudioDock.left : StudioDock.right,
            ),
            onDockTo: (side) => _setDock(title, side),
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
  ];

  Widget _buildWorkspaceShell(
    Widget topBar,
    Widget statusBar,
    Map<String, Widget> contents,
  ) => ListenableBuilder(
    listenable: Listenable.merge([_sidebar, _inspector]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(
              384 +
                  _getDockExtent(_sidebar, StudioDock.left) +
                  _getDockExtent(_inspector, StudioDock.right),
              constraints.maxWidth,
            ),
            height: math.max(420, constraints.maxHeight),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Column(
                  children: [
                    topBar,
                    if (!_presenting) const Divider(),
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _buildDockedPanels(contents),
                          ..._buildFloatingPanels(contents),
                        ],
                      ),
                    ),
                    statusBar,
                    if (_workspaceError != null)
                      StudioFormError(_workspaceError!),
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
    ),
  );

  @override
  Widget build(BuildContext context) {
    final workspaceControls = WorkspaceModeControls(
      mode: _mode,
      presentationLabel:
          'Presentation · ${widget.input.getBinding(StudioCommand.presentation)?.getLabel() ?? 'Unbound'}',
      onPresetChanged: _applyPreset,
      onTogglePresentation: _togglePresentation,
    );
    final topBar = Visibility(
      visible: !_presenting,
      maintainState: true,
      child: WorkspaceTopBar(
        toolbar: widget.toolbar,
        workspaceControls: widget.toolbar is StudioToolbar
            ? null
            : workspaceControls,
        onToggleSidebar: () => _togglePanel('Sidebar'),
      ),
    );
    final statusBar = Visibility(
      visible: !_presenting,
      maintainState: true,
      child: widget.statusBar,
    );
    final contents = <String, Widget>{
      'Sidebar': KeyedSubtree(key: _sidebarKey, child: widget.sidebar),
      'Inspector': KeyedSubtree(key: _inspectorKey, child: widget.inspector),
    };
    final workspaceCommands = _buildWorkspaceCommands();
    return CallbackShortcuts(
      bindings: {
        for (final entry in workspaceCommands.entries)
          if (widget.input.getBinding(entry.key) case final binding?
              when _hasModifier(binding))
            binding.getActivator(repeats: false): entry.value,
        if (_presenting)
          const SingleActivator(LogicalKeyboardKey.escape): _togglePresentation,
      },
      child: StudioWorkspaceScope(
        presenting: _presenting,
        mode: _mode,
        workspaceControls: workspaceControls,
        child: Focus(
          onKeyEvent: (_, event) =>
              _handleWorkspaceKeyEvent(event, workspaceCommands),
          child: Scaffold(
            child: _buildWorkspaceShell(topBar, statusBar, contents),
          ),
        ),
      ),
    );
  }
}
