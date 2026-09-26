import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mozais_theme_sdk/mozais_theme_sdk.dart';

class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    required this.account,
    required this.tokens,
    required this.onSelect,
    super.key,
  });

  final AccountPickerSlots account;
  final ThemeTokens tokens;
  final ValueChanged<UserSummary> onSelect;

  @override
  Widget build(BuildContext context) {
    final selected = account.selected;
    final accent = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: 'Choose account',
      child: Center(
        child: AspectRatio(
          aspectRatio: 1,
          child: Material(
            color: tokens.surfaceColor,
            shape: CircleBorder(
              side: BorderSide(color: tokens.surfaceVariantColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: account.canSelect
                  ? () => _showAccountPicker(context, account, tokens, onSelect)
                  : null,
              child: Center(
                child: selected == null
                    ? Icon(Icons.person_outline, size: 40, color: accent)
                    : _AccountAvatarImage(
                        user: selected,
                        accent: accent,
                        fontSize: 48,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _showAccountPicker(
  BuildContext context,
  AccountPickerSlots account,
  ThemeTokens tokens,
  ValueChanged<UserSummary> onSelect,
) {
  unawaited(
    showDialog<void>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return Dialog(
          backgroundColor: tokens.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: tokens.surfaceVariantColor),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260, maxHeight: 320),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(10),
              children: [
                for (final user in account.users)
                  _UserTile(
                    user: user,
                    selected: account.selected?.id == user.id,
                    accent: scheme.primary,
                    tokens: tokens,
                    onTap: () {
                      onSelect(user);
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _AccountAvatarImage extends StatelessWidget {
  const _AccountAvatarImage({
    required this.user,
    required this.accent,
    required this.fontSize,
  });

  final UserSummary user;
  final Color accent;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    if (user.iconPath.isEmpty) {
      return _initial();
    }
    return Image.file(
      File(user.iconPath),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _initial(),
    );
  }

  Widget _initial() {
    return Text(
      user.displayName.characters.first.toUpperCase(),
      style: TextStyle(
        color: accent,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.selected,
    required this.accent,
    required this.tokens,
    required this.onTap,
  });

  final UserSummary user;
  final bool selected;
  final Color accent;
  final ThemeTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? tokens.surfaceVariantColor : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: selected ? accent : tokens.surfaceVariantColor,
                foregroundImage: user.iconPath.isEmpty
                    ? null
                    : FileImage(File(user.iconPath)),
                onForegroundImageError: user.iconPath.isEmpty
                    ? null
                    : (error, stackTrace) {},
                child: Text(
                  user.displayName.characters.first.toUpperCase(),
                  style: TextStyle(
                    color: selected ? scheme.onPrimary : accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  user.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (selected) Icon(Icons.check, size: 18, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class AccountName extends StatelessWidget {
  const AccountName({required this.account, super.key});

  final AccountPickerSlots account;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        account.selected?.displayName ?? 'Choose account',
        maxLines: 1,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
