import 'package:flutter/material.dart';
import 'package:greeter_components/greeter_components.dart';
import 'package:theme_sdk/theme_sdk.dart';

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
                  ),
                ),
              ),
            ),
          ),
      ],
      child: Center(
        child: AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).inputDecorationTheme.fillColor,
              border: Border.all(color: accent.withValues(alpha: 0.5)),
            ),
            child: ClipOval(
              child: account.selected == null
                  ? Icon(Icons.person_outline, color: accent, size: 24)
                  : Center(
                      child: AccountPortrait(
                        user: account.selected!,
                        accent: accent,
                        fontSize: 24,
                      ),
                    ),
            ),
          ),
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
    CatalogMode.ready || CatalogMode.empty => LayoutBuilder(
      builder: (context, constraints) => _TerraceMenu<SessionSummary>(
        tooltip: 'Choose a session',
        minWidth: constraints.maxWidth,
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
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).inputDecorationTheme.fillColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(
                  Icons.desktop_windows_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    session.selected?.name ?? 'Choose session',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (session.sessions.length > 1)
                  const Icon(Icons.expand_more, size: 18),
              ],
            ),
          ),
        ),
      ),
    ),
  };
}

class _TerraceMenu<T> extends StatelessWidget {
  const _TerraceMenu({
    required this.tooltip,
    required this.entries,
    required this.child,
    this.enabled = true,
    this.minWidth = 240,
  });

  final String tooltip;
  final List<PopupMenuEntry<T>> entries;
  final Widget child;
  final bool enabled;
  final double minWidth;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
    tooltip: tooltip,
    enabled: enabled,
    position: PopupMenuPosition.under,
    offset: const Offset(0, 8),
    constraints: BoxConstraints(minWidth: minWidth, maxWidth: minWidth),
    menuPadding: const EdgeInsets.all(4),
    popUpAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: Duration(milliseconds: 140),
            reverseDuration: Duration(milliseconds: 100),
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
    itemBuilder: (context) => entries,
    child: child,
  );
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
