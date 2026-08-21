import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/models/api_key.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../common/confirm_dialog.dart';
import '../common/state_views.dart';
import '../common/system_insets.dart';
import 'api_key_form_screen.dart';
import 'api_key_labels.dart';
import 'api_keys_providers.dart';
import 'user_messages.dart';
import 'users_providers.dart' show runUserWrite;

/// The API keys issued on this server (full screen, pushed from the drawer).
///
/// A key is a credential handed to something that is not this app — Home
/// Assistant, SpoolBuddy, a script — and this screen exists mostly for the
/// moment one has to be taken away again.
class ApiKeysScreen extends ConsumerWidget {
  const ApiKeysScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final async = ref.watch(apiKeysListProvider);
    final canCreate = ref.watch(canCreateApiKeysProvider);

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.apiKeysTitle),
        floatingActionButton: canCreate
            ? logTag(
                'api_keys.create',
                FloatingActionButton.extended(
                  backgroundColor: t.accentGreen,
                  foregroundColor: const Color(0xFF0A0C08),
                  onPressed: () => openApiKeyCreate(context),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.apiKeysCreate),
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
            onRetry: () => ref.read(apiKeysListProvider.notifier).refresh(),
          ),
          data: (keys) => RefreshIndicator(
            onRefresh: () => ref.read(apiKeysListProvider.notifier).refresh(),
            child: keys.isEmpty
                ? EmptyStateView(
                    message: l10n.apiKeysEmpty,
                    icon: Icons.key_outlined,
                  )
                : ListView.builder(
                    padding: withSystemNavInset(
                      context,
                      EdgeInsets.fromLTRB(12, 8, 12, canCreate ? 88 : 24),
                    ),
                    itemCount: keys.length,
                    itemBuilder: (_, i) => _ApiKeyCard(apiKey: keys[i]),
                  ),
          ),
        ),
      ),
    );
  }
}

class _ApiKeyCard extends ConsumerWidget {
  const _ApiKeyCard({required this.apiKey});

  final ApiKey apiKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final canEdit = ref.watch(canUpdateApiKeysProvider);
    final canRevoke = ref.watch(canRevokeApiKeysProvider);
    final expired = apiKey.isExpired(DateTime.now());
    final live = apiKey.enabled && !expired;
    final accent = live ? t.accentGreen : t.textTertiary;

    final subtitle = <String>[
      '${apiKey.keyPrefix}••••••••',
      if (apiKey.lastUsed != null)
        l10n.apiKeysLastUsed(DateFormat.yMMMd(locale).format(apiKey.lastUsed!))
      else
        l10n.apiKeysNeverUsed,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: logTag(
          'api_keys.key',
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: canEdit ? () => openApiKeyEdit(context, apiKey) : null,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: t.cardGradient,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: t.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.key_outlined, size: 20, color: accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              apiKey.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: DashTokens.fontUi,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: live ? t.textPrimary : t.textTertiary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle.join(' · '),
                              style: TextStyle(
                                fontFamily: DashTokens.fontMono,
                                fontSize: 11,
                                color: t.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (canRevoke)
                        IconButton(
                          icon: Icon(Icons.delete_outline,
                              size: 20, color: t.danger),
                          tooltip: l10n.apiKeysRevoke,
                          onPressed: () => _revoke(context, ref),
                        ).tagged('api_keys.revoke'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (!apiKey.enabled)
                        DashPill(
                          label: l10n.apiKeysDisabled,
                          accent: t.danger,
                          icon: Icons.pause_circle_outline,
                        )
                      else if (expired)
                        DashPill(
                          label: l10n.apiKeysExpired,
                          accent: t.danger,
                          icon: Icons.schedule,
                        ),
                      if (apiKey.expiresAt != null && !expired)
                        DashPill(
                          label: l10n.apiKeysExpiresOn(
                              DateFormat.yMMMd(locale).format(apiKey.expiresAt!)),
                          accent: t.accentOrange,
                          icon: Icons.schedule,
                        ),
                      if (apiKey.printerIds != null)
                        DashPill(
                          label: l10n.apiKeysPrinterLimited(
                              apiKey.printerIds!.length),
                          accent: t.accentBlue,
                          icon: Icons.print_outlined,
                        ),
                      if (apiKey.isLegacy)
                        DashPill(
                          label: l10n.apiKeysLegacy,
                          accent: t.accentOrange,
                          icon: Icons.history,
                        ),
                      for (final scope in ApiKeyScope.values)
                        if (apiKey.scopes.contains(scope))
                          DashPill(
                            label: apiKeyScopeLabel(l10n, scope),
                            accent: t.textSecondary,
                            accentInk: t.textSecondary,
                          ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await confirmDialog(
      context,
      title: l10n.apiKeysRevokeQuestion(apiKey.name),
      message: l10n.apiKeysRevokeBody,
      confirmLabel: l10n.apiKeysRevoke,
      id: 'api_key_revoke',
    );
    if (!confirmed) return;

    final result = await runUserWrite(
      () => ref.read(apiKeysRepositoryProvider).delete(apiKey.id),
      'api_keys.revoke',
    );
    await ref.read(apiKeysListProvider.notifier).refresh();
    messenger.showSnackBar(SnackBar(
      content: Text(
        result.ok ? l10n.apiKeysRevoked : userWriteMessage(l10n, result),
      ),
    ));
  }
}

/// Shows the key exactly once — the server keeps only its hash, so this dialog
/// is the last place it exists. Deliberately not persisted anywhere, not put
/// in app state, and not written to the diagnostic log: the copy button is
/// named, its content is not.
Future<void> showCreatedKeyDialog(BuildContext context, String key) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreatedKeyDialog(apiKey: key),
    );

class _CreatedKeyDialog extends StatefulWidget {
  const _CreatedKeyDialog({required this.apiKey});

  final String apiKey;

  @override
  State<_CreatedKeyDialog> createState() => _CreatedKeyDialogState();
}

class _CreatedKeyDialogState extends State<_CreatedKeyDialog> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final apiKey = widget.apiKey;
    return AlertDialog(
      title: Text(l10n.apiKeysCreatedTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.apiKeysCreatedWarning),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.subCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.subCardBorder),
            ),
            child: SelectableText(
              apiKey,
              style: TextStyle(
                fontFamily: DashTokens.fontMono,
                fontSize: 12.5,
                color: t.accentGreenInk,
              ),
            ),
          ),
        ],
      ),
      actions: [
        // The confirmation stays inside the dialog rather than going out as a
        // SnackBar: this route can sit over a screen with no Scaffold under it
        // (the form pops itself first), and a copy that silently threw would
        // be the worst possible moment for it.
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: apiKey));
            if (mounted) setState(() => _copied = true);
          },
          icon: Icon(_copied ? Icons.check : Icons.copy, size: 18),
          label: Text(_copied ? l10n.apiKeysCopied : l10n.apiKeysCopy),
        ).tagged('api_key_created.copy'),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.apiKeysCreatedDone),
        ).tagged('api_key_created.done'),
      ],
    );
  }
}
