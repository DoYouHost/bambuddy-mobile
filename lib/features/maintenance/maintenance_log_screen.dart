import 'dart:async';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/format/datetime_format.dart';
import '../../core/models/current_user.dart';
import '../../core/models/maintenance.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import '../common/chips_or_select.dart';
import '../common/dash_async.dart';
import '../common/device_files.dart';
import 'maintenance_providers.dart';

/// The log of maintenance resets (server 1.3.2): one printer at a time, picked
/// by its chip, newest first. The printer that was open last is the one that
/// opens next time, kept on the device (`loadMaintenanceLogPrinter`).
///
/// The menu exports and cleans up either this printer or all of them; a row's
/// long press deletes it. Cleanup and delete need `maintenance:delete`, and are
/// left out without it, while reading and exporting are not.
class MaintenanceLogScreen extends ConsumerStatefulWidget {
  const MaintenanceLogScreen({super.key});

  @override
  ConsumerState<MaintenanceLogScreen> createState() =>
      _MaintenanceLogScreenState();
}

class _MaintenanceLogScreenState extends ConsumerState<MaintenanceLogScreen> {
  int? _printerId;

  /// A save dialog is open or the CSV is being fetched: a second tap would
  /// fetch it again.
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _printerId = ref
        .read(settingsRepositoryProvider)
        .loadMaintenanceLogPrinter();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final overview = ref.watch(maintenanceOverviewProvider);
    final printers = overview.value ?? const <PrinterMaintenanceOverview>[];
    final shown = _shownOf(printers);
    final mayDelete = ref.watch(
      permissionProvider(Permissions.maintenanceDelete),
    );

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(
          context,
          title: shown == null
              ? l10n.maintenanceLog
              : l10n.maintenanceLogTitle(shown.printerName),
          actions: [
            if (shown != null)
              logTag(
                'maintenance_log.menu',
                PopupMenuButton<_LogAction>(
                  onSelected: (action) => _run(action, shown),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: _LogAction.exportPrinter,
                      child: logTag(
                        'maintenance_log.export_printer',
                        Text(l10n.maintenanceLogExportPrinter),
                      ),
                    ),
                    PopupMenuItem(
                      value: _LogAction.exportAll,
                      child: logTag(
                        'maintenance_log.export_all',
                        Text(l10n.maintenanceLogExportAll),
                      ),
                    ),
                    if (mayDelete) ...[
                      PopupMenuItem(
                        value: _LogAction.cleanUpPrinter,
                        child: logTag(
                          'maintenance_log.cleanup_printer',
                          Text(l10n.maintenanceLogCleanUpPrinter),
                        ),
                      ),
                      PopupMenuItem(
                        value: _LogAction.cleanUpAll,
                        child: logTag(
                          'maintenance_log.cleanup_all',
                          Text(l10n.maintenanceLogCleanUpAll),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
        body: dashAsync(
          context,
          overview,
          onRetry: () =>
              ref.read(maintenanceOverviewProvider.notifier).refresh(),
          data: (_) => shown == null
              ? EmptyStateView(
                  message: l10n.maintenanceEmpty,
                  icon: Icons.build_circle_outlined,
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DashSpace.gutter,
                        vertical: DashSpace.sm,
                      ),
                      // Chips for a small fleet; the select when they would take
                      // more than two rows, at this width and text size.
                      child: ChipsOrSelect(
                        chips: Wrap(
                          spacing: DashSpace.sm,
                          runSpacing: DashSpace.sm,
                          children: [
                            for (final p in printers)
                              ChoiceChip(
                                label: Text(p.printerName),
                                selected: p.printerId == shown.printerId,
                                onSelected: (_) => _pick(p.printerId),
                              ).tagged(
                                'maintenance_log.printer',
                                selected: p.printerId == shown.printerId,
                              ),
                          ],
                        ),
                        select: dashCombo<int>(
                          context,
                          id: 'maintenance_log.printer_select',
                          // Rebuilt when the printer changes from elsewhere: the
                          // field only reads its initial selection.
                          fieldKey: ValueKey(shown.printerId),
                          label: Text(l10n.maintenanceLogPrinter),
                          initialSelection: shown.printerId,
                          textStyle: DashTokens.of(context).body,
                          onSelected: (id) {
                            if (id != null) _pick(id);
                          },
                          entries: [
                            for (final p in printers)
                              DropdownMenuEntry(
                                value: p.printerId,
                                label: p.printerName,
                                labelWidget: logTag(
                                  'maintenance_log.printer_select.option',
                                  Text(p.printerName),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: _LogList(
                        printerId: shown.printerId,
                        mayDelete: mayDelete,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// The printer on screen. A remembered one that is gone (deleted, or another
  /// server) falls back to the first.
  PrinterMaintenanceOverview? _shownOf(
    List<PrinterMaintenanceOverview> printers,
  ) => printers.isEmpty
      ? null
      : printers.firstWhere(
          (p) => p.printerId == _printerId,
          orElse: () => printers.first,
        );

  void _pick(int printerId) {
    setState(() => _printerId = printerId);
    unawaited(
      ref.read(settingsRepositoryProvider).saveMaintenanceLogPrinter(printerId),
    );
  }

  Future<void> _run(_LogAction action, PrinterMaintenanceOverview shown) =>
      switch (action) {
        _LogAction.exportPrinter => _export(
          shown.printerId,
          'maintenance_log.export_printer',
        ),
        _LogAction.exportAll => _export(null, 'maintenance_log.export_all'),
        _LogAction.cleanUpPrinter => _cleanUp(shown, all: false),
        _LogAction.cleanUpAll => _cleanUp(shown, all: true),
      };

  /// Saves the CSV of [printerId], or of every printer when null, wherever the
  /// user points the system dialog. The file is small, so it goes through bytes.
  Future<void> _export(int? printerId, String logId) async {
    if (_exporting) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      final file = await ref
          .read(maintenanceRepositoryProvider)
          .exportLog(printerId: printerId);
      // Left meanwhile: the dialog would open over whatever is there now.
      if (!mounted) return;
      final saved = await saveBytesToDevice(
        fileName: file.filename,
        bytes: file.bytes,
        dialogTitle: l10n.maintenanceLog,
      );
      switch (saved.outcome) {
        // Backing out of the dialog is an answer, not a failure.
        case DeviceFileOutcome.cancelled:
          return;
        case DeviceFileOutcome.failed:
          messenger.snack(l10n.filePickerFailed);
        case DeviceFileOutcome.done:
          messenger.snack(l10n.maintenanceLogSaved(file.filename));
      }
    } on AppApiException catch (e) {
      showApiFailure(messenger, e, l10n, action: logId);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _cleanUp(
    PrinterMaintenanceOverview shown, {
    required bool all,
  }) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final days = await showDialog<int>(
      context: context,
      builder: (_) =>
          _CleanUpDialog(printerName: all ? null : shown.printerName),
    );
    if (!mounted || days == null) return;
    // The overview may have reloaded under the dialog: the list to reload is
    // the one on screen now, and a printer that is gone has nothing to clean.
    final now = _shownOf(
      ref.read(maintenanceOverviewProvider).value ??
          const <PrinterMaintenanceOverview>[],
    );
    if (now == null || (!all && now.printerId != shown.printerId)) return;
    final result = await ref
        .read(maintenanceLogProvider(now.printerId).notifier)
        .cleanUp(
          days,
          allPrinters: all,
          logId: all
              ? 'maintenance_log.cleanup_all'
              : 'maintenance_log.cleanup_printer',
        );
    messenger.snack(
      result.outcome.messageFor(l10n) ??
          l10n.maintenanceLogCleanedUp(result.deleted),
    );
  }
}

enum _LogAction { exportPrinter, exportAll, cleanUpPrinter, cleanUpAll }

/// One printer's entries, a page at a time.
class _LogList extends ConsumerWidget {
  const _LogList({required this.printerId, required this.mayDelete});

  final int printerId;
  final bool mayDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final provider = maintenanceLogProvider(printerId);
    final notifier = ref.read(provider.notifier);

    return dashAsync(
      context,
      ref.watch(provider),
      onRetry: notifier.refresh,
      data: (view) => RefreshIndicator(
        onRefresh: notifier.refresh,
        child: view.entries.isEmpty
            ? EmptyStateView(
                message: l10n.maintenanceLogEmpty,
                icon: Icons.history,
              )
            : ListView(
                // As on every other refreshable list: a short one is still dragged.
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: DashSpace.lg),
                children: [
                  for (final entry in view.entries)
                    _EntryTile(
                      entry: entry,
                      onDelete: mayDelete
                          ? () => _delete(context, ref, entry)
                          : null,
                    ),
                  if (notifier.hasMore)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DashSpace.gutter,
                        vertical: DashSpace.sm,
                      ),
                      child: logTag(
                        'maintenance_log.load_more',
                        OutlinedButton(
                          onPressed: () => _loadMore(context, ref),
                          child: Text(
                            l10n.maintenanceLogLoadMore(
                              view.entries.length,
                              view.total,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _loadMore(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await ref
        .read(maintenanceLogProvider(printerId).notifier)
        .loadMore(logId: 'maintenance_log.load_more');
    final message = outcome.messageFor(l10n);
    if (message != null) messenger.snack(message);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    MaintenanceLogEntry entry,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final fmt = DateTimeFormats.of(context);
    final when = entry.performedAtDate;
    final confirmed = await confirmDialog(
      context,
      id: 'maintenance_log.delete_entry_confirm',
      title: l10n.maintenanceLogDeleteEntryTitle,
      message: l10n.maintenanceLogDeleteEntryMessage(
        entry.maintenanceTypeName,
        when == null ? '—' : fmt.dateTime(when),
      ),
      confirmLabel: l10n.maintenanceLogDelete,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final outcome = await ref
        .read(maintenanceLogProvider(printerId).notifier)
        .deleteEntry(entry.id, logId: 'maintenance_log.entry');
    messenger.snack(
      outcome.messageFor(l10n) ?? l10n.maintenanceLogEntryDeleted,
    );
  }
}

/// A reset: the task, then who made it, when and at how many hours, then the
/// comment. A long press deletes it where the user may.
class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onDelete});

  final MaintenanceLogEntry entry;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final fmt = DateTimeFormats.of(context);
    final when = entry.performedAtDate;
    final who = entry.performedByUsername;
    final meta = [
      if (who != null && who.isNotEmpty) who,
      if (when != null) fmt.dateTime(when),
      l10n.maintenanceLogHours(entry.hoursAtMaintenance.round()),
    ].join(' · ');
    final notes = entry.notes;

    return logTag(
      'maintenance_log.entry',
      ListTile(
        title: Text(
          entry.maintenanceTypeName.isEmpty ? '—' : entry.maintenanceTypeName,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(meta),
            if (notes != null && notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: DashSpace.xs),
                child: Text(notes, style: theme.textTheme.bodyMedium),
              ),
          ],
        ),
        onLongPress: onDelete,
      ),
    );
  }
}

/// How old the entries to delete must be: a few ages to pick from, the longest
/// first chosen, because the shorter the age the more it takes with it.
class _CleanUpDialog extends StatefulWidget {
  const _CleanUpDialog({required this.printerName});

  /// Null cleans every printer the user can see.
  final String? printerName;

  /// Within the route's 1..36500.
  static const ages = [30, 90, 180, 365];

  @override
  State<_CleanUpDialog> createState() => _CleanUpDialogState();
}

class _CleanUpDialogState extends State<_CleanUpDialog> {
  int _days = _CleanUpDialog.ages.last;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final printerName = widget.printerName;

    return logSurface(
      'maintenance_log_cleanup',
      AlertDialog(
        scrollable: true,
        title: Text(l10n.maintenanceLogCleanUpTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              printerName == null
                  ? l10n.maintenanceLogCleanUpMessageAll
                  : l10n.maintenanceLogCleanUpMessage(printerName),
            ),
            const SizedBox(height: DashSpace.md),
            Wrap(
              spacing: DashSpace.sm,
              runSpacing: DashSpace.sm,
              children: [
                for (final days in _CleanUpDialog.ages)
                  ChoiceChip(
                    label: Text(
                      days == 365
                          ? l10n.maintenanceLogYear
                          : l10n.maintenanceLogAge(days),
                    ),
                    selected: _days == days,
                    onSelected: (_) => setState(() => _days = days),
                  ).tagged(
                    'maintenance_log_cleanup.age',
                    selected: _days == days,
                  ),
              ],
            ),
          ],
        ),
        actions: [
          logTag(
            'maintenance_log_cleanup.cancel',
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
          ),
          logTag(
            'maintenance_log_cleanup.confirm',
            FilledButton(
              style: dashDangerButtonStyle(t),
              onPressed: () => Navigator.pop(context, _days),
              child: Text(l10n.maintenanceLogDelete),
            ),
          ),
        ],
      ),
    );
  }
}
