import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/format/datetime_format.dart';
import '../../core/models/maintenance.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../common/dash_async.dart';
import '../common/dash_sheet.dart';
import '../common/dash_snack.dart';
import '../common/state_views.dart';
import 'maintenance_icons.dart';
import 'maintenance_providers.dart';

/// Printer maintenance screen (M7): overview of all printer states grouped by printer,
/// mark task done (reset counter), and history. View + execute only — type management stays on server.
class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // First build fetches current state anyway — clear any dirty marker from background action
    // to avoid unnecessary refresh on return.
    ref.read(settingsRepositoryProvider).setMaintenanceDirty(false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshIfDirty();
  }

  /// On app return: if background notification "mark done" reset counter in isolate,
  /// fetch fresh state. `reload()` necessary — write from different isolate,
  /// so UI prefs cache doesn't see it.
  Future<void> _refreshIfDirty() async {
    await ref.read(sharedPreferencesProvider).reload();
    final settings = ref.read(settingsRepositoryProvider);
    if (!settings.maintenanceDirty()) return;
    await settings.setMaintenanceDirty(false);
    if (!mounted) return;
    await ref.read(maintenanceOverviewProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(maintenanceOverviewProvider);

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(
          context,
          title: l10n.navMaintenance,
          actions: [
            logTag(
              'maintenance.settings',
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: l10n.maintenanceSettingsTitle,
                onPressed: () => context.push('/settings/maintenance'),
              ),
            ),
          ],
        ),
        body: dashAsync(
          context,
          async,
          onRetry: () => ref.read(maintenanceOverviewProvider.notifier).refresh(),
          data: (printers) => RefreshIndicator(
            onRefresh: () =>
                ref.read(maintenanceOverviewProvider.notifier).refresh(),
            child: printers.isEmpty
                ? EmptyStateView(
                    message: l10n.maintenanceEmpty,
                    icon: Icons.build_circle_outlined,
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      for (final p in printers)
                        _PrinterSection(
                          printer: p,
                          // Single printer: no point hiding its tasks. With
                          // several, collapse by default so the list stays scannable.
                          initiallyExpanded: printers.length == 1,
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _PrinterSection extends StatefulWidget {
  const _PrinterSection({required this.printer, required this.initiallyExpanded});

  final PrinterMaintenanceOverview printer;
  final bool initiallyExpanded;

  @override
  State<_PrinterSection> createState() => _PrinterSectionState();
}

class _PrinterSectionState extends State<_PrinterSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final printer = widget.printer;
    final items = [...printer.maintenanceItems]
      ..sort((a, b) => a.hoursUntilDue.compareTo(b.hoursUntilDue));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: t.cardGradient,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: t.cardBorder),
        ),
        // One card per printer: the tasks live inside it, split off by
        // hairlines, so nesting needs no indent to read. Clipping keeps the
        // header and last-row ink inside the rounded corners.
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              logTag(
                'maintenance.printer_toggle',
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                printer.printerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.titleLg,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                [
                                  if (printer.printerModel != null)
                                    printer.printerModel!,
                                  l10n.maintenanceTotalHours(
                                      printer.totalPrintHours.round()),
                                ].join(' · '),
                                style: t.monoLabel,
                              ),
                            ],
                          ),
                        ),
                        if (printer.dueCount > 0) ...[
                          const SizedBox(width: 12),
                          DashPill(
                            label: l10n.maintenanceDueBadge(printer.dueCount),
                            accent: t.accentOrange,
                          ),
                        ],
                        const SizedBox(width: 8),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(Icons.expand_more, color: t.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Divider goes before each row, so it also separates
                          // the header from the first task and a printer with
                          // no tasks gets no stray line.
                          for (final item in items) ...[
                            const Divider(height: 1),
                            _MaintenanceRow(item: item),
                          ],
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaintenanceRow extends ConsumerWidget {
  const _MaintenanceRow({required this.item});

  final MaintenanceStatus item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final due = item.isDue;
    // Binary accent: due/overdue gets the urgent orange, everything else (ok
    // and not-yet-due warning) shares the neutral green tier.
    final tileAccent = due ? t.accentOrange : t.accentGreen;
    final inkAccent = due ? t.accentOrange : t.accentGreenInk;

    final dueText = item.isDue
        ? l10n.maintenanceOverdueBy(item.hoursUntilDue.abs().round())
        : l10n.maintenanceDueIn(item.hoursUntilDue.round());

    return Opacity(
      opacity: item.enabled ? 1 : 0.5,
      child: logTag(
        'maintenance.task',
        InkWell(
          onTap: () => _showHistory(context, ref, l10n),
          child: Padding(
            // Trimmed on the right because the perform button brings its own
            // padding; without that the row would sit visibly off-centre.
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tileAccent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    maintenanceIcon(item.maintenanceTypeIcon),
                    size: 18,
                    color: inkAccent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.maintenanceTypeName, style: t.titleSm),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: item.progress,
                          minHeight: 5,
                          backgroundColor: t.gaugeTrack,
                          valueColor: AlwaysStoppedAnimation(tileAccent),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        dueText,
                        style: t.monoLabel.copyWith(
                            color: due ? t.accentOrange : t.textTertiary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.check_circle_outline, size: 28),
                  // Matches the row's own urgency accent (orange when overdue)
                  // instead of always green, so it doesn't clash with the rest.
                  color: inkAccent,
                  tooltip: l10n.maintenancePerform,
                  onPressed: () => _confirmPerform(context, ref, l10n),
                ).tagged('maintenance.perform'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmPerform(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    // `null` = cancelled; otherwise the (possibly empty) trimmed notes text.
    final notes = await showDialog<String>(
      context: context,
      builder: (_) => _PerformConfirmDialog(title: item.maintenanceTypeName),
    );
    if (notes == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(maintenanceOverviewProvider.notifier)
        .perform(item.id, notes: notes.isEmpty ? null : notes);
    if (!context.mounted) return;
    messenger.snack(result.messageFor(l10n) ?? l10n.maintenanceDone);
  }

  Future<void> _showHistory(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final prov = maintenanceHistoryProvider(item.id);
    // Prefetch before opening so the sheet slides up already populated —
    // otherwise the autoDispose fetch resolves mid-animation and flashes a
    // spinner, which reads like a bug. Hold a manual subscription so the
    // provider isn't disposed+refetched when the sheet subscribes.
    final sub = ref.listenManual(prov, (_, _) {});
    try {
      await ref.read(prov.future);
    } catch (_) {
      // Ignore — the sheet renders the error state itself.
    }
    if (!context.mounted) {
      sub.close();
      return;
    }
    await dashSheet<void>(
      context,
      scrollControlled: false,
      builder: (ctx) => _HistorySheet(item: item),
    );
    sub.close();
  }
}

/// "Perform maintenance" confirm dialog with optional notes — a StatefulWidget
/// so it owns and disposes its own controller in the State lifecycle, same as
/// `_NotesEditDialog` in project_detail_screen.dart (`_MaintenanceRow` is a
/// plain `ConsumerWidget` with no dispose hook of its own to hang this off).
/// Returns the trimmed notes text on confirm (possibly empty), `null` on cancel.
class _PerformConfirmDialog extends StatefulWidget {
  const _PerformConfirmDialog({required this.title});

  final String title;

  @override
  State<_PerformConfirmDialog> createState() => _PerformConfirmDialogState();
}

class _PerformConfirmDialogState extends State<_PerformConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.maintenancePerformConfirm),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              labelText: l10n.maintenanceNotesHint,
              border: const OutlineInputBorder(),
            ),
            maxLines: 2,
          ).tagged('maintenance_perform.notes'),
        ],
      ),
      actions: [
        logTag(
          'maintenance_perform.cancel',
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ),
        logTag(
          'maintenance_perform.confirm',
          FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text.trim()),
            child: Text(l10n.maintenancePerform),
          ),
        ),
      ],
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
    final fmt = DateTimeFormats.of(context);
    final async = ref.watch(maintenanceHistoryProvider(item.id));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Force full width so the sheet doesn't animate down to the
            // intrinsic text width (unlike the archive sheet, whose Row/Expanded
            // already fills the width). Keeps the slide-up matching other sheets.
            const SizedBox(width: double.infinity),
            Text('${item.maintenanceTypeName} · ${l10n.maintenanceHistory}',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            dashAsyncStrip(
              context,
              async,
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
                              title: Text(
                                  _formatDate(fmt, e.performedAtDate) ?? '—'),
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

String? _formatDate(DateTimeFormats fmt, DateTime? dt) =>
    dt == null ? null : fmt.dateTime(dt);

