part of 'printer_card.dart';

/// Plate-clear banner: shown only when the scheduler requires plate-clear
/// confirmation AND this printer still has a finished job on the plate. The
/// button posts the `clear-plate` acknowledgement, freeing the scheduler.
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
    final require = ref.watch(requirePlateClearProvider).valueOrNull ?? false;
    if (!require) return const SizedBox.shrink();

    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: t.accentBlue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.accentBlue.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.layers_clear_outlined, size: 20, color: t.accentBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.plateClearBadge,
                style: TextStyle(
                  fontFamily: DashTokens.fontUi,
                  fontSize: 13,
                  color: t.textPrimary,
                ),
              ),
            ),
            logTag(
              'printer.plate_clear',
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
            ),
          ],
        ),
      ),
    );
  }
}

/// Active HMS errors panel: red-bordered card with readable description, code,
/// and a wiki link when the full code can be composed.
class _HmsErrorsPanel extends StatelessWidget {
  const _HmsErrorsPanel({required this.errors});

  final List<HmsError> errors;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
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
                style: TextStyle(
                  fontFamily: DashTokens.fontUi,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
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
    final t = DashTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final label = hmsLabel(
      error,
      description: HmsCatalog.instance.describe(error),
    );
    final url = hmsWikiUrl(error);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Text(
              label,
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 13,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  error.displayCode,
                  style: TextStyle(
                    fontFamily: DashTokens.fontMono,
                    fontSize: 11.5,
                    color: t.textTertiary,
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
                        style: TextStyle(
                          fontFamily: DashTokens.fontUi,
                          fontSize: 11.5,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.open_in_new, size: 14, color: scheme.primary),
                    ],
                  ),
                ).tagged('printer.open_url'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Full-width "Details ▾ / ▴" toggle button expanding the AMS/connectivity section.
class _DetailsToggle extends StatelessWidget {
  const _DetailsToggle({
    required this.expanded,
    required this.onTap,
    required this.id,
  });

  final bool expanded;
  final VoidCallback onTap;

  /// Name for the diagnostic log; the visible label is localized and is not
  /// recorded.
  final String id;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: t.subCard,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: logTag(
          id,
          InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: t.subCardBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    expanded ? l10n.detailsHide : l10n.detailsShow,
                    style: TextStyle(
                      fontFamily: DashTokens.fontUi,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: t.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more,
                        size: 18, color: t.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Expanded details section: AMS unit(s) and external spool as list rows inside
/// a grouping card, followed by the connectivity (Wi-Fi/door) row.
class _DetailsPanel extends ConsumerWidget {
  const _DetailsPanel({required this.status});

  final PrinterStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final ams = status.ams ?? const [];
    final spools = status.externalSpools;
    final active = status.activeTray;
    final dual = status.isDualExtruder;
    final activeExtruder = status.activeExtruder;
    final assigned = ref.watch(assignedSpoolsProvider(status.id));
    final printerId = status.id;
    final printerName = status.name;

    final blocks = <Widget>[
      for (var i = 0; i < ams.length; i++)
        _AmsSection(
          unit: ams[i],
          unitIndex: i,
          active: active,
          extruder: dual ? (status.amsExtruderMap?[ams[i].id]) : null,
          activeExtruder: activeExtruder,
          assigned: assigned,
          printerId: printerId,
          printerName: printerName,
          supportsDrying: status.supportsDrying ?? false,
        ),
      if (spools.isNotEmpty)
        _SpoolSection(
          trays: spools,
          active: active,
          extruderOf:
              dual ? (i) => status.extruderForExternal(spools[i].id) : (_) => null,
          assignedOf: (i) => assigned.forExtruder(
            dual ? status.extruderForExternal(spools[i].id) : 1,
          ),
          trayIdOf: (i) {
            if (!dual) return 0;
            return status.extruderForExternal(spools[i].id) == 1 ? 0 : 1;
          },
          printerId: printerId,
          printerName: printerName,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (blocks.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              decoration: BoxDecoration(
                color: t.groupCard,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: t.groupCardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < blocks.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    blocks[i],
                  ],
                ],
              ),
            ),
          // Connectivity row (has its own top hairline + spacing).
          _InfoRow(status: status),
        ],
      ),
    );
  }
}

/// One AMS unit as a titled list: header (unit + extruder + humidity/temp),
/// then a filament row per slot.
class _AmsSection extends StatelessWidget {
  const _AmsSection({
    required this.unit,
    required this.unitIndex,
    required this.active,
    required this.extruder,
    required this.activeExtruder,
    required this.assigned,
    required this.printerId,
    required this.printerName,
    required this.supportsDrying,
  });

  final AmsUnit unit;
  final int unitIndex;
  final AmsTray? active;
  final int? extruder;
  final int? activeExtruder;
  final AssignedSpools assigned;
  final int printerId;
  final String? printerName;
  final bool supportsDrying;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final trays = unit.trays ?? const <AmsTray>[];

    final metaParts = <Widget>[];
    if (unit.humidity != null) {
      metaParts.add(_AmsMeta(
        icon: Icons.water_drop_outlined,
        text: '${unit.humidity}%',
        onTap: () => showAmsHistorySheet(
          context,
          printerId: printerId,
          amsId: unit.id ?? unitIndex,
          amsLabel: l10n.amsUnit(unitIndex + 1),
          initialMetric: AmsHistoryMetric.humidity,
        ),
      ));
    }
    if (unit.temp != null) {
      metaParts.add(_AmsMeta(
        icon: Icons.thermostat,
        text: '${unit.temp!.toStringAsFixed(0)}°',
        onTap: () => showAmsHistorySheet(
          context,
          printerId: printerId,
          amsId: unit.id ?? unitIndex,
          amsLabel: l10n.amsUnit(unitIndex + 1),
          initialMetric: AmsHistoryMetric.temperature,
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.amsUnit(unitIndex + 1).toUpperCase(),
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: t.textPrimary,
              ),
            ),
            if (extruder != null) ...[
              const SizedBox(width: 8),
              _ExtruderBadge(
                  extruder: extruder!, active: extruder == activeExtruder),
            ],
            const Spacer(),
            for (var i = 0; i < metaParts.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              metaParts[i],
            ],
            // Only AMS 2 Pro / AMS-HT modules can dry — hide the control on
            // regular AMS even when the printer supports drying.
            if (supportsDrying && unit.canDry) ...[
              const SizedBox(width: 12),
              _AmsDryControl(
                printerId: printerId,
                amsId: unit.id ?? unitIndex,
                amsLabel: l10n.amsUnit(unitIndex + 1),
                unit: unit,
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        if (trays.isEmpty)
          Text('—',
              style: TextStyle(fontFamily: DashTokens.fontMono, color: t.textTertiary))
        else
          for (var i = 0; i < trays.length; i++)
            _FilamentRow(
              tray: trays[i],
              active: identical(trays[i], active),
              assignedSpool: assigned.forAmsSlot(
                unit.id ?? unitIndex,
                trays[i].id ?? 0,
              ),
              allowRemain: true,
              last: i == trays.length - 1,
              slot: _SlotRef(
                printerId: printerId,
                printerName: printerName,
                amsId: unit.id ?? unitIndex,
                trayId: trays[i].id ?? 0,
                label: '${l10n.amsUnit(unitIndex + 1)} · ${(trays[i].id ?? 0) + 1}',
              ),
            ),
      ],
    );
  }
}

/// External spool section (design "SZPULA ZEWNĘTRZNA"): title + one row per spool,
/// each prefixed with its extruder side on dual machines.
class _SpoolSection extends StatelessWidget {
  const _SpoolSection({
    required this.trays,
    required this.active,
    required this.extruderOf,
    required this.assignedOf,
    required this.trayIdOf,
    required this.printerId,
    required this.printerName,
  });

  final List<AmsTray> trays;
  final AmsTray? active;
  final int? Function(int index) extruderOf;
  final Spool? Function(int index) assignedOf;
  final int Function(int index) trayIdOf;
  final int printerId;
  final String? printerName;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.externalSpool.toUpperCase(),
          style: TextStyle(
            fontFamily: DashTokens.fontUi,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < trays.length; i++)
          _FilamentRow(
            tray: trays[i],
            active: identical(trays[i], active),
            assignedSpool: assignedOf(i),
            allowRemain: false,
            last: i == trays.length - 1,
            sidePrefix: switch (extruderOf(i)) {
              1 => l10n.extruderLeftShort,
              0 => l10n.extruderRightShort,
              _ => null,
            },
            slot: _SlotRef(
              printerId: printerId,
              printerName: printerName,
              amsId: 255,
              trayId: trayIdOf(i),
              label: switch (extruderOf(i)) {
                1 => l10n.extruderLeft,
                0 => l10n.extruderRight,
                _ => l10n.externalSpool,
              },
            ),
          ),
      ],
    );
  }
}

/// One filament list row: color dot + (side prefix) material on the left,
/// weight/fill on the right, tappable to assign a spool. Active (loaded) row is
/// accent-colored with a solid accent underline; other rows use a dotted rule.
class _FilamentRow extends StatelessWidget {
  const _FilamentRow({
    required this.tray,
    required this.active,
    required this.allowRemain,
    required this.last,
    this.sidePrefix,
    this.assignedSpool,
    this.slot,
  });

  final AmsTray tray;
  final bool active;
  final bool allowRemain;
  final bool last;
  final String? sidePrefix;
  final Spool? assignedSpool;
  final _SlotRef? slot;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final empty = tray.isEmpty;
    final dotColor = empty ? null : _parseTrayColor(tray.trayColor);

    final material =
        empty ? l10n.traySlotEmpty : (tray.materialLabel ?? l10n.traySlotEmpty);
    final label = sidePrefix == null ? material : '$sidePrefix · $material';

    final remain = tray.remain;
    final showRemain = allowRemain && !empty && remain != null && remain >= 0;
    final spool = empty ? null : assignedSpool;
    final grams = spool == null
        ? null
        : l10n.inventoryUsageWeight(spool.remainingWeight.toStringAsFixed(0));
    final trailing = [if (showRemain) '$remain%', ?grams].join(' · ');

    final textColor = active ? t.accentGreenInk : t.textSecondary;

    final row = Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          _ColorDot(color: dotColor, size: 9),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: DashTokens.fontMono,
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
          if (trailing.isNotEmpty)
            Text(
              trailing,
              style: TextStyle(
                fontFamily: DashTokens.fontMono,
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                color: active ? t.accentGreenInk : t.textSecondary,
              ),
            ),
        ],
      ),
    );

    // Separator under the row (except the last): solid accent when active,
    // otherwise a dotted hairline.
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        if (!last)
          active
              ? Container(height: 1, color: t.accentGreen)
              : _DashedLine(color: t.dottedRule)
        else if (active)
          Container(height: 1, color: t.accentGreen),
        if (!last) const SizedBox(height: 7),
      ],
    );

    final slot = this.slot;
    final tappable = slot == null
        ? content
        : logTagMaterial(
            'printer.ams_slot',
            tray.trayType,
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => _AssignSlotSheet(slot: slot),
              ),
              child: content,
            ),
          );

    return spool == null
        ? tappable
        : Tooltip(message: spool.displayName, child: tappable);
  }
}

/// Tappable humidity/temperature metadata in the AMS header (opens history).
class _AmsMeta extends StatelessWidget {
  const _AmsMeta({required this.icon, required this.text, required this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: t.textTertiary),
            const SizedBox(width: 4),
            Text(
              text,
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
    ).tagged('printer.ams_meta');
  }
}

/// AMS header dry control: a compact chip. While drying it shows the remaining
/// time in the accent-orange heat colour; idle it reads "Dry". Tapping opens
/// [_DryingSheet]. Hidden when control is forbidden.
class _AmsDryControl extends ConsumerWidget {
  const _AmsDryControl({
    required this.printerId,
    required this.amsId,
    required this.amsLabel,
    required this.unit,
  });

  final int printerId;
  final int amsId;
  final String amsLabel;
  final AmsUnit unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final forbidden = ref.watch(controlsProvider.select((s) => s.forbidden));
    if (forbidden) return const SizedBox.shrink();

    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final drying = unit.isDrying;
    final remain = unit.dryTime ?? 0;
    final color = drying ? t.accentOrange : t.textTertiary;
    final label =
        drying && remain > 0 ? _durationText(l10n, remain) : l10n.ctrlDry;

    return InkWell(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _DryingSheet(
          printerId: printerId,
          amsId: amsId,
          amsLabel: amsLabel,
          unit: unit,
        ),
      ),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              drying ? Icons.local_fire_department : Icons.wb_sunny_outlined,
              size: 13,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: DashTokens.fontMono,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    ).tagged('printer.drying');
  }
}

/// Bottom sheet to start/stop AMS drying for one unit. While a cycle runs it
/// shows the remaining time and a Stop button; idle it offers temperature
/// (45–85 °C) and duration (1–24 h) pickers and a Start button. Filament is
/// backfilled server-side from the loaded tray.
class _DryingSheet extends ConsumerStatefulWidget {
  const _DryingSheet({
    required this.printerId,
    required this.amsId,
    required this.amsLabel,
    required this.unit,
  });

  final int printerId;
  final int amsId;
  final String amsLabel;
  final AmsUnit unit;

  @override
  ConsumerState<_DryingSheet> createState() => _DryingSheetState();
}

/// Recommended drying temp/duration per filament, mirroring the bambuddy
/// frontend's DRYING_PRESETS. `n3*` = regular AMS module, `ht*` = AMS-HT
/// (high-temp) module; picked via [AmsUnit.isAmsHt].
typedef _DryPreset = ({int temp, int htTemp, int hours, int htHours});
const _dryingPresets = <String, _DryPreset>{
  'PLA': (temp: 45, htTemp: 45, hours: 12, htHours: 12),
  'PETG': (temp: 65, htTemp: 65, hours: 12, htHours: 12),
  'TPU': (temp: 65, htTemp: 75, hours: 12, htHours: 18),
  'ABS': (temp: 65, htTemp: 80, hours: 12, htHours: 8),
  'ASA': (temp: 65, htTemp: 80, hours: 12, htHours: 8),
  'PA': (temp: 65, htTemp: 85, hours: 12, htHours: 12),
  'PC': (temp: 65, htTemp: 80, hours: 12, htHours: 8),
  'PVA': (temp: 65, htTemp: 85, hours: 12, htHours: 18),
};

class _DryingSheetState extends ConsumerState<_DryingSheet> {
  static const _durationPresets = [4, 6, 8, 12];

  String _filament = 'PLA';
  int _temp = 55;
  int _hours = 4;
  bool _busy = false;

  /// AMS-HT tops out at 85 °C; AMS 2 Pro at 65 °C.
  bool get _isHt => widget.unit.isHtDryModule;
  int get _maxTemp => _isHt ? 85 : 65;
  List<int> get _tempPresets => _isHt ? const [45, 65, 75, 85] : const [45, 55, 65];

  @override
  void initState() {
    super.initState();
    _applyFilament(_filament); // seed temp/duration from the default filament
  }

  /// Selecting a filament sets the recommended temp + duration for this AMS
  /// module type (AMS 2 Pro vs AMS-HT). The user can still fine-tune the sliders.
  void _applyFilament(String filament) {
    final p = _dryingPresets[filament];
    setState(() {
      _filament = filament;
      if (p != null) {
        _temp = (_isHt ? p.htTemp : p.temp).clamp(45, _maxTemp);
        _hours = (_isHt ? p.htHours : p.hours).clamp(1, 24);
      }
    });
  }

  Future<void> _run(Future<ControlResult> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final result = await action();
    if (!mounted) return;
    navigator.pop();
    final msg = switch (result) {
      ControlResult.ok => null,
      ControlResult.forbidden => l10n.ctrlForbidden,
      ControlResult.error => l10n.ctrlFailed,
    };
    if (msg != null) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final drying = widget.unit.isDrying;

    return logTag(
      'sheet.drying',
      SafeArea(
        top: false,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: t.overlaySurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: t.subCardBorder)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: t.textTertiary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          l10n.ctrlDry,
                          style: TextStyle(
                            fontFamily: DashTokens.fontUi,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: t.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          widget.amsLabel,
                          style: TextStyle(
                            fontFamily: DashTokens.fontUi,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: t.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (drying)
                      ..._runningBody(t, l10n)
                    else
                      ..._setupBody(t, l10n),
                  ],
                ),
              ),
            ],
          ),
        ),
      )
    );
  }

  List<Widget> _runningBody(DashTokens t, AppLocalizations l10n) {
    final remain = widget.unit.dryTime ?? 0;
    return [
      Center(
        child: Column(
          children: [
            Icon(Icons.local_fire_department, size: 32, color: t.accentOrange),
            const SizedBox(height: 8),
            Text(
              remain > 0 ? _durationText(l10n, remain) : l10n.ctrlDrying,
              style: TextStyle(
                fontFamily: DashTokens.fontMono,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: t.accentOrange,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _SheetButton(
        label: l10n.ctrlStop,
        id: 'drying.stop',
        busy: _busy,
        onTap: _busy
            ? null
            : () => _run(() => ref
                .read(controlsProvider.notifier)
                .stopDrying(widget.printerId, amsId: widget.amsId)),
      ),
    ];
  }

  List<Widget> _setupBody(DashTokens t, AppLocalizations l10n) => [
        DropdownMenu<String>(
          initialSelection: _filament,
          expandedInsets: EdgeInsets.zero,
          menuHeight: 280,
          requestFocusOnTap: false,
          label: Text(l10n.ctrlDryFilament),
          textStyle: TextStyle(
            fontFamily: DashTokens.fontUi,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: t.textPrimary,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: t.subCard,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.subCardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.subCardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: t.accentGreen),
            ),
          ),
          onSelected: (v) {
            if (v != null) _applyFilament(v);
          },
          dropdownMenuEntries: [
            // Preset keys are Bambu material names, so the pick rides in the
            // `mat` field instead of turning the identifier into content.
            for (final f in _dryingPresets.keys)
              DropdownMenuEntry(
                value: f,
                label: f,
                labelWidget:
                    logTagMaterial('drying.filament_option', f, Text(f)),
              ),
          ],
        ).tagged('drying.filament'),
        const SizedBox(height: 16),
        _DrySlider(
          id: 'drying.temp',
          label: l10n.ctrlDryTemp,
          valueText: '$_temp°',
          value: _temp,
          min: 45,
          max: _maxTemp,
          presets: _tempPresets,
          presetLabel: (p) => '$p°',
          onChanged: (v) => setState(() => _temp = v),
        ),
        const SizedBox(height: 16),
        _DrySlider(
          id: 'drying.hours',
          label: l10n.ctrlDryDuration,
          valueText: l10n.ctrlDryHours(_hours),
          value: _hours,
          min: 1,
          max: 24,
          presets: _durationPresets,
          presetLabel: (p) => l10n.ctrlDryHours(p),
          onChanged: (v) => setState(() => _hours = v),
        ),
        const SizedBox(height: 20),
        _SheetButton(
          label: l10n.ctrlDryStart,
          id: 'drying.start',
          filled: true,
          busy: _busy,
          onTap: _busy
              ? null
              : () => _run(() => ref.read(controlsProvider.notifier).startDrying(
                    widget.printerId,
                    amsId: widget.amsId,
                    temp: _temp,
                    duration: _hours,
                    filament: _filament,
                  )),
        ),
      ];
}

/// Labelled value + slider (with −/+ steppers and presets) used twice in the
/// drying sheet (temperature and duration).
class _DrySlider extends StatelessWidget {
  const _DrySlider({
    required this.id,
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.presets,
    required this.presetLabel,
    required this.onChanged,
  });

  /// Diagnostic prefix for this row's controls (`drying.temp` →
  /// `drying.temp_slider`, `drying.temp_preset`, …). The drying sheet builds two
  /// of these rows, so a tag baked into the widget could not say whether the
  /// user changed the temperature or the hours.
  final String id;

  final String label;
  final String valueText;
  final int value;
  final int min;
  final int max;
  final List<int> presets;
  final String Function(int) presetLabel;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    int clamp(int v) => v.clamp(min, max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: t.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              valueText,
              style: TextStyle(
                fontFamily: DashTokens.fontMono,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: t.textPrimary,
              ),
            ),
          ],
        ),
        Row(
          children: [
            _StepButton(
              icon: Icons.remove,
              id: '${id}_step_down',
              onTap: () => onChanged(clamp(value - 1)),
            ),
            Expanded(
              child: Slider(
                value: value.clamp(min, max).toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                activeColor: t.accentOrange,
                onChanged: (v) => onChanged(v.round()),
              ).tagged('${id}_slider'),
            ),
            _StepButton(
              icon: Icons.add,
              id: '${id}_step_up',
              onTap: () => onChanged(clamp(value + 1)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in presets)
              _PresetChip(
                label: presetLabel(p),
                id: '${id}_preset',
                selected: value == p,
                onTap: () => onChanged(p),
              ),
          ],
        ),
      ],
    );
  }
}

/// Thin dotted horizontal rule between filament rows.
class _DashedLine extends StatelessWidget {
  const _DashedLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(double.infinity, 1), painter: _DashedPainter(color));
}

class _DashedPainter extends CustomPainter {
  _DashedPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 2.0;
    const gap = 3.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) => old.color != color;
}

/// Physical slot identification for spool assignment from a row.
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

/// "Assign spool to this slot" sheet opened from a filament row. Slot is known
/// from context, so the user picks ONLY the spool. Shows the current assignment
/// (with unassign) and the list of active spools from inventory.
class _AssignSlotSheet extends ConsumerWidget {
  const _AssignSlotSheet({required this.slot});

  final _SlotRef slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final inv = ref.watch(inventoryProvider).valueOrNull;
    final spools = inv?.spools ?? const <Spool>[];

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

    bool assignedElsewhere(Spool s) => inv?.assignmentFor(s.id) != null;
    final options = [
      for (final s in spools)
        if (!s.isArchived && s.id != current?.id) s,
    ]..sort((a, b) {
        final ga = assignedElsewhere(a) ? 1 : 0;
        final gb = assignedElsewhere(b) ? 1 : 0;
        if (ga != gb) return ga - gb;
        return a.remainingWeight.compareTo(b.remainingWeight);
      });

    return logTag(
      'sheet.assign_spool',
      DraggableScrollableSheet(
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
              Text(l10n.inventoryAssignCurrent, style: theme.textTheme.labelLarge),
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
                ).taggedMaterial('assign_spool.unassign', current.material),
              ),
              const Divider(height: 24),
            ],
            Text(l10n.inventoryAssignPick, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            if (options.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(l10n.inventoryEmpty, style: theme.textTheme.bodyMedium),
              )
            else
              for (final s in options)
                Builder(
                  builder: (context) {
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
                    ).taggedMaterial('assign_spool.option', s.material);
                  },
                ),
          ],
        ),
      )
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
    if (from != null) {
      final fromLabel = [
        ?from.printerName,
        assignmentSlotLabel(l10n, from),
      ].join(' · ');
      final ok = await confirmDialog(
        context,
        title: l10n.inventoryReassignTitle,
        message: l10n.inventoryReassignMessage(fromLabel),
        confirmLabel: l10n.inventoryReassignAction,
        id: 'spool_reassign',
      );
      if (!ok || !context.mounted) return;
    }

    Navigator.of(context).pop();
    try {
      await ref.read(inventoryProvider.notifier).assignSpool(
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

/// Small extruder badge for dual-extruder machines: icon + side (L/R). Active
/// extruder in accent color, others dimmed.
class _ExtruderBadge extends StatelessWidget {
  const _ExtruderBadge({required this.extruder, required this.active});

  final int extruder;
  final bool active;

  bool get _isLeft => extruder == 1;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final color = active ? t.accentGreenInk : t.textTertiary;
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
              fontFamily: DashTokens.fontMono,
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
  const _ColorDot({required this.color, this.size = 14});

  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    if (color == null) {
      return Icon(Icons.circle_outlined, size: size + 3, color: t.textTertiary);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: t.hairline, width: 0.5),
      ),
    );
  }
}
