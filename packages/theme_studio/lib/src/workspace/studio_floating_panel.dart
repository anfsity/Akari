import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../model/studio_workspace_layout.dart';
import '../ui/studio_tooltip.dart';
import 'studio_workspace_dock.dart';

class WorkspaceFloatingPanel extends StatefulWidget {
  const WorkspaceFloatingPanel({
    required this.title,
    required this.initialBounds,
    required this.onChanged,
    required this.onDockTo,
    required this.onDock,
    required this.child,
    super.key,
  });

  final String title;
  final Rect initialBounds;
  final ValueChanged<Rect> onChanged;
  final ValueChanged<StudioDock> onDockTo;
  final VoidCallback onDock;
  final Widget child;

  @override
  State<WorkspaceFloatingPanel> createState() => _WorkspaceFloatingPanelState();
}

class _WorkspaceFloatingPanelState extends State<WorkspaceFloatingPanel> {
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
                  _FloatingPanelTitleBar(
                    title: widget.title,
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
                    onPanEnd: (_) {
                      widget.onChanged(_offset & Size(width, height));
                      if (_offset.dx <= 8) widget.onDockTo(StudioDock.left);
                      if (_offset.dx + width >= constraints.maxWidth - 8) {
                        widget.onDockTo(StudioDock.right);
                      }
                    },
                    onDockTo: widget.onDockTo,
                    onDock: widget.onDock,
                  ),
                  const Divider(),
                  Expanded(child: widget.child),
                  _FloatingPanelResizeGrip(
                    title: widget.title,
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
                    onPanEnd: (_) => widget.onChanged(offset & _size),
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

class _FloatingPanelTitleBar extends StatelessWidget {
  const _FloatingPanelTitleBar({
    required this.title,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onDockTo,
    required this.onDock,
  });

  final String title;
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;
  final ValueChanged<StudioDock> onDockTo;
  final VoidCallback onDock;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.move,
    child: GestureDetector(
      key: ValueKey('float-drag-$title'),
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onPanStart: onPanStart,
      onPanUpdate: onPanUpdate,
      onPanEnd: onPanEnd,
      child: SizedBox(
        height: 42,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Icon(
                LucideIcons.gripVertical,
                size: 14,
                color: Theme.of(context).colorScheme.mutedForeground,
              ),
              const Gap(6),
              Expanded(
                child: Text(getWorkspacePanelLabel(title)).small().semiBold(),
              ),
              StudioTooltip(
                tooltip: (_) => const Text('Dock left'),
                child: GhostButton(
                  key: ValueKey('dock-left-$title'),
                  onPressed: () => onDockTo(StudioDock.left),
                  density: ButtonDensity.icon,
                  child: const Icon(LucideIcons.panelLeft, size: 14),
                ),
              ),
              StudioTooltip(
                tooltip: (_) => const Text('Dock right'),
                child: GhostButton(
                  key: ValueKey('dock-right-$title'),
                  onPressed: () => onDockTo(StudioDock.right),
                  density: ButtonDensity.icon,
                  child: const Icon(LucideIcons.panelRight, size: 14),
                ),
              ),
              const Gap(2),
              OutlineButton(
                key: ValueKey('dock-$title'),
                density: ButtonDensity.dense,
                onPressed: onDock,
                child: const Text('Dock').xSmall(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _FloatingPanelResizeGrip extends StatelessWidget {
  const _FloatingPanelResizeGrip({
    required this.title,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });

  final String title;
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: MouseRegion(
      cursor: SystemMouseCursors.resizeUpLeftDownRight,
      child: GestureDetector(
        key: ValueKey('float-resize-$title'),
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: onPanStart,
        onPanUpdate: onPanUpdate,
        onPanEnd: onPanEnd,
        child: const SizedBox(
          width: 24,
          height: 16,
          child: Icon(LucideIcons.grip, size: 12),
        ),
      ),
    ),
  );
}
