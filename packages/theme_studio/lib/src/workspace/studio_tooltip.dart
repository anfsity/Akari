import 'dart:async';

import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Tooltips share a surface and spacing, and never intercept editor clicks.
class StudioTooltip extends StatefulWidget {
  const StudioTooltip({
    required this.tooltip,
    required this.child,
    this.above = false,
    this.enabled = true,
    super.key,
  });

  final WidgetBuilder tooltip;
  final Widget child;
  final bool above;
  final bool enabled;

  @override
  State<StudioTooltip> createState() => _StudioTooltipState();
}

class _StudioTooltipState extends State<StudioTooltip> {
  final _controller = OverlayController();
  Timer? _hoverTimer;

  void _startHover() {
    _hoverTimer?.cancel();
    if (!widget.enabled) return;
    _hoverTimer = Timer(const Duration(milliseconds: 500), _showTooltip);
  }

  void _cancelHover() {
    _hoverTimer?.cancel();
    _controller.close();
  }

  void _showTooltip() {
    if (!mounted || !widget.enabled) return;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    _controller.show<void>(
      context,
      TooltipConfiguration(
        alignment: widget.above ? Alignment.bottomCenter : Alignment.topCenter,
        anchorAlignment: widget.above
            ? Alignment.topCenter
            : Alignment.bottomCenter,
        showDuration: reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 120),
        dismissDuration: reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 100),
      ),
      adaptive: false,
      builder: (context) => IgnorePointer(
        child: TooltipContainer(child: widget.tooltip(context)),
      ),
    );
  }

  @override
  void didUpdateWidget(StudioTooltip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _hoverTimer?.cancel();
      _controller.closeLater();
    }
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => _startHover(),
    onExit: (_) => _cancelHover(),
    child: Listener(onPointerDown: (_) => _cancelHover(), child: widget.child),
  );
}
