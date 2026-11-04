import 'package:shadcn_flutter/shadcn_flutter.dart';

class StudioStatusBar extends StatelessWidget {
  const StudioStatusBar({
    required this.path,
    required this.error,
    required this.confirmReload,
    required this.onCancelReload,
    required this.onReload,
    super.key,
  });

  final String path;
  final String? error;
  final bool confirmReload;
  final VoidCallback onCancelReload;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasError = error != null;
    final themesIndex = path.indexOf('/themes/');
    final displayPath = themesIndex >= 0
        ? path.substring(themesIndex + 1)
        : path;
    return ColoredBox(
      color: hasError
          ? colors.destructive.withValues(alpha: 0.08)
          : colors.background,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Row(
            children: [
              Icon(
                hasError ? LucideIcons.circleAlert : LucideIcons.fileJson,
                size: 13,
                color: hasError ? colors.destructive : colors.mutedForeground,
              ),
              const Gap(6),
              Expanded(
                child: Tooltip(
                  tooltip: (_) => Text(error ?? path),
                  child: Text(
                    error ?? displayPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasError
                          ? colors.destructive
                          : colors.mutedForeground,
                    ),
                  ).xSmall(),
                ),
              ),
              const Gap(12),
              if (confirmReload) ...[
                const Text('Discard edits and reload?').xSmall(),
                const Gap(6),
                GhostButton(
                  density: ButtonDensity.dense,
                  onPressed: onCancelReload,
                  child: const Text('Cancel').xSmall(),
                ),
              ],
              GhostButton(
                density: ButtonDensity.dense,
                onPressed: onReload,
                child: Text(
                  confirmReload ? 'Discard and reload' : 'Reload from disk',
                ).xSmall(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
