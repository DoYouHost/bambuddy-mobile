import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/action_outcome.dart';
import '../../core/models/inventory.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../settings/queue_settings_providers.dart';

/// The server-wide `low_stock_threshold`, shown where the alert is configured
/// and edited here by whoever may write server settings, as on the web's Low
/// Stock tile. Everyone else sees the number without the pencil: an API key can
/// never write it and a named account may lack `settings:update`
/// ([queueSettingsLockProvider] decides, and a refused write closes it).
///
/// Here and not on the server settings hub, which is where a new server-side
/// setting normally goes (docs/api-keys-and-settings.md): the number is what the
/// alert on this screen measures against, and the user chose to change it where
/// it is read.
class LowStockThresholdRow extends ConsumerStatefulWidget {
  const LowStockThresholdRow({super.key, this.dimmed = false});

  /// The low filament alert is switched off on this phone. The number still
  /// drives the inventory list, so this only dims the row, as the other
  /// threshold rows are dimmed when their alert is off.
  final bool dimmed;

  static const id = 'notification_settings.low_stock';

  @override
  ConsumerState<LowStockThresholdRow> createState() =>
      _LowStockThresholdRowState();
}

class _LowStockThresholdRowState extends ConsumerState<LowStockThresholdRow> {
  /// A write is out. A second one started meanwhile could be answered first,
  /// and the settings would then show the older number over the newer one.
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final threshold = ref.watch(lowStockThresholdProvider);
    final writable =
        ref.watch(queueSettingsLockProvider).value == QueueSettingsLock.none;
    return Opacity(
      opacity: widget.dimmed ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DashSpace.md,
          vertical: DashSpace.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.notifLowStockTitle(formatLowStockThreshold(threshold)),
                    style: t.titleSm,
                  ),
                  const SizedBox(height: DashSpace.xs),
                  Text(l10n.notifLowStockDesc, style: t.label),
                ],
              ),
            ),
            if (writable)
              IconButton(
                tooltip: l10n.notifLowStockEdit,
                icon: const Icon(Icons.edit_outlined),
                // 48 dp whatever the theme's density says: the row is the only
                // thing on this card that is a button.
                constraints: const BoxConstraints.tightFor(
                  width: DashSize.d48,
                  height: DashSize.d48,
                ),
                onPressed: _saving ? null : () => _edit(threshold),
              ).tagged('${LowStockThresholdRow.id}.edit'),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(double current) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // Read now: the dialog can outlive this row (the screen popped, the
    // settings re-read without the key), and `ref` is not usable after that.
    final settings = ref.read(serverSettingsProvider.notifier);
    final repository = ref.read(serverSettingsRepositoryProvider);
    final text = await promptName(
      context,
      title: l10n.notifLowStockEdit,
      label: l10n.notifLowStockInputLabel,
      initial: formatLowStockThreshold(current),
      id: LowStockThresholdRow.id,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
    if (text == null) return;
    final value = parseLowStockThresholdInput(text);
    if (value == null) {
      messenger.snack(l10n.notifLowStockInvalid);
      return;
    }
    if (mounted) setState(() => _saving = true);
    try {
      final outcome = await runAction(() async {
        // The reply is the whole of `AppSettings`: handing it straight over
        // spares a second read that could fail after a save that worked.
        settings.adopt(await repository.update({lowStockThresholdKey: value}));
      }, logId: '${LowStockThresholdRow.id}.save');
      if (outcome.messageFor(l10n) case final message?) {
        messenger.snack(message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
