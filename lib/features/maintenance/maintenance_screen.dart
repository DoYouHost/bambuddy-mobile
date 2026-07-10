import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/maintenance.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
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
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: l10n.maintenanceSettingsTitle,
              onPressed: () => context.push('/settings/maintenance'),
            ),
          ],
        ),
        body: async.when(
          skipLoadingOnReload: true,
          skipLoadingOnRefresh: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => AsyncErrorView(
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
                ? EmptyStateView(
                    message: l10n.maintenanceEmpty,
                    icon: Icons.build_circle_outlined,
                  )
                : ListView(
                    children: [
                      const SizedBox(height: 8),
                      for (final p in printers) _PrinterSection(printer: p),
                      const SizedBox(height: 16),
                    ],
                  ),
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
    final t = DashTokens.of(context);
    final items = [...printer.maintenanceItems]
      ..sort((a, b) => a.hoursUntilDue.compareTo(b.hoursUntilDue));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              gradient: t.cardGradient,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: t.cardBorder),
            ),
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
                        style: TextStyle(
                          fontFamily: DashTokens.fontUi,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: t.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (printer.printerModel != null)
                            printer.printerModel!,
                          l10n.maintenanceTotalHours(
                              printer.totalPrintHours.round()),
                        ].join(' · '),
                        style: TextStyle(
                          fontFamily: DashTokens.fontMono,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: t.textTertiary,
                        ),
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
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final item in items) _MaintenanceTile(item: item),
        ],
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
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _showHistory(context, ref, l10n),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: due
                    ? t.accentOrange.withValues(alpha: 0.06)
                    : t.subCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: due
                      ? t.accentOrange.withValues(alpha: 0.35)
                      : t.subCardBorder,
                ),
              ),
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
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                item.maintenanceTypeName,
                                style: TextStyle(
                                  fontFamily: DashTokens.fontUi,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: t.textPrimary,
                                ),
                              ),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: t.accentGreenInk,
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 0),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () =>
                                  _confirmPerform(context, ref, l10n),
                              child: Text(l10n.maintenancePerform),
                            ),
                          ],
                        ),
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
                          style: TextStyle(
                            fontFamily: DashTokens.fontMono,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: due ? t.accentOrange : t.textTertiary,
                          ),
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

/// "Perform maintenance" confirm dialog with optional notes — a StatefulWidget
/// so it owns and disposes its own controller in the State lifecycle, same as
/// `_NotesEditDialog` in project_detail_screen.dart (`_MaintenanceTile` is a
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
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(l10n.maintenancePerform),
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

/// Simple date format `YYYY-MM-DD HH:MM` (local) without intl dependency.
String? _formatDate(DateTime? dt) {
  if (dt == null) return null;
  final l = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

