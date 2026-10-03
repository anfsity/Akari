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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              error ?? path,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: error == null
                    ? colors.mutedForeground
                    : colors.destructive,
              ),
            ).small(),
          ),
          const Gap(12),
          if (confirmReload) ...[
            const Text('Discard edits and reload?').small(),
            const Gap(8),
            GhostButton(onPressed: onCancelReload, child: const Text('Cancel')),
          ],
          GhostButton(
            onPressed: onReload,
            child: Text(
              confirmReload ? 'Discard and reload' : 'Reload from disk',
            ),
          ),
        ],
      ),
    );
  }
}
