import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/models/group_summary.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../common/state_views.dart';
import 'group_form_screen.dart';
import 'groups_providers.dart';

/// The groups on the server (full screen, pushed from the dashboard drawer).
///
/// A group is a named permission set plus the accounts that hold it — which is
/// how "print, but don't delete archives" is expressed. Read-only here:
/// `groups:read` opens the list, and tapping one leads to its members.
class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final async = ref.watch(groupsListProvider);
    final canManage = ref.watch(canManageGroupsProvider);

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.groupsTitle),
        floatingActionButton: canManage
            ? logTag(
                'groups.create',
                FloatingActionButton.extended(
                  backgroundColor: t.accentGreen,
                  foregroundColor: const Color(0xFF0A0C08),
                  onPressed: () => openGroupCreate(context),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.groupsCreate),
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
            onRetry: () => ref.read(groupsListProvider.notifier).refresh(),
          ),
          data: (groups) => RefreshIndicator(
            onRefresh: () => ref.read(groupsListProvider.notifier).refresh(),
            child: groups.isEmpty
                ? EmptyStateView(
                    message: l10n.groupsEmpty,
                    icon: Icons.group_outlined,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: groups.length,
                    itemBuilder: (_, i) => GroupCard(
                      group: groups[i],
                      onTap: () => context.push('/admin/groups/${groups[i].id}'),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// One group: name, whether it ships with the server, what it is for, and how
/// much it holds — the same four things bambuddy's own list shows.
class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.group, required this.onTap});

  final GroupSummary group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final accent = group.isSystem ? t.accentOrange : t.accentBlue;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: logTag(
          'groups.group',
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
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
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: accent.withValues(alpha: 0.4)),
                    ),
                    child: Icon(Icons.group_outlined, size: 20, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                group.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.titleMd,
                              ),
                            ),
                            if (group.isSystem) ...[
                              const SizedBox(width: 8),
                              Text(
                                l10n.usersGroupSystem,
                                style: t.micro.copyWith(color: t.accentOrange),
                              ),
                            ],
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            (group.description?.isNotEmpty ?? false)
                                ? group.description!
                                : l10n.groupsNoDescription,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.labelSoft.copyWith(color: t.textSecondary),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${l10n.groupsMemberCount(group.userCount)}'
                          ' · ${l10n.groupsPermissionCount(group.permissions.length)}',
                          style: t.monoLabel,
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
