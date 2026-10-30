import 'dart:async';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/action_outcome.dart';
import '../../core/models/profile_default.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../common/dash_async.dart';
import 'inventory_providers.dart';

/// Settings → Profile defaults (server #1326): what new spools of each product
/// start with. A default is saved from a spool's form; this screen lists them,
/// applies one to the spools already in stock and deletes one.
class ProfileDefaultsScreen extends ConsumerStatefulWidget {
  const ProfileDefaultsScreen({super.key});

  @override
  ConsumerState<ProfileDefaultsScreen> createState() =>
      _ProfileDefaultsScreenState();
}

class _ProfileDefaultsScreenState extends ConsumerState<ProfileDefaultsScreen> {
  /// One write at a time: a second tap while one is in flight would apply or
  /// delete twice.
  bool _busy = false;

  Future<void> _run(
    Future<void> Function() write, {
    required String logId,
    required String Function(AppLocalizations l10n) success,
  }) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final result = await runAction(write, logId: logId);
    if (!mounted) return;
    setState(() => _busy = false);
    messenger.snack(result.messageFor(l10n) ?? success(l10n));
  }

  Future<void> _apply(ProfileDefault row) async {
    final repo = ref.read(profileDefaultsRepositoryProvider);
    final shelf = ref.read(inventoryProvider.notifier);
    var updated = 0;
    await _run(
      () async => updated = await repo.apply(row.id),
      logId: 'profile_defaults.apply',
      success: (l10n) => l10n.profileDefaultsApplied(updated),
    );
    // The shelf shows the preset a spool now carries.
    if (updated > 0) unawaited(shelf.refresh());
  }

  Future<void> _delete(ProfileDefault row) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await confirmDialog(
      context,
      id: 'profile_defaults.delete_confirm',
      title: l10n.profileDefaultsDeleteTitle,
      message: l10n.profileDefaultsDeleteBody(_titleOf(row)),
      confirmLabel: l10n.inventoryDelete,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final repo = ref.read(profileDefaultsRepositoryProvider);
    await _run(
      () => repo.delete(row.id),
      logId: 'profile_defaults.delete',
      // The row leaving the list is the answer.
      success: (_) => '',
    );
    ref.invalidate(profileDefaultsProvider);
  }

  /// "Bambu Lab PLA Basic", with the colour when the default is for one.
  static String _titleOf(ProfileDefault row) => [
    row.product.label,
    if (row.product.colorName.trim().isNotEmpty) row.product.colorName.trim(),
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(profileDefaultsProvider);

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.profileDefaultsTitle),
        body: dashAsync(
          context,
          async,
          onRetry: () => ref.invalidate(profileDefaultsProvider),
          data: (rows) => RefreshIndicator(
            onRefresh: () => ref.refresh(profileDefaultsProvider.future),
            child: ListView(
              padding: screenListPadding(context),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: DashSpace.md),
                  child: Text(
                    l10n.profileDefaultsDescription,
                    style: DashTokens.of(context).label.copyWith(
                      color: DashTokens.of(context).textSecondary,
                    ),
                  ),
                ),
                if (rows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: DashSpace.xl),
                    child: Text(
                      l10n.profileDefaultsEmpty,
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  for (final row in rows)
                    _DefaultCard(
                      row: row,
                      title: _titleOf(row),
                      busy: _busy,
                      onApply: () => _apply(row),
                      onDelete: () => _delete(row),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DefaultCard extends StatelessWidget {
  const _DefaultCard({
    required this.row,
    required this.title,
    required this.busy,
    required this.onApply,
    required this.onDelete,
  });

  final ProfileDefault row;
  final String title;
  final bool busy;
  final VoidCallback onApply;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final parts = [
      if (row.product.colorName.trim().isEmpty)
        l10n.inventoryProfileDefaultAllColors,
      if ((row.slicerFilament ?? '').isNotEmpty)
        l10n.inventoryFieldSlicerPreset,
      if (row.presets.isNotEmpty)
        l10n.profileDefaultsModelPresets(row.presets.length),
      if (row.kProfiles.isNotEmpty)
        l10n.profileDefaultsKProfiles(row.kProfiles.length),
    ];
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(DashRadius.xl),
      side: BorderSide(color: t.subCardBorder),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: DashSpace.md),
      child: Material(
        color: t.subCard,
        shape: shape,
        child: Padding(
          padding: const EdgeInsets.all(DashSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t.titleSm),
              if (parts.isNotEmpty)
                Text(
                  parts.join(' · '),
                  style: t.label.copyWith(color: t.textSecondary),
                ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Wrap(
                  spacing: DashSpace.sm,
                  runSpacing: DashSpace.xs,
                  children: [
                    TextButton(
                      onPressed: busy ? null : onApply,
                      child: Text(l10n.profileDefaultsApply),
                    ).tagged('profile_defaults.apply'),
                    TextButton(
                      onPressed: busy ? null : onDelete,
                      child: Text(l10n.inventoryDelete),
                    ).tagged('profile_defaults.delete'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
