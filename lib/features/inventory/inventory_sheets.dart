part of 'inventory_screen.dart';

/// Opens spool create/edit sheet. [existing] != null → edit mode.
void openSpoolForm(BuildContext context, {Spool? existing}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: _sheetBarrier,
    builder: (_) => _SpoolFormSheet(existing: existing),
  );
}

/// Opens spool-to-slot assignment sheet (AMS or external extruder) —
/// reverse flow from dashboard chip: spool is known, we pick a slot.
/// Available when spool is not yet assigned anywhere.
void _openAssignSheet(BuildContext context, Spool spool) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: _sheetBarrier,
    builder: (_) => _AssignSheet(spool: spool),
  );
}

/// Printer and slot picker for assigning [spool]. Printer list from dashboard roster;
/// slot layout (AMS units, dual-extruder) fetched from live status if available —
/// for offline printer, fall back to manual number entry (assignment is DB operation,
/// works even with machine off). External spool convention: `ams_id=255`,
/// `tray_id` 0=left, 1=right ([[inventory-filaments]]).
class _AssignSheet extends ConsumerStatefulWidget {
  const _AssignSheet({required this.spool});

  final Spool spool;

  @override
  ConsumerState<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends ConsumerState<_AssignSheet> {
  int? _printerId;
  bool _external = false;
  int _amsUnit = 0;
  int _amsSlot = 0;
  int _externalTray = 0; // 0 = lewy, 1 = prawy
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = DashTokens.of(context);
    final roster = ref.watch(dashboardProvider).printers ?? const [];

    // Default printer: first from roster (once, while nothing chosen).
    if (_printerId == null && roster.isNotEmpty) {
      _printerId = roster.first.printer.id;
    }

    final status = _printerId == null
        ? null
        : ref.watch(printerStatusesProvider)[_printerId];
    final dual = status?.isDualExtruder ?? false;
    // AMS units detected live (their ids) — if none, provide 0..3.
    final unitIds =
        (status?.ams ?? const []).map((u) => u.id ?? 0).toSet().toList()
          ..sort();
    final unitOptions = unitIds.isNotEmpty ? unitIds : const [0, 1, 2, 3];
    // Keep the persisted selection in sync with the current printer's actual
    // units — without this, switching to a printer with fewer AMS units only
    // fixes the *displayed* value (see `_NumberDropdown` below) while
    // `_amsUnit` itself stays stale, so `_assign()` would submit a unit id
    // the printer doesn't have.
    if (!unitOptions.contains(_amsUnit)) {
      _amsUnit = unitOptions.first;
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      builder: (context, controller) => _SheetSurface(child: ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(
            l10n.inventoryAssignTitle,
            style: TextStyle(
              fontFamily: DashTokens.fontUi,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.spool.displayName,
            style: TextStyle(
              fontFamily: DashTokens.fontUi,
              fontSize: 13,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          if (roster.isEmpty)
            Text(l10n.inventoryAssignNoPrinters)
          else ...[
            Text(
              l10n.inventoryAssignPrinter,
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: _printerId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final p in roster)
                  DropdownMenuItem(
                    value: p.printer.id,
                    child: Text(p.printer.name),
                  ),
              ],
              onChanged: (v) => setState(() => _printerId = v),
            ),
            const SizedBox(height: 16),

            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(l10n.inventorySlotAms)),
                ButtonSegment(value: true, label: Text(l10n.externalSpool)),
              ],
              selected: {_external},
              onSelectionChanged: (s) => setState(() => _external = s.first),
            ),
            const SizedBox(height: 16),

            if (_external) ...[
              if (dual) ...[
                Text(
                  l10n.inventoryAssignExtruder,
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                SegmentedButton<int>(
                  segments: [
                    ButtonSegment(value: 0, label: Text(l10n.extruderLeft)),
                    ButtonSegment(value: 1, label: Text(l10n.extruderRight)),
                  ],
                  selected: {_externalTray},
                  onSelectionChanged: (s) =>
                      setState(() => _externalTray = s.first),
                ),
              ] else
                Text(
                  l10n.inventoryAssignExternalHint,
                  style: theme.textTheme.bodyMedium,
                ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: _NumberDropdown(
                      // `_NumberDropdown` wraps `DropdownButtonFormField`,
                      // whose `initialValue` only seeds state on first build —
                      // force a fresh element when the printer (and thus the
                      // valid unit range) changes, or the field would keep
                      // showing the previous printer's selection.
                      key: ValueKey(_printerId),
                      label: l10n.inventoryAssignUnit,
                      value: _amsUnit,
                      // Display 1-based, value is unit id.
                      items: {for (final u in unitOptions) u: '${u + 1}'},
                      onChanged: (v) => setState(() => _amsUnit = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumberDropdown(
                      label: l10n.inventoryAssignSlot,
                      value: _amsSlot,
                      items: {for (var s = 0; s < 4; s++) s: '${s + 1}'},
                      onChanged: (v) => setState(() => _amsSlot = v),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 24),

            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: t.accentGreen,
                foregroundColor: _onAccentGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: _saving || _printerId == null ? null : _assign,
              icon: _saving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _onAccentGreen,
                      ),
                    )
                  : const Icon(Icons.add_link, size: 18),
              label: Text(
                l10n.inventoryAssignConfirm,
                style: const TextStyle(
                  fontFamily: DashTokens.fontUi,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      )),
    );
  }

  Future<void> _assign() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final printerId = _printerId;
    if (printerId == null) return;
    final draft = SpoolAssignmentDraft(
      spoolId: widget.spool.id,
      printerId: printerId,
      amsId: _external ? 255 : _amsUnit,
      trayId: _external ? _externalTray : _amsSlot,
    );
    setState(() => _saving = true);
    try {
      await ref.read(inventoryProvider.notifier).assignSpool(draft);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.inventorySpoolAssigned)),
      );
    } on AppApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(e.localized(l10n))));
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.inventoryActionFailed)),
      );
    }
  }
}

/// Numeric dropdown (label above field) — int with display label map.
class _NumberDropdown extends StatelessWidget {
  const _NumberDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final int value;
  final Map<int, String> items;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(
          initialValue: value,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final e in items.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      ],
    );
  }
}

/// Action row in spool details: edit, reset usage, archive/restore, delete.
/// Each action closes the sheet first, then calls mutation on [inventoryProvider]
/// (which reloads the list itself) and reports result via snackbar.
/// Destructive actions (delete, reset) need dialog confirmation.
class _SpoolActions extends ConsumerWidget {
  const _SpoolActions({required this.spool, this.assignment});

  final Spool spool;
  final SpoolAssignment? assignment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ActionPill(
          tokens: t,
          variant: _ActionPillVariant.primary,
          onPressed: () {
            Navigator.of(context).pop();
            openSpoolForm(context, existing: spool);
          },
          icon: Icons.edit_outlined,
          label: l10n.inventoryEdit,
        ),
        if (!spool.isArchived)
          if (assignment != null)
            _ActionPill(
              tokens: t,
              onPressed: () => _run(
                context,
                ref,
                l10n,
                ref
                    .read(inventoryProvider.notifier)
                    .unassignSpool(
                      assignment!.printerId,
                      assignment!.amsId,
                      assignment!.trayId,
                    ),
                l10n.inventorySpoolUnassigned,
              ),
              icon: Icons.link_off,
              label: l10n.inventoryUnassign,
            )
          else
            _ActionPill(
              tokens: t,
              onPressed: () {
                Navigator.of(context).pop();
                _openAssignSheet(context, spool);
              },
              icon: Icons.add_link,
              label: l10n.inventoryAssign,
            ),
        if (spool.weightUsed > 0)
          _ActionPill(
            tokens: t,
            onPressed: () => _resetUsage(context, ref, l10n),
            icon: Icons.refresh,
            label: l10n.inventoryResetUsage,
          ),
        if (spool.isArchived)
          _ActionPill(
            tokens: t,
            onPressed: () => _run(
              context,
              ref,
              l10n,
              ref.read(inventoryProvider.notifier).restoreSpool(spool.id),
              l10n.inventorySpoolRestored,
            ),
            icon: Icons.unarchive_outlined,
            label: l10n.inventoryRestore,
          )
        else
          _ActionPill(
            tokens: t,
            onPressed: () => _run(
              context,
              ref,
              l10n,
              ref.read(inventoryProvider.notifier).archiveSpool(spool.id),
              l10n.inventorySpoolArchived,
            ),
            icon: Icons.archive_outlined,
            label: l10n.inventoryArchive,
          ),
        _ActionPill(
          tokens: t,
          variant: _ActionPillVariant.destructive,
          onPressed: () => _delete(context, ref, l10n),
          icon: Icons.delete_outline,
          label: l10n.inventoryDelete,
        ),
      ],
    );
  }

  Future<void> _resetUsage(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ok = await confirmDialog(
      context,
      title: l10n.inventoryResetUsage,
      message: l10n.inventoryResetUsageConfirm,
      confirmLabel: l10n.inventoryResetUsage,
    );
    if (!ok || !context.mounted) return;
    await _run(
      context,
      ref,
      l10n,
      ref.read(inventoryProvider.notifier).resetUsage(spool.id),
      l10n.inventoryUsageReset,
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ok = await confirmDialog(
      context,
      title: l10n.inventoryDeleteTitle,
      message: l10n.inventoryDeleteConfirm(spool.displayName),
      confirmLabel: l10n.inventoryDelete,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await _run(
      context,
      ref,
      l10n,
      ref.read(inventoryProvider.notifier).deleteSpool(spool.id),
      l10n.inventorySpoolDeleted,
    );
  }

  /// Closes sheet, waits for [action], reports result to parent ScaffoldMessenger
  /// (captured before pop, since sheet context disappears).
  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Future<void> action,
    String successMsg,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    try {
      await action;
      messenger.showSnackBar(SnackBar(content: Text(successMsg)));
    } on AppApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.localized(l10n))));
    } on Object {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.inventoryActionFailed)),
      );
    }
  }
}

enum _ActionPillVariant { primary, outline, destructive }

/// Small pill action button used in the spool detail sheet's action row.
/// [primary] (Edit) is filled with a tinted accent; other actions are
/// outlined; [destructive] (Delete) is text-only in the danger color.
class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.tokens,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.variant = _ActionPillVariant.outline,
  });

  final DashTokens tokens;
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final _ActionPillVariant variant;

  @override
  Widget build(BuildContext context) {
    final color = variant == _ActionPillVariant.destructive
        ? tokens.danger
        : tokens.accentGreenInk;
    final fill = variant == _ActionPillVariant.primary
        ? tokens.accentGreen.withValues(alpha: 0.16)
        : Colors.transparent;
    final border = variant == _ActionPillVariant.outline
        ? Border.all(color: tokens.accentGreen.withValues(alpha: 0.4))
        : null;

    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: border,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: DashTokens.fontUi,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
