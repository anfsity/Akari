import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:greeter_components/greeter_components.dart';
import 'package:theme_sdk/theme_sdk.dart';

import 'terrace_visuals.dart';

/// Account and desktop choices use one anchored surface and selection treatment.
/// Popup routes retain keyboard ownership, so Escape closes a choice without
/// sleeping the greeter or sending a credential through its early key handler.
class TerraceAccountPicker extends StatelessWidget {
  const TerraceAccountPicker({
    required this.account,
    required this.onSelect,
    super.key,
  });

  final AccountPickerSlots account;
  final ValueChanged<UserSummary> onSelect;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return _TerraceMenu<UserSummary>(
      tooltip: 'Choose account',
      enabled: account.canSelect,
      entries: [
        for (final user in account.users)
          PopupMenuItem<UserSummary>(
            value: user,
            onTap: () => onSelect(user),
            padding: EdgeInsets.zero,
            child: _ChoiceRow(
              label: user.displayName,
              selected: account.selected?.id == user.id,
              leading: ClipOval(
                child: Center(
                  child: AccountPortrait(
                    user: user,
                    accent: accent,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
      ],
      builder: (open) => Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 48,
              child: ClipOval(
                child: account.selected == null
                    ? Icon(Icons.person_outline, color: accent, size: 24)
                    : Center(
                        child: AccountPortrait(
                          user: account.selected!,
                          accent: accent,
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Flexible(
              child: TerraceChoiceLabel(
                id: account.selected?.id,
                label: account.selected?.displayName ?? 'Choose account',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            if (account.canSelect) ...[
              const SizedBox(width: 8),
              _TerraceChoiceArrow(open: open),
            ],
          ],
        ),
      ),
    );
  }
}

class TerraceSessionPicker extends StatelessWidget {
  const TerraceSessionPicker({
    required this.session,
    required this.onSelect,
    required this.onRetry,
    super.key,
  });

  final SessionPickerSlots session;
  final ValueChanged<SessionSummary> onSelect;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => switch (session.mode) {
    CatalogMode.loading => const Center(
      child: SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
    CatalogMode.failed => TextButton(
      onPressed: onRetry,
      child: Text(session.error?.message ?? 'Retry sessions'),
    ),
    CatalogMode.empty when session.sessions.isEmpty => const Align(
      alignment: Alignment.centerLeft,
      child: Text('No desktop sessions available.'),
    ),
    CatalogMode.ready || CatalogMode.empty => _TerraceMenu<SessionSummary>(
      tooltip: 'Choose a session',
      entries: [
        for (final item in session.sessions)
          PopupMenuItem<SessionSummary>(
            value: item,
            onTap: () => onSelect(item),
            padding: EdgeInsets.zero,
            child: _ChoiceRow(
              label: item.name,
              selected: session.selected?.id == item.id,
              leading: const Icon(Icons.desktop_windows_outlined, size: 18),
            ),
          ),
      ],
      builder: (open) => Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.desktop_windows_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: TerraceChoiceLabel(
                id: session.selected?.id,
                label: session.selected?.name ?? 'Choose session',
                style: const TextStyle(fontSize: 16),
              ),
            ),
            if (session.sessions.length > 1) ...[
              const SizedBox(width: 8),
              _TerraceChoiceArrow(open: open),
            ],
          ],
        ),
      ),
    ),
  };
}

class _TerraceChoiceArrow extends StatelessWidget {
  const _TerraceChoiceArrow({required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) => AnimatedRotation(
    turns: open ? 0.5 : 0,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220),
    curve: Curves.easeOutCubic,
    child: Icon(
      Icons.expand_more,
      size: 18,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _TerraceMenu<T> extends StatefulWidget {
  const _TerraceMenu({
    required this.tooltip,
    required this.entries,
    required this.builder,
    this.enabled = true,
  });

  final String tooltip;
  final List<PopupMenuEntry<T>> entries;
  final Widget Function(bool open) builder;
  final bool enabled;

  @override
  State<_TerraceMenu<T>> createState() => _TerraceMenuState<T>();
}

class _TerraceMenuState<T> extends State<_TerraceMenu<T>> {
  bool _open = false;

  Future<void> _openMenu() async {
    final navigator = Navigator.of(context);
    final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
    final button = context.findRenderObject()! as RenderBox;
    final anchor = MatrixUtils.transformRect(
      button.getTransformTo(overlay),
      Offset.zero & button.size,
    );
    final scale = anchor.width / button.size.width;
    setState(() => _open = true);
    await navigator.push(
      _TerraceChoiceRoute<T>(
        anchor: anchor,
        width: 240 * scale,
        scale: scale,
        entries: widget.entries,
        label: widget.tooltip,
        barrierLabel: MaterialLocalizations.of(context)
            .modalBarrierDismissLabel,
        themes: InheritedTheme.capture(from: context, to: navigator.context),
        reducedMotion: MediaQuery.disableAnimationsOf(context),
      ),
    );
    if (mounted) {
      setState(() => _open = false);
    }
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    child: InkWell(
      onTap: widget.enabled && !_open ? _openMenu : null,
      borderRadius: BorderRadius.circular(12),
      child: widget.builder(_open),
    ),
  );
}

/// The surface and rows animate in paint coordinates. A fixed-width scrollable
/// layout avoids intrinsic measurement and relayout on every expansion frame.
/// Keep a popup route so focus, Escape, outside clicks and credential dispatch
/// have the same ownership as the standard controls.
class _TerraceChoiceRoute<T> extends PopupRoute<T> {
  _TerraceChoiceRoute({
    required this.anchor,
    required this.width,
    required this.scale,
    required this.entries,
    required this.label,
    required this.barrierLabel,
    required this.themes,
    required this.reducedMotion,
  }) : super(
         requestFocus: true,
         traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
       );

  final Rect anchor;
  final double width;
  final double scale;
  final List<PopupMenuEntry<T>> entries;
  final String label;
  final CapturedThemes themes;
  final bool reducedMotion;

  @override
  final String barrierLabel;
  @override
  bool get barrierDismissible => true;
  @override
  Color? get barrierColor => null;
  @override
  Duration get transitionDuration =>
      reducedMotion ? Duration.zero : const Duration(milliseconds: 260);
  @override
  Duration get reverseTransitionDuration =>
      reducedMotion ? Duration.zero : const Duration(milliseconds: 160);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => themes.wrap(
    Builder(
      builder: (context) {
        final popup = PopupMenuTheme.of(context);
        return CustomSingleChildLayout(
          delegate: _TerraceMenuLayout(
            anchor,
            width,
            MediaQuery.paddingOf(context),
          ),
          // The overlay sits outside the scaled scene. Convert its limits to
          // authored units so popup rows share the selector's visual scale.
          child: LayoutBuilder(
            builder: (context, constraints) => FittedBox(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: constraints.minWidth / scale,
                  maxWidth: constraints.maxWidth / scale,
                  maxHeight: constraints.maxHeight / scale,
                ),
                child: Shortcuts(
                  shortcuts: const {
                    SingleActivator(LogicalKeyboardKey.arrowDown):
                        NextFocusIntent(),
                    SingleActivator(LogicalKeyboardKey.arrowUp):
                        PreviousFocusIntent(),
                  },
                  child: FadeTransition(
                    opacity: animation.drive(
                      CurveTween(
                        curve: const Interval(
                          0,
                          0.55,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                    ),
                    child: ScaleTransition(
                      alignment: Alignment.topLeft,
                      scale: Tween<double>(begin: 0.94, end: 1).animate(
                        animation.drive(CurveTween(curve: Curves.easeOutBack)),
                      ),
                      child: Material(
                        color: popup.color,
                        shape: popup.shape,
                        clipBehavior: Clip.antiAlias,
                        textStyle: popup.textStyle,
                        child: Semantics(
                          role: SemanticsRole.menu,
                          scopesRoute: true,
                          namesRoute: true,
                          label: label,
                          explicitChildNodes: true,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (
                                  var index = 0;
                                  index < entries.length;
                                  index++
                                )
                                  _createEntryTransition(animation, index),
                              ],
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
      },
    ),
  );

  Widget _createEntryTransition(Animation<double> animation, int index) {
    final progress = animation.drive(
      CurveTween(
        curve: Interval(
          math.min(index * 0.06, 0.3),
          1,
          curve: Curves.easeOutCubic,
        ),
      ),
    );
    return FadeTransition(
      opacity: progress,
      alwaysIncludeSemantics: true,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.22),
          end: Offset.zero,
        ).animate(progress),
        child: RepaintBoundary(child: entries[index]),
      ),
    );
  }
}

class _TerraceMenuLayout extends SingleChildLayoutDelegate {
  _TerraceMenuLayout(this.anchor, this.width, this.padding);

  final Rect anchor;
  final double width;
  final EdgeInsets padding;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final available = constraints.deflate(padding + const EdgeInsets.all(8));
    return BoxConstraints(
      minWidth: math.min(width, available.maxWidth),
      maxWidth: math.min(width, available.maxWidth),
      maxHeight: available.maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final bounds = padding.deflateRect(Offset.zero & size).deflate(8);
    final below = anchor.bottom + 8;
    final y = below + childSize.height <= bounds.bottom
        ? below
        : anchor.top - childSize.height - 8;
    return Offset(
      anchor.left.clamp(bounds.left, bounds.right - childSize.width),
      y.clamp(bounds.top, bounds.bottom - childSize.height),
    );
  }

  @override
  bool shouldRelayout(_TerraceMenuLayout oldDelegate) =>
      anchor != oldDelegate.anchor ||
      width != oldDelegate.width ||
      padding != oldDelegate.padding;
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.selected,
    required this.leading,
  });

  final String label;
  final bool selected;
  final Widget leading;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? accent.withValues(alpha: 0.1) : Colors.transparent,
        border: Border(
          left: BorderSide(
            color: selected ? accent : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            IconTheme.merge(
              data: IconThemeData(color: accent),
              child: SizedBox.square(dimension: 28, child: leading),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
            if (selected) Icon(Icons.check, size: 16, color: accent),
          ],
        ),
      ),
    );
  }
}
