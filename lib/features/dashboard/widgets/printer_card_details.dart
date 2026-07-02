part of 'printer_card.dart';

/// Plate-clear banner: shown only when the scheduler requires plate-clear
/// confirmation AND this printer still has a finished job on the plate. The
/// button posts the same `clear-plate` acknowledgement used before queued
/// starts, freeing the scheduler to dispatch the next print.
class _PlateClearBanner extends ConsumerStatefulWidget {
  const _PlateClearBanner({required this.printerId, required this.status});

  final int printerId;
  final PrinterStatus status;

  @override
  ConsumerState<_PlateClearBanner> createState() => _PlateClearBannerState();
}

class _PlateClearBannerState extends ConsumerState<_PlateClearBanner> {
  bool _busy = false;

  Future<void> _clear() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(printerCommandsRepositoryProvider)
          .clearPlate(widget.printerId);
      messenger.showSnackBar(SnackBar(content: Text(l10n.plateClearedSnack)));
    } on AppApiException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is AuthException && e.code == AppErrorCode.forbidden
                ? l10n.ctrlForbidden
                : l10n.ctrlFailed,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.status.awaitingPlateClear != true) {
      return const SizedBox.shrink();
    }
    // Only relevant when the server actually gates on plate-clear.
    final require = ref.watch(requirePlateClearProvider).valueOrNull ?? false;
    if (!require) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.layers_clear_outlined,
              size: 20,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.plateClearBadge,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : _clear,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.plateClearAction),
            ),
          ],
        ),
      ),
    );
  }
}

/// Active HMS errors panel: red border, each error with readable description
/// (from Bambu catalog or fallback "level · module"), canonical code, and—
/// when the full code can be composed—link to Bambu wiki.
class _HmsErrorsPanel extends StatelessWidget {
  const _HmsErrorsPanel({required this.errors});

  final List<HmsError> errors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.error.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
              const SizedBox(width: 6),
              Text(
                l10n.hmsErrorsHeader,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.error,
                ),
              ),
            ],
          ),
          for (final e in errors) _HmsErrorRow(error: e),
        ],
      ),
    );
  }
}

class _HmsErrorRow extends StatelessWidget {
  const _HmsErrorRow({required this.error});

  final HmsError error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final label = hmsLabel(
      error,
      description: HmsCatalog.instance.describe(error),
      l10n: l10n,
    );
    final url = hmsWikiUrl(error);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Text(label, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 2),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  error.displayCode,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                  ),
                ),
              ),
              if (url != null)
                InkWell(
                  onTap: () => unawaited(
                    launchUrl(
                      Uri.parse(url),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.hmsViewInWiki,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.open_in_new,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Clickable "Details ▾" bar expanding AMS/connectivity section.
class _DetailsToggle extends StatelessWidget {
  const _DetailsToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final scheme = theme.colorScheme;
    final color = scheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Ink(
        decoration: BoxDecoration(
          // Subtle contrast from card background — same tone as chips/tiles.
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              expanded ? l10n.detailsHide : l10n.detailsShow,
              style: theme.textTheme.labelLarge?.copyWith(color: color),
            ),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.expand_more, size: 20, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Expanded details section: AMS units with colored slots,
/// external spool, and connectivity metadata (model, Wi-Fi, door state).
class _DetailsPanel extends ConsumerWidget {
  const _DetailsPanel({required this.status});

  final PrinterStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ams = status.ams ?? const [];
    final spools = status.externalSpools;
    // Actually loaded filament (on the active extruder)—highlight this one
    // regardless of list order.
    final active = status.activeTray;
    final dual = status.isDualExtruder;
    final activeExtruder = status.activeExtruder;
    // Spools from inventory assigned to this printer's slots—to show exact
    // remaining weight (printer only reports %, external spools report nothing).
    final assigned = ref.watch(assignedSpoolsProvider(status.id));

    final printerId = status.id;
    final printerName = status.name;

    final sections = <Widget>[
      for (var i = 0; i < ams.length; i++)
        _AmsUnitView(
          unit: ams[i],
          unitIndex: i,
          active: active,
          // On dual extruder, show which extruder feeds this unit.
          extruder: dual ? (status.amsExtruderMap?[ams[i].id]) : null,
          activeExtruder: activeExtruder,
          assigned: assigned,
          printerId: printerId,
          printerName: printerName,
        ),
      if (spools.isNotEmpty)
        _TraySection(
          title: l10n.externalSpool,
          trays: spools,
          active: active,
          // Spool→extruder mapping from id (inverse order: 254→left).
          extruderOf: dual
              ? (i) => status.extruderForExternal(spools[i].id)
              : (_) => null,
          activeExtruder: activeExtruder,
          // External spool feeding a given extruder (dual); on single extruder
          // treat as "left" (extruder 1)—see resolver.
          assignedOf: (i) => assigned.forExtruder(
            dual ? status.extruderForExternal(spools[i].id) : 1,
          ),
          // tray_id for external assignment: extruder 1 (left)→0, 0 (right)→1;
          // single extruder→0. amsId=255 (inventory convention).
          trayIdOf: (i) {
            if (!dual) return 0;
            return status.extruderForExternal(spools[i].id) == 1 ? 0 : 1;
          },
          printerId: printerId,
          printerName: printerName,
        ),
    ];

    final info = _InfoRow(status: status);

    // Uniform 10px spacing above first section (from "Details" bar) and between
    // sections—consistent rhythm with the rest of the card.
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            sections[i],
          ],
          const SizedBox(height: 10),
          info,
        ],
      ),
    );
  }
}

/// One AMS unit: header (number + extruder + humidity + temperature) and slots.
/// [active] is the actually loaded tray instance (from model)—compared by identity,
/// so exactly one is highlighted.
class _AmsUnitView extends StatelessWidget {
  const _AmsUnitView({
    required this.unit,
    required this.unitIndex,
    required this.active,
    required this.extruder,
    required this.activeExtruder,
    required this.assigned,
    required this.printerId,
    required this.printerName,
  });

  final AmsUnit unit;
  final int unitIndex;
  final AmsTray? active;
  final int? extruder;
  final int? activeExtruder;
  final AssignedSpools assigned;
  final int printerId;
  final String? printerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final scheme = theme.colorScheme;
    final color = scheme.onSurfaceVariant;
    final trays = unit.trays ?? const [];

    // Distinguish the AMS unit as a separate "card": darker background than slot
    // chips (surfaceContainerHigh), so slots visually pop above the unit block,
    // and the AMS reads as a cohesive group distinct from external spools.
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dns_outlined, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                l10n.amsUnit(unitIndex + 1),
                style: theme.textTheme.labelLarge,
              ),
              if (extruder != null) ...[
                const SizedBox(width: 6),
                _ExtruderBadge(
                  extruder: extruder!,
                  active: extruder == activeExtruder,
                ),
              ],
              const Spacer(),
              if (unit.humidity != null)
                _MetaItem(
                  icon: Icons.water_drop_outlined,
                  text: '${unit.humidity}%',
                  onTap: () => showAmsHistorySheet(
                    context,
                    printerId: printerId,
                    amsId: unit.id ?? unitIndex,
                    amsLabel: l10n.amsUnit(unitIndex + 1),
                    initialMetric: AmsHistoryMetric.humidity,
                  ),
                ),
              if (unit.humidity != null && unit.temp != null)
                const SizedBox(width: 12),
              if (unit.temp != null)
                _MetaItem(
                  icon: Icons.thermostat,
                  text: '${unit.temp!.toStringAsFixed(0)}°',
                  onTap: () => showAmsHistorySheet(
                    context,
                    printerId: printerId,
                    amsId: unit.id ?? unitIndex,
                    amsLabel: l10n.amsUnit(unitIndex + 1),
                    initialMetric: AmsHistoryMetric.temperature,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in trays)
                _TrayChip(
                  tray: t,
                  active: identical(t, active),
                  assignedSpool: assigned.forAmsSlot(
                    unit.id ?? unitIndex,
                    t.id ?? 0,
                  ),
                  slot: _SlotRef(
                    printerId: printerId,
                    printerName: printerName,
                    amsId: unit.id ?? unitIndex,
                    trayId: t.id ?? 0,
                    label:
                        '${l10n.amsUnit(unitIndex + 1)} · ${(t.id ?? 0) + 1}',
                  ),
                ),
            ],
          ),
          if (trays.isEmpty)
            Text('—', style: theme.textTheme.bodySmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// Tray section with title (e.g., external spool). [extruderOf] maps index to
/// extruder (on dual), [active] is the actually loaded tray.
class _TraySection extends StatelessWidget {
  const _TraySection({
    required this.title,
    required this.trays,
    required this.active,
    required this.extruderOf,
    required this.activeExtruder,
    required this.assignedOf,
    required this.trayIdOf,
    required this.printerId,
    required this.printerName,
  });

  final String title;
  final List<AmsTray> trays;
  final AmsTray? active;
  final int? Function(int index) extruderOf;
  final int? activeExtruder;
  final Spool? Function(int index) assignedOf;
  final int Function(int index) trayIdOf;
  final int printerId;
  final String? printerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < trays.length; i++)
              _TrayChip(
                tray: trays[i],
                active: identical(trays[i], active),
                extruder: extruderOf(i),
                activeExtruder: activeExtruder,
                // External spool: printer doesn't measure fill (no RFID like genuine
                // Bambu filament in AMS)—don't show %.
                allowRemain: false,
                assignedSpool: assignedOf(i),
                slot: _SlotRef(
                  printerId: printerId,
                  printerName: printerName,
                  amsId: 255,
                  trayId: trayIdOf(i),
                  label: switch (extruderOf(i)) {
                    1 => l10n.extruderLeft,
                    0 => l10n.extruderRight,
                    _ => title,
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Single slot chip: optional extruder badge + color dot + material + qty.
/// Active (loaded) tray gets a border.
class _TrayChip extends StatelessWidget {
  const _TrayChip({
    required this.tray,
    required this.active,
    this.extruder,
    this.activeExtruder,
    this.allowRemain = true,
    this.assignedSpool,
    this.slot,
  });

  final AmsTray tray;
  final bool active;
  final int? extruder;
  final int? activeExtruder;

  /// Whether to show fill % at all (AMS only—external spool has no reliable measurement).
  final bool allowRemain;

  /// Spool from inventory assigned to this slot—gives exact remaining weight in grams
  /// (supplements/replaces the printer's rough %). Null = none assigned.
  final Spool? assignedSpool;

  /// Slot identification (printer/AMS/tray)—when provided, tapping the chip opens
  /// the assignment sheet for THIS slot. Null → chip not tappable.
  final _SlotRef? slot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final empty = tray.isEmpty;
    final dotColor = empty ? null : _parseTrayColor(tray.trayColor);

    final label = empty
        ? l10n.traySlotEmpty
        : (tray.materialLabel ?? l10n.traySlotEmpty);
    final remain = tray.remain;
    final showRemain = allowRemain && !empty && remain != null && remain >= 0;
    // Exact grams from assigned spool (only for occupied slots).
    final spool = empty ? null : assignedSpool;
    final grams = spool == null
        ? null
        : l10n.inventoryUsageWeight(spool.remainingWeight.toStringAsFixed(0));

    final text = [label, if (showRemain) '$remain%', ?grams].join(' · ');

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: active
            ? Border.all(color: scheme.primary, width: 1.5)
            : Border.all(color: Colors.transparent, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (extruder != null) ...[
            _ExtruderBadge(
              extruder: extruder!,
              active: extruder == activeExtruder,
            ),
            const SizedBox(width: 6),
          ],
          _ColorDot(color: dotColor),
          const SizedBox(width: 6),
          Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              color: empty ? scheme.onSurfaceVariant : scheme.onSurface,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );

    final slot = this.slot;
    final tappable = slot == null
        ? chip
        : InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => _AssignSlotSheet(slot: slot),
            ),
            child: chip,
          );

    // Assigned spool name in tooltip (chip shows material + grams only).
    return spool == null
        ? tappable
        : Tooltip(message: spool.displayName, child: tappable);
  }
}

/// Physical slot identification for spool assignment from chip.
class _SlotRef {
  const _SlotRef({
    required this.printerId,
    required this.printerName,
    required this.amsId,
    required this.trayId,
    required this.label,
  });

  final int printerId;
  final String? printerName;
  final int amsId;
  final int trayId;

  /// Readable slot label (e.g., "AMS 1 · 2" or "Left extruder").
  final String label;
}

/// "Assign spool to this slot" sheet opened from AMS/spool chip. Slot is known
/// from chip context, so user picks ONLY the spool. Shows current assignment
/// (with unassign option) and list of active spools from inventory.
class _AssignSlotSheet extends ConsumerWidget {
  const _AssignSlotSheet({required this.slot});

  final _SlotRef slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final inv = ref.watch(inventoryProvider).valueOrNull;
    final spools = inv?.spools ?? const <Spool>[];

    // Spool currently assigned to exactly this slot (if any).
    Spool? current;
    for (final s in spools) {
      final a = inv?.assignmentFor(s.id);
      if (a != null &&
          a.printerId == slot.printerId &&
          a.amsId == slot.amsId &&
          a.trayId == slot.trayId) {
        current = s;
        break;
      }
    }

    // Available: active spools (no archived), excluding current assignment.
    // Sort: unassigned spools first, then by remaining qty (use up scraps first).
    bool assignedElsewhere(Spool s) => inv?.assignmentFor(s.id) != null;
    final options =
        [
          for (final s in spools)
            if (!s.isArchived && s.id != current?.id) s,
        ]..sort((a, b) {
          final ga = assignedElsewhere(a) ? 1 : 0;
          final gb = assignedElsewhere(b) ? 1 : 0;
          if (ga != gb) return ga - gb;
          return a.remainingWeight.compareTo(b.remainingWeight);
        });

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(l10n.inventoryAssignTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            [?slot.printerName, slot.label].join(' · '),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          if (current != null) ...[
            Text(
              l10n.inventoryAssignCurrent,
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: SpoolSwatch(rgba: current.rgba),
              title: Text(current.displayName),
              subtitle: current.remainingFraction != null
                  ? Text(
                      l10n.inventoryRemaining(
                        current.remainingWeight.toStringAsFixed(0),
                      ),
                    )
                  : null,
              trailing: TextButton.icon(
                onPressed: () => _unassign(context, ref, l10n),
                icon: const Icon(Icons.link_off, size: 18),
                label: Text(l10n.inventoryUnassign),
              ),
            ),
            const Divider(height: 24),
          ],

          Text(l10n.inventoryAssignPick, style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          if (options.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                l10n.inventoryEmpty,
                style: theme.textTheme.bodyMedium,
              ),
            )
          else
            for (final s in options)
              Builder(
                builder: (context) {
                  // Where spool currently sits (if in another slot)—will be moved
                  // from there upon selection (after confirmation).
                  final from = inv?.assignmentFor(s.id);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: SpoolSwatch(rgba: s.rgba),
                    title: Text(s.displayName),
                    subtitle: Text(
                      [
                        if (s.remainingFraction != null)
                          l10n.inventoryRemaining(
                            s.remainingWeight.toStringAsFixed(0),
                          ),
                        '#${s.id}',
                        if (from != null)
                          [
                            ?from.printerName,
                            assignmentSlotLabel(l10n, from),
                          ].join(' '),
                      ].join(' · '),
                    ),
                    trailing: from != null
                        ? const Icon(Icons.swap_horiz, size: 20)
                        : null,
                    onTap: () => _assign(context, ref, l10n, s, from: from),
                  );
                },
              ),
        ],
      ),
    );
  }

  Future<void> _assign(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Spool spool, {
    SpoolAssignment? from,
  }) async {
    final messenger = ScaffoldMessenger.of(context);

    // Spool already in another slot → confirm move (unassign from there).
    if (from != null) {
      final fromLabel = [
        ?from.printerName,
        assignmentSlotLabel(l10n, from),
      ].join(' · ');
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.inventoryReassignTitle),
          content: Text(l10n.inventoryReassignMessage(fromLabel)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.inventoryReassignAction),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
    }

    Navigator.of(context).pop();
    try {
      await ref
          .read(inventoryProvider.notifier)
          .assignSpool(
            SpoolAssignmentDraft(
              spoolId: spool.id,
              printerId: slot.printerId,
              amsId: slot.amsId,
              trayId: slot.trayId,
            ),
            from: from,
          );
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.inventorySpoolAssigned)),
      );
    } on AppApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.localized(l10n))));
    } on Object {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.inventoryActionFailed)),
      );
    }
  }

  Future<void> _unassign(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    try {
      await ref
          .read(inventoryProvider.notifier)
          .unassignSpool(slot.printerId, slot.amsId, slot.trayId);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.inventorySpoolUnassigned)),
      );
    } on AppApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.localized(l10n))));
    } on Object {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.inventoryActionFailed)),
      );
    }
  }
}

/// Small extruder badge for dual-extruder machines: icon + side (L/R—left/right).
/// Mapping per contract: extruder 1 = left, 0 = right (verified live: AMS →
/// extruder 1 = left). Active extruder in accent color, others dimmed.
class _ExtruderBadge extends StatelessWidget {
  const _ExtruderBadge({required this.extruder, required this.active});

  final int extruder;
  final bool active;

  bool get _isLeft => extruder == 1;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    final short = _isLeft ? l10n.extruderLeftShort : l10n.extruderRightShort;
    return Tooltip(
      message: _isLeft ? l10n.extruderLeft : l10n.extruderRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.print_outlined, size: 13, color: color),
          const SizedBox(width: 2),
          Text(
            short,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Circle in filament color; empty/unknown slot → crossed-out outline.
class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (color == null) {
      return Icon(Icons.circle_outlined, size: 14, color: scheme.outline);
    }
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outlineVariant, width: 0.5),
      ),
    );
  }
}
