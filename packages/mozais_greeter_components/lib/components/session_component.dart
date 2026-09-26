import 'package:flutter/material.dart';
import 'package:mozais_theme_sdk/mozais_theme_sdk.dart';

class SessionPicker extends StatelessWidget {
  const SessionPicker({
    required this.session,
    required this.onSelect,
    required this.onRetry,
    super.key,
  });

  final SessionPickerSlots session;
  final ValueChanged<SessionSummary> onSelect;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SizedBox(
        height: 48,
        width: double.infinity,
        child: switch (session.mode) {
          CatalogMode.loading => const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          CatalogMode.failed => Center(
            child: TextButton(
              onPressed: onRetry,
              child: Text(session.error?.message ?? 'Retry sessions'),
            ),
          ),
          CatalogMode.empty when session.sessions.isEmpty => Center(
            child: Text(
              'No desktop sessions available.',
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7)),
            ),
          ),
          CatalogMode.ready || CatalogMode.empty => _SessionMenu(
            session: session,
            onSelect: onSelect,
          ),
        },
      ),
    );
  }
}

class _SessionMenu extends StatelessWidget {
  const _SessionMenu({required this.session, required this.onSelect});

  final SessionPickerSlots session;
  final ValueChanged<SessionSummary> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final menuItems = [
      for (final item in session.sessions)
        PopupMenuItem<SessionSummary>(
          value: item,
          onTap: () => onSelect(item),
          child: Row(
            children: [
              Icon(
                session.selected?.id == item.id
                    ? Icons.check_circle
                    : Icons.desktop_windows_outlined,
                size: 18,
                color: session.selected?.id == item.id
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Text(item.name),
            ],
          ),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => PopupMenuButton<SessionSummary>(
        tooltip: 'Choose a session',
        position: PopupMenuPosition.under,
        popUpAnimationStyle: const AnimationStyle(
          duration: Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        constraints: BoxConstraints(minWidth: constraints.maxWidth),
        itemBuilder: (context) => menuItems,
        child: _PillSurface(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.desktop_windows_outlined,
                size: 16,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  session.selected?.name ?? 'Choose session',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (session.sessions.length > 1)
                Icon(Icons.arrow_drop_down, size: 18, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillSurface extends StatelessWidget {
  const _PillSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Ink(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Center(child: child),
      ),
    );
  }
}
