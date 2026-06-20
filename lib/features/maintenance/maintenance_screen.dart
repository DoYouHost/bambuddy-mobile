import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/maintenance.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import 'maintenance_icons.dart';
import 'maintenance_providers.dart';

/// Ekran konserwacji drukarek (M7): przegląd stanu wszystkich drukarek
/// pogrupowany po drukarce, oznaczanie czynności jako wykonanej (reset licznika)
/// i historia. Tylko podgląd + wykonanie — zarządzanie typami zostaje na serwerze.
class MaintenanceScreen extends ConsumerWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(maintenanceOverviewProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navMaintenance)),
      body: async.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorView(
          message: err is AppApiException
              ? err.localized(l10n)
              : l10n.connectFailed,
          onRetry: () =>
              ref.read(maintenanceOverviewProvider.notifier).refresh(),
          retryLabel: l10n.retry,
        ),
        data: (printers) => RefreshIndicator(
          onRefresh: () =>
              ref.read(maintenanceOverviewProvider.notifier).refresh(),
          child: printers.isEmpty
              ? _EmptyView(message: l10n.maintenanceEmpty)
              : ListView(
                  children: [
                    for (final p in printers) _PrinterSection(printer: p),
                    const SizedBox(height: 16),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PrinterSection extends StatelessWidget {
  const _PrinterSection({required this.printer});

  final PrinterMaintenanceOverview printer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final items = [...printer.maintenanceItems]
      ..sort((a, b) => a.hoursUntilDue.compareTo(b.hoursUntilDue));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      printer.printerName,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      [
                        if (printer.printerModel != null) printer.printerModel!,
                        l10n.maintenanceTotalHours(
                            printer.totalPrintHours.round()),
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (printer.dueCount > 0)
                _CountBadge(
                  label: l10n.maintenanceDueBadge(printer.dueCount),
                  color: theme.colorScheme.error,
                ),
              if (printer.warningCount > 0) ...[
                const SizedBox(width: 6),
                _CountBadge(
                  label: l10n.maintenanceWarningBadge(printer.warningCount),
                  color: Colors.orange.shade700,
                ),
              ],
            ],
          ),
        ),
        for (final item in items) _MaintenanceTile(item: item),
        const Divider(height: 16),
      ],
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _MaintenanceTile extends ConsumerWidget {
  const _MaintenanceTile({required this.item});

  final MaintenanceStatus item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final accent = switch (item.severity) {
      MaintenanceSeverity.due => theme.colorScheme.error,
      MaintenanceSeverity.warning => Colors.orange.shade700,
      MaintenanceSeverity.ok => theme.colorScheme.primary,
    };

    final dueText = item.isDue
        ? l10n.maintenanceOverdueBy(item.hoursUntilDue.abs().round())
        : l10n.maintenanceDueIn(item.hoursUntilDue.round());

    return Opacity(
      opacity: item.enabled ? 1 : 0.5,
      child: ListTile(
        leading: Icon(maintenanceIcon(item.maintenanceTypeIcon), color: accent),
        title: Text(item.maintenanceTypeName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: item.progress,
                color: accent,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 4),
            Text(dueText,
                style: theme.textTheme.bodySmall?.copyWith(color: accent)),
          ],
        ),
        trailing: TextButton(
          onPressed: () => _confirmPerform(context, ref, l10n),
          child: Text(l10n.maintenancePerform),
        ),
        onTap: () => _showHistory(context, ref, l10n),
      ),
    );
  }

  Future<void> _confirmPerform(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.maintenanceTypeName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.maintenancePerformConfirm),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: l10n.maintenanceNotesHint,
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.maintenancePerform),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final notes = controller.text.trim();
    final result = await ref
        .read(maintenanceOverviewProvider.notifier)
        .perform(item.id, notes: notes.isEmpty ? null : notes);
    messenger.showSnackBar(SnackBar(content: Text(switch (result) {
      MaintenanceActionResult.ok => l10n.maintenanceDone,
      MaintenanceActionResult.forbidden => l10n.errForbidden,
      MaintenanceActionResult.error => l10n.maintenanceFailed,
    })));
  }

  void _showHistory(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _HistorySheet(item: item),
    );
  }
}

class _HistorySheet extends ConsumerWidget {
  const _HistorySheet({required this.item});

  final MaintenanceStatus item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final async = ref.watch(maintenanceHistoryProvider(item.id));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${item.maintenanceTypeName} · ${l10n.maintenanceHistory}',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.connectFailed),
              ),
              data: (entries) => entries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(l10n.maintenanceHistoryEmpty),
                    )
                  : Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final e in entries)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.check_circle_outline),
                              title: Text(_formatDate(e.performedAtDate) ?? '—'),
                              subtitle: e.notes == null || e.notes!.isEmpty
                                  ? null
                                  : Text(e.notes!),
                              trailing: Text(l10n.maintenanceTotalHours(
                                  e.hoursAtMaintenance.round())),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Prosty format daty `RRRR-MM-DD GG:MM` (lokalny) bez zależności od intl.
String? _formatDate(DateTime? dt) {
  if (dt == null) return null;
  final l = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            children: [
              Icon(Icons.build_circle_outlined,
                  size: 48, color: Theme.of(context).disabledColor),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.retryLabel,
  });

  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}
