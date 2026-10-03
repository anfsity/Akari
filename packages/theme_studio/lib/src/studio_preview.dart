import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'studio_preferences.dart';

/// Renders the compiled theme at its authored resolution. Selection wraps each
/// component inside SceneRuntime so hit testing follows its actual transform,
/// paint order and visibility instead of a second approximation of layout.
class StudioPreview extends StatefulWidget {
  const StudioPreview({
    required this.theme,
    required this.document,
    required this.selectedId,
    required this.dormant,
    required this.onSelect,
    required this.onStartDrag,
    required this.onMove,
    required this.preferences,
    super.key,
  });

  final ThemeDefinition theme;
  final SceneDocument document;
  final String selectedId;
  final bool dormant;
  final StudioPreferences preferences;
  final ValueChanged<String> onSelect;
  final SceneNode? Function(String id) onStartDrag;
  final ValueChanged<SceneNode> onMove;

  @override
  State<StudioPreview> createState() => _StudioPreviewState();
}

class _StudioPreviewState extends State<StudioPreview> {
  final _canvas = GlobalKey();
  SceneNode? _dragSource;
  SceneNode? _dragPreview;
  Offset _dragStart = Offset.zero;

  void _startDrag(String id, DragStartDetails details) {
    final node = widget.onStartDrag(id);
    if (node == null) return;
    final canvas = _canvas.currentContext!.findRenderObject()! as RenderBox;
    setState(() {
      _dragSource = node;
      _dragPreview = node;
      _dragStart = canvas.globalToLocal(details.globalPosition);
    });
  }

  void _updateDrag(DragUpdateDetails details) {
    final node = _dragSource;
    if (node == null) return;
    // Convert through the canvas, not the transformed node: rotation, scale
    // and fit-to-workspace must not change the direction or speed of a drag.
    final canvas = _canvas.currentContext!.findRenderObject()! as RenderBox;
    final delta = canvas.globalToLocal(details.globalPosition) - _dragStart;
    final grid = widget.preferences.gridSize;
    var x = node.rect.x * canvas.size.width + delta.dx;
    var y = node.rect.y * canvas.size.height + delta.dy;
    if (widget.preferences.snapToGrid) {
      x = (x / grid).round() * grid.toDouble();
      y = (y / grid).round() * grid.toDouble();
    }
    setState(() {
      _dragPreview = node.copyWith(
        rect: node.rect.copyWith(
          x: (x / canvas.size.width).clamp(0.0, 1.0 - node.rect.width),
          y: (y / canvas.size.height).clamp(0.0, 1.0 - node.rect.height),
        ),
      );
    });
  }

  void _stopDrag({required bool commit}) {
    final node = _dragPreview;
    setState(() {
      _dragSource = null;
      _dragPreview = null;
    });
    if (commit && node != null) widget.onMove(node);
  }

  static const _user = UserSummary(id: 'alice', displayName: 'Alice');
  final _service = ValueNotifier<ServiceSlots>((
    mode: ServiceMode.ready,
    error: null,
  ));
  final _auth = ValueNotifier<AuthPromptSlots>((
    mode: AuthMode.prompting,
    selectedUser: _user,
    prompt: (kind: PromptKind.secret, text: 'Password'),
    error: null,
    promptError: null,
  ));
  final _account = ValueNotifier(
    AccountPickerSlots(users: [_user], selected: _user),
  );
  final _session = ValueNotifier(
    SessionPickerSlots(
      mode: CatalogMode.ready,
      sessions: const [(id: 'wayland:sway', name: 'Sway')],
      selected: (id: 'wayland:sway', name: 'Sway'),
      error: null,
    ),
  );
  final _power = ValueNotifier<PowerSlots>((mode: PowerMode.idle, error: null));
  final _credential = TextEditingController();
  final _focus = FocusNode();
  late final _host = GreeterHost(
    serviceSlots: _service,
    authPromptSlots: _auth,
    accountPickerSlots: _account,
    sessionPickerSlots: _session,
    powerSlots: _power,
    credentialController: _credential,
    credentialFocusNode: _focus,
    onSelectUser: (_) {},
    onSelectSession: (_) {},
    onRequestPowerAction: (_) {},
    onRetry: (_) {},
    onRetrySessionCatalog: () {},
    onRespondToPrompt: () {},
  );

  late GreeterThemeComponents _components;

  @override
  void initState() {
    super.initState();
    _updateComponents();
  }

  @override
  void didUpdateWidget(StudioPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.theme, widget.theme)) {
      _updateComponents();
    }
  }

  void _updateComponents() {
    _components = widget.theme.components(
      GreeterThemeContext(host: _host, tokens: widget.theme.tokens),
    );
  }

  @override
  void dispose() {
    _service.dispose();
    _auth.dispose();
    _account.dispose();
    _session.dispose();
    _power.dispose();
    _credential.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dragged = _dragPreview;
    final document = dragged == null
        ? widget.document
        : widget.document.copyWith(
            nodes: [
              for (final node in widget.document.nodes)
                if (node.id == dragged.id) dragged else node,
            ],
          );
    final size = Size(
      document.canvas.referenceWidth.toDouble(),
      document.canvas.referenceHeight.toDouble(),
    );
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox.fromSize(
          key: _canvas,
          size: size,
          // Material belongs to the theme preview alone; the editor's controls
          // use shadcn. This also provides localization for theme components.
          child: CustomPaint(
            foregroundPainter: widget.preferences.showGrid
                ? _GridPainter(widget.preferences.gridSize)
                : null,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: widget.theme.materialTheme,
              home: MediaQuery(
                data: MediaQueryData(size: size, disableAnimations: true),
                child: Scaffold(
                  body: SceneRuntime(
                    document: document,
                    theme: widget.theme.bundle,
                    backgroundBlurSigma: AlwaysStoppedAnimation(
                      widget.dormant ? 0 : document.background.blurSigma,
                    ),
                    activePredicates: {
                      ScenePredicate.isServiceReady,
                      ScenePredicate.isAuthPrompting,
                      ScenePredicate.hasSelectedUser,
                      ScenePredicate.isSessionReady,
                      if (widget.dormant) ScenePredicate.isDormant,
                    },
                    nodeBuilder: (context, node) => GestureDetector(
                      key: ValueKey('preview-${node.id}'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onSelect(node.id),
                      dragStartBehavior: DragStartBehavior.down,
                      onPanStart: (details) => _startDrag(node.id, details),
                      onPanUpdate: _updateDrag,
                      onPanEnd: (_) => _stopDrag(commit: true),
                      onPanCancel: () => _stopDrag(commit: false),
                      child: DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                          border: node.id == widget.selectedId
                              ? Border.all(
                                  color: const Color(0xffa78bfa),
                                  width: 3,
                                )
                              : null,
                        ),
                        child: ExcludeFocus(
                          child: IgnorePointer(
                            child: _components.build(context, node),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter(this.spacing);

  final int spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x507f7f7f)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) =>
      spacing != oldDelegate.spacing;
}
