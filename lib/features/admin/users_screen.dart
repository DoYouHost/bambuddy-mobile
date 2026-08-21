import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/models/current_user.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../common/dash_sheet.dart';
import '../common/state_views.dart';
import 'user_delete_dialog.dart';
import 'user_form_screen.dart';
import 'user_messages.dart';
import 'users_providers.dart';

/// The accounts on the server (full screen, pushed from the dashboard drawer).
///
/// Read-only: `GET /users/` is gated on `users:read` alone server-side
/// (`backend/app/api/routes/users.py::_user_to_response`), so a household
/// member in a custom group reaches this without the admin role. Creating,
/// editing and deleting an account is admin-only and is not offered here yet.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final async = ref.watch(usersListProvider);
    final canManage = ref.watch(canManageUsersProvider);

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.usersTitle),
        floatingActionButton: canManage
            ? logTag(
                'users.create',
                FloatingActionButton.extended(
                  backgroundColor: t.accentGreen,
                  foregroundColor: const Color(0xFF0A0C08),
                  onPressed: () => openUserCreate(context),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: Text(l10n.usersCreate),
                ),
              )
            : null,
        body: async.when(
          skipLoadingOnReload: true,
          skipLoadingOnRefresh: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => AsyncErrorView(
            message: err is AppApiException
                ? err.localized(l10n)
                : l10n.connectFailed,
            retryLabel: l10n.retry,
            onRetry: () => ref.read(usersListProvider.notifier).refresh(),
          ),
          data: (users) => RefreshIndicator(
            onRefresh: () => ref.read(usersListProvider.notifier).refresh(),
            child: users.isEmpty
                ? EmptyStateView(
                    message: l10n.usersEmpty,
                    icon: Icons.people_outline,
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(12, 8, 12, canManage ? 88 : 24),
                    itemCount: users.length,
                    itemBuilder: (_, i) => _UserCard(user: users[i]),
                  ),
          ),
        ),
      ),
    );
  }
}

/// One account. The signed-in one is marked — with two "kacper"-ish accounts
/// on a household server, which one is yours is not obvious from the name.
class _UserCard extends ConsumerWidget {
  const _UserCard({required this.user});

  final CurrentUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final isSelf = ref.watch(
      currentUserProvider.select((u) => u.valueOrNull?.id == user.id),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: logTag(
          'users.account',
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => showUserDetailSheet(context, user),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: t.cardGradient,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: t.cardBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Avatar(user: user),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                user.username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.titleMd,
                              ),
                            ),
                            if (isSelf) ...[
                              const SizedBox(width: 8),
                              Text(
                                l10n.usersYou,
                                style: t.micro.copyWith(color: t.accentGreenInk),
                              ),
                            ],
                          ],
                        ),
                        if (user.email != null && user.email!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              user.email!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.labelSoft.copyWith(color: t.textSecondary),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (user.isAdmin)
                              DashPill(
                                label: l10n.usersRoleAdmin,
                                accent: t.accentGreen,
                                accentInk: t.accentGreenInk,
                                icon: Icons.shield_outlined,
                              )
                            else
                              DashPill(
                                label: l10n.usersRoleUser,
                                accent: t.accentBlue,
                                icon: Icons.person_outline,
                              ),
                            if (!user.isActive)
                              DashPill(
                                label: l10n.usersInactive,
                                accent: t.danger,
                                icon: Icons.block,
                              ),
                            if (user.authSource != 'local')
                              DashPill(
                                label: user.authSource.toUpperCase(),
                                accent: t.accentOrange,
                                icon: Icons.dns_outlined,
                              ),
                            for (final g in user.groups)
                              DashPill(
                                label: g.name,
                                accent: t.textSecondary,
                                accentInk: t.textSecondary,
                                icon: Icons.group_outlined,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user});

  final CurrentUser user;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final accent = user.isAdmin ? t.accentGreen : t.accentBlue;
    final initial =
        user.username.isEmpty ? '?' : user.username.characters.first.toUpperCase();
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: user.isActive ? 0.16 : 0.06),
        shape: BoxShape.circle,
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Text(
        initial,
        style: t.titleLg.copyWith(color: user.isActive ? accent : t.textTertiary),
      ),
    );
  }
}

/// Opens the per-account detail: what the list has no room for, plus what the
/// account owns (one request, made only when someone opens this).
Future<void> showUserDetailSheet(BuildContext context, CurrentUser user) =>
    dashSheet<void>(
      context,
      builder: (_) => _UserDetailSheet(user: user),
    );

class _UserDetailSheet extends ConsumerWidget {
  const _UserDetailSheet({required this.user});

  final CurrentUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final created = user.createdAt;

    return logTag(
      'sheet.user_detail',
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.username,
                  style: t.display,
                ),
                const SizedBox(height: 16),
                _DetailRow(
                  icon: Icons.alternate_email,
                  label: l10n.usersEmailLabel,
                  value: (user.email?.isNotEmpty ?? false)
                      ? user.email!
                      : l10n.usersEmailNone,
                ),
                _DetailRow(
                  icon: Icons.group_outlined,
                  label: l10n.usersGroupsLabel,
                  value: user.groups.isEmpty
                      ? l10n.usersNoGroups
                      : [for (final g in user.groups) g.name].join(', '),
                ),
                _DetailRow(
                  icon: Icons.key_outlined,
                  label: l10n.usersPermissionsLabel,
                  // An unknown permission set (a server that didn't send the
                  // field) is not "none" — see [CurrentUser.permissionsKnown].
                  value: user.permissionsKnown
                      ? l10n.usersPermissionsCount(user.permissions.length)
                      : l10n.usersPermissionsUnknown,
                ),
                _DetailRow(
                  icon: Icons.dns_outlined,
                  label: l10n.usersAuthSourceLabel,
                  value: user.authSource == 'local'
                      ? l10n.usersAuthSourceLocal
                      : user.authSource.toUpperCase(),
                ),
                if (created != null)
                  _DetailRow(
                    icon: Icons.event_outlined,
                    label: l10n.usersCreatedLabel,
                    value: DateFormat.yMMMd(locale).add_Hm().format(created),
                  ),
                const SizedBox(height: 16),
                Text(
                  l10n.usersOwnedTitle,
                  style: t.bodyBold.copyWith(letterSpacing: 0.3),
                ),
                const SizedBox(height: 8),
                _OwnedCounts(userId: user.id),
                if (ref.watch(canManageUsersProvider)) ...[
                  const SizedBox(height: 20),
                  _SheetActions(user: user),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Edit and delete for one account. Both are admin-only server-side, and the
/// rules about what may not happen (the last admin, your own account) are left
/// to the server — refusing them here as well would mean keeping a copy of a
/// rule that lives elsewhere.
class _SheetActions extends ConsumerWidget {
  const _SheetActions({required this.user});

  final CurrentUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    // Deleting the account you are signed in with is refused server-side
    // (`users.py::delete_user`); bambuddy's own UI leaves the button out rather
    // than offer it and explain afterwards.
    final isSelf = ref.watch(
      currentUserProvider.select((u) => u.valueOrNull?.id == user.id),
    );
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              openUserEdit(context, user);
            },
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(l10n.usersEdit),
          ).tagged('user_detail.edit'),
        ),
        if (!isSelf) ...[
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: t.danger,
                side: BorderSide(color: t.danger.withValues(alpha: 0.5)),
              ),
              onPressed: () => _delete(context, ref),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(l10n.usersDelete),
            ).tagged('user_detail.delete'),
          ),
        ],
      ],
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final sheet = Navigator.of(context);
    final choice = await confirmUserDelete(context, user);
    if (choice == null) return;

    final result = await runUserWrite(
      () => ref
          .read(usersRepositoryProvider)
          .delete(user.id, deleteItems: choice.deleteItems),
      'user_detail.delete',
    );
    await ref.read(usersListProvider.notifier).refresh();
    messenger.showSnackBar(SnackBar(
      content: Text(
        result.ok ? l10n.usersDeleted : userWriteMessage(l10n, result),
      ),
    ));
    // The sheet describes an account that is gone; close it either way — on a
    // refusal the list underneath still shows the account and its reason.
    if (sheet.canPop()) sheet.pop();
  }
}

/// Archives, queue items and library files this account created. Failure is
/// shown in place rather than as an error over the whole sheet — the rest of
/// what is on screen came from the list request and is still good.
class _OwnedCounts extends ConsumerWidget {
  const _OwnedCounts({required this.userId});

  final int userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);

    return ref.watch(userItemsCountProvider(userId)).when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (_, _) => Text(
            l10n.usersOwnedFailed,
            style: t.labelSoft,
          ),
          data: (counts) => Row(
            children: [
              Expanded(
                child: _CountTile(
                  label: l10n.usersOwnedArchives,
                  value: counts.archives,
                  icon: Icons.inventory_2_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CountTile(
                  label: l10n.usersOwnedQueue,
                  value: counts.queueItems,
                  icon: Icons.playlist_play_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CountTile(
                  label: l10n.usersOwnedLibrary,
                  value: counts.libraryFiles,
                  icon: Icons.folder_outlined,
                ),
              ),
            ],
          ),
        );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: t.subCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.subCardBorder),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: t.textSecondary),
          const SizedBox(height: 6),
          Text(
            '$value',
            style: t.monoHeadline,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: t.micro,
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: t.textTertiary),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: t.label.copyWith(color: t.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: t.body,
            ),
          ),
        ],
      ),
    );
  }
}
