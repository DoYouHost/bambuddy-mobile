import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import 'api_keys_providers.dart';
import 'groups_providers.dart';
import 'users_providers.dart';

/// Administration — the three server-side things this app can manage, in one
/// place. Each entry is gated on its own permission, so a household account
/// granted only `users:read` sees the accounts and nothing else.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final user = ref.watch(currentUserProvider).valueOrNull;

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.adminTitle),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            if (user != null) _SignedInAs(username: user.username),
            if (ref.watch(canReadUsersProvider))
              _AdminEntry(
                icon: Icons.people_outline,
                title: l10n.usersTitle,
                subtitle: l10n.adminUsersSubtitle,
                onTap: () => context.push('/admin/users'),
                id: 'admin.users',
              ),
            if (ref.watch(canReadGroupsProvider))
              _AdminEntry(
                icon: Icons.group_outlined,
                title: l10n.groupsTitle,
                subtitle: l10n.adminGroupsSubtitle,
                onTap: () => context.push('/admin/groups'),
                id: 'admin.groups',
              ),
            if (ref.watch(canReadApiKeysProvider))
              _AdminEntry(
                icon: Icons.key_outlined,
                title: l10n.apiKeysTitle,
                subtitle: l10n.adminApiKeysSubtitle,
                onTap: () => context.push('/admin/api-keys'),
                id: 'admin.api_keys',
              ),
          ],
        ),
      ),
    );
  }
}

/// Whose rights the screens below are being used with. An admin managing a
/// household server usually has more than one account on it.
class _SignedInAs extends StatelessWidget {
  const _SignedInAs({required this.username});

  final String username;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      child: Row(
        children: [
          Icon(Icons.badge_outlined, size: 15, color: t.textTertiary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.adminSignedInAs(username),
              style: t.labelSoft,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminEntry extends StatelessWidget {
  const _AdminEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.id,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Name for the diagnostic log — the visible label is localized and is not
  /// recorded.
  final String id;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: logTag(
          id,
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: t.cardGradient,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: t.cardBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.accentGreen.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, size: 21, color: t.accentGreenInk),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: t.titleMd,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: t.labelSoft.copyWith(color: t.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: t.textTertiary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether to offer administration at all: an identity the server named, with
/// at least one of the three read permissions. Nothing is shown to an
/// anonymous session or to an API key — see [identifiedPermissionProvider].
final canOpenAdminProvider = Provider<bool>((ref) =>
    ref.watch(canReadUsersProvider) ||
    ref.watch(canReadGroupsProvider) ||
    ref.watch(canReadApiKeysProvider));
