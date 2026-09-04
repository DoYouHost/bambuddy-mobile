import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/models/current_user.dart';
import '../../core/models/group_summary.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/confirm_dialog.dart';
import '../common/dash_async.dart';
import '../common/dash_sheet.dart';
import '../common/dash_snack.dart';
import 'group_form_screen.dart';
import 'groups_providers.dart';
import 'user_messages.dart';
import 'users_providers.dart';

/// One group: what it is, and who is in it.
///
/// Membership is editable from both ends — here and in the account form —
/// because "put Zosia in Operators" and "who is in Operators?" are different
/// questions. The server keeps one state either way
/// (`backend/app/api/routes/groups.py::delete_group`).
class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final int groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final async = ref.watch(groupDetailProvider(groupId));
    final canManage = ref.watch(canManageGroupsProvider);

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(
          context,
          title: async.valueOrNull?.name ?? l10n.groupsTitle,
          actions: [
            if (canManage && async.hasValue)
              _GroupMenu(group: async.value!),
          ],
        ),
        floatingActionButton: canManage && async.hasValue
            ? logTag(
                'group_detail.add_member',
                FloatingActionButton.extended(
                  backgroundColor: t.accentGreen,
                  foregroundColor: const Color(0xFF0A0C08),
                  onPressed: () => _addMember(context, ref, async.value!),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: Text(l10n.groupsAddMember),
                ),
              )
            : null,
        body: dashAsync(
          context,
          async,
          onRetry: () => ref.read(groupDetailProvider(groupId).notifier).refresh(),
          data: (group) => RefreshIndicator(
            onRefresh: () =>
                ref.read(groupDetailProvider(groupId).notifier).refresh(),
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 8, 16, canManage ? 88 : 24),
              children: [
                _GroupHeader(group: group),
                const SizedBox(height: 20),
                Text(
                  l10n.groupsMembersHeader,
                  style: t.bodyBold.copyWith(letterSpacing: 0.3),
                ),
                const SizedBox(height: 8),
                if (group.members.isEmpty)
                  Text(
                    l10n.groupsNoMembers,
                    style: t.bodyPlain.copyWith(color: t.textTertiary),
                  )
                else
                  for (final member in group.members)
                    _MemberRow(
                      member: member,
                      onRemove: canManage
                          ? () => _removeMember(context, ref, group, member)
                          : null,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addMember(
    BuildContext context,
    WidgetRef ref,
    GroupDetail group,
  ) async {
    final picked = await pickAccountForGroup(context, group);
    if (picked == null) return;
    if (!context.mounted) return;
    await _mutate(
      context,
      ref,
      () => ref.read(groupsRepositoryProvider).addMember(group.id, picked.id),
      'group_detail.add_member',
    );
  }

  Future<void> _removeMember(
    BuildContext context,
    WidgetRef ref,
    GroupDetail group,
    GroupMember member,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await confirmDialog(
      context,
      title: l10n.groupsRemoveMemberQuestion(member.username, group.name),
      message: l10n.groupsRemoveMemberBody,
      confirmLabel: l10n.groupsRemoveMember,
      id: 'group_member_remove',
    );
    if (!confirmed || !context.mounted) return;
    await _mutate(
      context,
      ref,
      () =>
          ref.read(groupsRepositoryProvider).removeMember(group.id, member.id),
      'group_detail.remove_member',
    );
  }

  /// Runs a membership change and refreshes everything that shows it: this
  /// group, the group list (`user_count`) and the account list (group chips).
  Future<void> _mutate(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
    String logId,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await runUserWrite(action, logId);
    await ref.read(groupDetailProvider(groupId).notifier).refresh();
    ref.invalidate(groupsListProvider);
    ref.invalidate(usersListProvider);
    // Membership is where permissions come from — if it was your own, what the
    // app offers you changes with it.
    await ref.read(currentUserProvider.notifier).refresh();
    if (!result.ok) {
      messenger.snack(userWriteMessage(l10n, result));
    }
  }
}

/// Edit and delete for the group itself. Deleting is offered only for a group
/// the server would actually delete: a system group is refused
/// (`groups.py::delete_group`), so the entry is left out rather than shown and
/// refused.
class _GroupMenu extends ConsumerWidget {
  const _GroupMenu({required this.group});

  final GroupDetail group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: t.textSecondary),
      onSelected: (value) {
        if (value == 'edit') openGroupEdit(context, group);
        if (value == 'delete') _delete(context, ref);
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'edit',
          child: logTag('group_detail.edit', Text(l10n.usersEdit)),
        ),
        if (!group.isSystem)
          PopupMenuItem(
            value: 'delete',
            child: logTag(
              'group_detail.delete',
              Text(l10n.groupsDelete, style: TextStyle(color: t.danger)),
            ),
          ),
      ],
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await confirmDialog(
      context,
      title: l10n.groupsDeleteQuestion(group.name),
      // Members survive a deleted group — they only lose what it granted.
      message: group.members.isEmpty
          ? l10n.groupsDeleteBody
          : l10n.groupsDeleteBodyWithMembers(group.members.length),
      confirmLabel: l10n.groupsDelete,
      id: 'group_delete',
    );
    if (!confirmed) return;

    final result = await runUserWrite(
      () => ref.read(groupsRepositoryProvider).delete(group.id),
      'group_detail.delete',
    );
    ref.invalidate(groupsListProvider);
    ref.invalidate(usersListProvider);
    await ref.read(currentUserProvider.notifier).refresh();
    messenger.snack(result.ok ? l10n.groupsDeleted : userWriteMessage(l10n, result));
    if (result.ok) navigator.pop();
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final GroupDetail group;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: t.cardGradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  group.name,
                  style: t.titleLg,
                ),
              ),
              if (group.isSystem)
                DashPill(
                  label: l10n.groupsSystemPill,
                  accent: t.accentOrange,
                  accentInk: t.accentOrangeInk,
                  icon: Icons.lock_outline,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            (group.description?.isNotEmpty ?? false)
                ? group.description!
                : l10n.groupsNoDescription,
            style: t.bodyPlain,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.groupsPermissionCount(group.permissions.length),
            style: t.monoLabel,
          ),
          if (group.isSystem) ...[
            const SizedBox(height: 8),
            // The server refuses to rename a system group or to touch what it
            // grants (`groups.py::update_group`, `:200`); only its membership
            // moves.
            Text(
              l10n.groupsSystemNote,
              style: t.labelSoft,
            ),
          ],
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, this.onRemove});

  final GroupMember member;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: t.subCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.subCardBorder),
        ),
        child: Row(
          children: [
            Icon(
              Icons.person_outline,
              size: 18,
              color: member.isActive ? t.textSecondary : t.textTertiary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                member.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodyStrong.copyWith(color: member.isActive ? t.textPrimary : t.textTertiary),
              ),
            ),
            if (!member.isActive)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  l10n.usersInactive,
                  style: t.micro.copyWith(color: t.danger),
                ),
              ),
            if (onRemove != null)
              IconButton(
                icon: Icon(Icons.person_remove_outlined,
                    size: 18, color: t.danger),
                tooltip: l10n.groupsRemoveMember,
                onPressed: onRemove,
              ).tagged('group_detail.remove_member'),
          ],
        ),
      ),
    );
  }
}

/// Picks an account that is not in [group] yet. Returns null when the sheet is
/// dismissed.
Future<CurrentUser?> pickAccountForGroup(
  BuildContext context,
  GroupDetail group,
) =>
    dashSheet<CurrentUser>(
      context,
      builder: (_) => _AccountPickerSheet(group: group),
    );

class _AccountPickerSheet extends ConsumerWidget {
  const _AccountPickerSheet({required this.group});

  final GroupDetail group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final already = {for (final m in group.members) m.id};
    final async = ref.watch(usersListProvider);

    return logTag(
      'sheet.group_add_member',
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.groupsAddMemberTitle(group.name),
                style: t.titleMd,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: dashAsyncStrip(
                  context,
                  async,
                  padding: const EdgeInsets.all(24),
                  data: (users) {
                    final candidates = [
                      for (final u in users)
                        if (!already.contains(u.id)) u,
                    ];
                    if (candidates.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l10n.groupsEveryoneIsIn,
                          style: TextStyle(
                            fontFamily: DashTokens.fontUi,
                            color: t.textSecondary,
                          ),
                        ),
                      );
                    }
                    return ListView(
                      shrinkWrap: true,
                      children: [
                        for (final u in candidates)
                          ListTile(
                            leading: Icon(Icons.person_outline,
                                color: t.textSecondary),
                            title: Text(u.username),
                            subtitle: u.groups.isEmpty
                                ? null
                                : Text([for (final g in u.groups) g.name]
                                    .join(', ')),
                            onTap: () => Navigator.of(context).pop(u),
                          ).tagged('group_add_member.account'),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
