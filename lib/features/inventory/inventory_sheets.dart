part of 'inventory_screen.dart';

/// Opens spool create/edit sheet. [existing] != null → edit mode; [copyOf]
/// fills a create form from another spool.
void openSpoolForm(BuildContext context, {Spool? existing, Spool? copyOf}) {
  dashSurfaceSheet<void>(
    context,
    builder: (_) => _SpoolFormSheet(existing: existing, copyOf: copyOf),
  );
}

/// Opens spool-to-slot assignment sheet (AMS or external extruder) —
/// reverse flow from dashboard chip: spool is known, we pick a slot.
/// Available when spool is not yet assigned anywhere.
void _openAssignSheet(BuildContext context, Spool spool) {
  dashSurfaceSheet<void>(context, builder: (_) => _AssignSheet(spool: spool));
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
  int _externalTray = 0; // Holder side — see `slot_addressing`.
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

    return DraggableSheetSurface(
      initialSize: 0.55,
      maxSize: 0.9,
      minSize: 0.3,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(
          DashSpace.gutter,
          0,
          DashSpace.gutter,
          DashSpace.xl,
        ),
        children: [
          Text(l10n.inventoryAssignTitle, style: t.display),
          const SizedBox(height: DashSpace.xs),
          Text(widget.spool.displayName, style: t.bodyPlain),
          const SizedBox(height: DashSpace.lg),

          if (roster.isEmpty)
            Text(l10n.inventoryAssignNoPrinters)
          else ...[
            Text(
              l10n.inventoryAssignPrinter,
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: DashSpace.sm),
            // The label stays above the field rather than moving inside it:
            // the segmented buttons below cannot carry one, and a single field
            // labelled differently from its neighbours reads as a mistake.
            dashCombo<int>(
              context,
              id: 'spool_assign.printer',
              initialSelection: _printerId,
              onSelected: (v) => setState(() => _printerId = v),
              entries: [
                for (final p in roster)
                  DropdownMenuEntry(
                    value: p.printer.id,
                    label: p.printer.name,
                    // One id for every row: the printer's name is the user's
                    // own text, and the field's tag does not reach the popup.
                    labelWidget: logTag(
                      'spool_assign.printer_option',
                      Text(p.printer.name),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: DashSpace.lg),

            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(l10n.inventorySlotAms)),
                ButtonSegment(value: true, label: Text(l10n.externalSpool)),
              ],
              selected: {_external},
              onSelectionChanged: (s) => setState(() => _external = s.first),
            ).tagged('spool_assign.slot_kind'),
            const SizedBox(height: DashSpace.lg),

            if (_external) ...[
              if (dual) ...[
                Text(
                  l10n.inventoryAssignExtruder,
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: DashSpace.sm),
                SegmentedButton<int>(
                  segments: [
                    ButtonSegment(value: 0, label: Text(l10n.extruderLeft)),
                    ButtonSegment(value: 1, label: Text(l10n.extruderRight)),
                  ],
                  selected: {_externalTray},
                  onSelectionChanged: (s) =>
                      setState(() => _externalTray = s.first),
                ).tagged('spool_assign.extruder'),
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
                      // A `DropdownMenu` re-seeds its field from
                      // `initialSelection` only when the new value is among
                      // its entries (`didUpdateWidget`) — and switching
                      // printer is exactly when it is not, because the valid
                      // unit range changed with it. A fresh element is what
                      // stops the field naming the previous printer's unit.
                      key: ValueKey(_printerId),
                      id: 'spool_assign.unit',
                      label: l10n.inventoryAssignUnit,
                      value: _amsUnit,
                      // Display 1-based, value is unit id.
                      items: {for (final u in unitOptions) u: '${u + 1}'},
                      onChanged: (v) => setState(() => _amsUnit = v),
                    ),
                  ),
                  const SizedBox(width: DashSpace.md),
                  Expanded(
                    child: _NumberDropdown(
                      id: 'spool_assign.slot',
                      label: l10n.inventoryAssignSlot,
                      value: _amsSlot,
                      items: {for (var s = 0; s < 4; s++) s: '${s + 1}'},
                      onChanged: (v) => setState(() => _amsSlot = v),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: DashSpace.xl),

            FilledButton.icon(
              onPressed: _saving || _printerId == null ? null : _assign,
              icon: _saving
                  ? DashSpinner(color: t.onAccent)
                  : const Icon(Icons.add_link, size: 18),
              label: Text(l10n.inventoryAssignConfirm),
            ).tagged('spool_assign.save'),
          ],
        ],
      ),
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
      amsId: _external ? externalHolderUnit : _amsUnit,
      trayId: _external ? _externalTray : _amsSlot,
    );
    setState(() => _saving = true);
    try {
      await ref.read(inventoryProvider.notifier).assignSpool(draft);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.snack(l10n.inventorySpoolAssigned);
    } on AppApiException catch (e) {
      if (mounted) setState(() => _saving = false);
      showApiFailure(
        mounted ? messenger : null,
        e,
        l10n,
        action: 'spool_assign.save',
      );
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.snack(l10n.inventoryActionFailed);
    }
  }
}

/// Numeric dropdown (label above field) — int with display label map.
class _NumberDropdown extends StatelessWidget {
  const _NumberDropdown({
    super.key,
    required this.id,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  /// Log identifier for the field; each option gets `<id>.<value>`. The options
  /// live in a popup route of their own, so the field's identifier does not
  /// reach them — untagged, picking an AMS slot recorded as a bare `menuItem`.
  final String id;

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
        const SizedBox(height: DashSpace.sm),
        dashCombo<int>(
          context,
          id: id,
          initialSelection: value,
          onSelected: (v) => v == null ? null : onChanged(v),
          entries: [
            for (final e in items.entries)
              DropdownMenuEntry(
                value: e.key,
                label: e.value,
                // Named by value, not shared across the options: which AMS unit
                // and slot the user picked is the whole point of the record, and
                // a slot number is the printer's, not the user's.
                labelWidget: logTag('$id.${e.key}', Text(e.value)),
              ),
          ],
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
      spacing: DashSpace.sm,
      runSpacing: DashSpace.sm,
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
        ).tagged('spool_actions.edit'),
        _ActionPill(
          tokens: t,
          onPressed: () {
            Navigator.of(context).pop();
            openSpoolForm(context, copyOf: spool);
          },
          icon: Icons.copy_outlined,
          label: l10n.inventoryDuplicate,
        ).tagged('spool_actions.duplicate'),
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
                logId: 'spool_actions.unassign',
              ),
              icon: Icons.link_off,
              label: l10n.inventoryUnassign,
            ).tagged('spool_actions.unassign')
          else
            _ActionPill(
              tokens: t,
              onPressed: () {
                Navigator.of(context).pop();
                _openAssignSheet(context, spool);
              },
              icon: Icons.add_link,
              label: l10n.inventoryAssign,
            ).tagged('spool_actions.assign'),
        // Gated on the counter, not on lifetime use: a spool whose counter is
        // already at zero has nothing to reset, however much filament it has
        // been through.
        if (spool.consumedWeight > 0)
          _ActionPill(
            tokens: t,
            variant: _ActionPillVariant.warning,
            onPressed: () => _resetUsage(context, ref, l10n),
            icon: Icons.refresh,
            label: l10n.inventoryResetUsage,
          ).tagged('spool_actions.reset_usage'),
        if (spool.isArchived)
          _ActionPill(
            tokens: t,
            onPressed: () => _run(
              context,
              ref,
              l10n,
              ref.read(inventoryProvider.notifier).restoreSpool(spool.id),
              l10n.inventorySpoolRestored,
              logId: 'spool_actions.restore',
            ),
            icon: Icons.unarchive_outlined,
            label: l10n.inventoryRestore,
          ).tagged('spool_actions.restore')
        else
          _ActionPill(
            tokens: t,
            variant: _ActionPillVariant.secondary,
            onPressed: () => _run(
              context,
              ref,
              l10n,
              ref.read(inventoryProvider.notifier).archiveSpool(spool.id),
              l10n.inventorySpoolArchived,
              logId: 'spool_actions.archive',
            ),
            icon: Icons.archive_outlined,
            label: l10n.inventoryArchive,
          ).tagged('spool_actions.archive'),
        _ActionPill(
          tokens: t,
          variant: _ActionPillVariant.destructive,
          onPressed: () => _delete(context, ref, l10n),
          icon: Icons.delete_outline,
          label: l10n.inventoryDelete,
        ).tagged('spool_actions.delete'),
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
      id: 'spool.reset_usage_confirm',
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
      logId: 'spool_actions.reset_usage',
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final ok = await confirmDialog(
      context,
      id: 'spool.delete_confirm',
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
      logId: 'spool_actions.delete',
    );
  }

  /// Closes sheet, waits for [action], reports result to parent ScaffoldMessenger
  /// (captured before pop, since sheet context disappears).
  ///
  /// [logId] is the pill that was tapped: five actions share this runner, and a
  /// tag chosen here instead would report all five as one.
  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Future<void> action,
    String successMsg, {
    required String logId,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    try {
      await action;
      messenger.snack(successMsg);
    } on AppApiException catch (e) {
      showApiFailure(messenger, e, l10n, action: logId);
    } on Object {
      messenger.snack(l10n.inventoryActionFailed);
    }
  }
}

enum _ActionPillVariant { primary, outline, secondary, warning, destructive }

/// Small pill action button used in the spool detail sheet's action row.
/// [primary] (Edit) is filled with a tinted accent; the rest are outlined:
/// [outline] in the accent (the default), [secondary] (Archive), [warning]
/// (Reset usage) and [destructive] (Delete) each in their own color.
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
    final (color, outline) = switch (variant) {
      _ActionPillVariant.primary => (tokens.accentGreenInk, null),
      _ActionPillVariant.outline => (tokens.accentGreenInk, tokens.accentGreen),
      _ActionPillVariant.secondary => (
        tokens.textSecondary,
        tokens.textSecondary,
      ),
      _ActionPillVariant.warning => (
        tokens.accentOrangeInk,
        tokens.accentOrange,
      ),
      _ActionPillVariant.destructive => (tokens.dangerInk, tokens.danger),
    };
    final fill = variant == _ActionPillVariant.primary
        ? tokens.accentGreen.withValues(alpha: 0.16)
        : Colors.transparent;
    final border = outline == null
        ? null
        : Border.all(color: outline.withValues(alpha: 0.4));

    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: DashSpace.lg,
            vertical: DashSpace.md,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: border,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: DashSpace.sm),
              Text(
                label,
                style: DashTokens.of(context).label.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
