import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/models/current_user.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import 'users_providers.dart';

/// Asks whether to delete [user], and what becomes of what they created.
///
/// Not [confirmDialog]: this is not a yes/no. The server takes
/// `delete_items=true|false` and does one of two irreversible things with the
/// account's archives, queue items and library files — delete them too, or
/// leave them in place with no owner
/// (`backend/app/api/routes/users.py::delete_user`). Picking one silently for
/// the user is exactly what should not happen here.
///
/// Returns the choice to carry into the request, or null when the user backed
/// out.
Future<({bool deleteItems})?> confirmUserDelete(
  BuildContext context,
  CurrentUser user,
) =>
    showDialog<({bool deleteItems})>(
      context: context,
      builder: (_) => _UserDeleteDialog(user: user),
    );

class _UserDeleteDialog extends ConsumerStatefulWidget {
  const _UserDeleteDialog({required this.user});

  final CurrentUser user;

  @override
  ConsumerState<_UserDeleteDialog> createState() => _UserDeleteDialogState();
}

class _UserDeleteDialogState extends ConsumerState<_UserDeleteDialog> {
  /// The server's own default, and the safer one: nothing else is destroyed.
  bool _deleteItems = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final counts = ref.watch(userItemsCountProvider(widget.user.id)).valueOrNull;
    final total = counts?.total ?? 0;

    return AlertDialog(
      title: Text(l10n.usersDeleteTitle(widget.user.username)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.usersDeleteBody),
          if (total > 0) ...[
            const SizedBox(height: 16),
            Text(
              l10n.usersDeleteOwnsCount(total),
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              value: _deleteItems,
              onChanged: (v) => setState(() => _deleteItems = v),
              contentPadding: EdgeInsets.zero,
              title: Text(
                l10n.usersDeleteItemsToo,
                style: TextStyle(
                  fontFamily: DashTokens.fontUi,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: t.textPrimary,
                ),
              ),
              subtitle: Text(
                _deleteItems
                    ? l10n.usersDeleteItemsTooHint
                    : l10n.usersDeleteItemsKeepHint,
                style: TextStyle(
                  fontFamily: DashTokens.fontUi,
                  fontSize: 12,
                  color: t.textSecondary,
                ),
              ),
            ).tagged('user_delete.items'),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ).tagged('user_delete.cancel'),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: t.danger,
            foregroundColor: Colors.white,
          ),
          onPressed: () =>
              Navigator.of(context).pop((deleteItems: _deleteItems)),
          child: Text(l10n.usersDeleteConfirm),
        ).tagged('user_delete.confirm'),
      ],
    );
  }
}
