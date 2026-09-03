part of 'printer_card.dart';

/// Plate-clear banner: the phone's door to the acknowledgement. When it is
/// offered, and why an unreachable printer is offered it too, is
/// [plateClearOffered]; the button posts the `clear-plate` acknowledgement,
/// freeing the scheduler.
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
    // Read out with the messenger, and for the same reason: the answer can land
    // after this banner is gone (the printer reconnects and the card swaps
    // layout, or the dashboard is left), and `ref` throws once that happens.
    final gate = ref.read(offlinePlateClearProvider.notifier);
    setState(() => _busy = true);
    try {
      await ref
          .read(printerCommandsRepositoryProvider)
          .clearPlate(widget.printerId);
      ref
          .read(printerStatusesProvider.notifier)
          .plateGateAcknowledged(widget.printerId);
      messenger.snack(l10n.plateClearedSnack);
    } on AppApiException catch (e) {
      showApiFailure(
        messenger,
        e,
        l10n,
        action: 'printer.plate_clear',
        message: recordPlateClearRefusal(gate, e.detail)
            ? l10n.plateClearNeedsOnline
            : null,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!plateClearOffered(ref, widget.status)) {
      return const SizedBox.shrink();
    }

    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
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
                style: t.bodyPlain.copyWith(color: t.textPrimary),
              ),
            ),
            // A checkmark rather than the full "mark plate as cleared": the
            // sentence spelled the badge next to it out twice and left the badge
            // itself two words wide on a 360 dp screen. The wording survives as
            // the tooltip, which is also what a screen reader announces. Being
            // disabled is how the card's other network buttons say "in flight"
            // (see `_SmartPlugButton`), so no spinner of its own.
            _HeaderIconButton(
              id: 'printer.plate_clear',
              icon: Icons.check_rounded,
              tooltip: l10n.plateClearAction,
              color: t.accentBlue,
              borderColor: t.accentBlue.withValues(alpha: 0.5),
              onPressed: _busy ? null : _clear,
            ),
          ],
        ),
      ),
    );
  }
}

/// Active HMS errors panel: red-bordered, collapsed to a count until tapped.
///
/// Collapsed is the default even mid-fault — an error card that expands itself
/// pushes the print progress and the controls below the fold on a phone, and
/// the count in the header already says how bad it is.
class _HmsErrorsPanel extends ConsumerStatefulWidget {
  const _HmsErrorsPanel({
    required this.printerId,
    required this.printerName,
    required this.errors,
  });

  final int printerId;
  final String printerName;
  final List<HmsError> errors;

  @override
  ConsumerState<_HmsErrorsPanel> createState() => _HmsErrorsPanelState();
}

class _HmsErrorsPanelState extends ConsumerState<_HmsErrorsPanel> {
  bool _expanded = false;

  Future<void> _dismissAll() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(controlsProvider.notifier)
        .clearHmsErrors(widget.printerId);
    if (!mounted) return;
    messenger.snack(result.messageFor(l10n) ?? l10n.hmsDismissed, clearQueue: true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final busy = ref
        .watch(controlsProvider)
        .pendingFor(widget.printerId)
        .inFlight
        .contains(ControlAction.hms);
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
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.hmsErrorsCount(widget.errors.length),
                    style: DashTokens.of(context).bodyBold.copyWith(color: scheme.error),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: scheme.error,
                ),
              ],
            ),
          ).tagged('printer.hms_expand'),
          if (_expanded) ...[
            for (final e in widget.errors)
              // Keyed by the fault, not by position: a frame arriving while a
              // command is in the air (the server holds the request 2.5s
              // waiting for the printer) can drop an error from the middle of
              // the list, and an unkeyed card would keep its neighbour's
              // in-flight spinner.
              _HmsErrorCard(
                key: ValueKey(e.fullCode ?? e.displayCode),
                printerId: widget.printerId,
                printerName: widget.printerName,
                error: e,
                busy: busy,
              ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: logTag(
                'printer.hms_dismiss_all',
                TextButton.icon(
                  onPressed: busy ? null : _dismissAll,
                  icon: const Icon(Icons.done_all, size: 18),
                  label: Text(l10n.hmsDismissAll),
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One fault: what it is, its code, a wiki link, and the buttons its firmware
/// offers for it.
class _HmsErrorCard extends ConsumerStatefulWidget {
  const _HmsErrorCard({
    super.key,
    required this.printerId,
    required this.printerName,
    required this.error,
    required this.busy,
  });

  final int printerId;
  final String printerName;
  final HmsError error;

  /// Another HMS command is in the air for this printer — every button waits,
  /// not just the one that was tapped.
  final bool busy;

  @override
  ConsumerState<_HmsErrorCard> createState() => _HmsErrorCardState();
}

class _HmsErrorCardState extends ConsumerState<_HmsErrorCard> {
  /// The action this card is waiting on, so the spinner sits on the button the
  /// user actually pressed rather than on all of them.
  String? _pending;

  /// Bambu writes for the printer's own screen, where a fault gets a dialog to
  /// itself — half its descriptions run past 100 characters and one reaches
  /// 330. Two lines is what the card can spend on each fault when several are
  /// reported at once; the rest is a tap away.
  bool _fullText = false;

  Future<void> _run(String action) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (action == hmsStopAction) {
      final confirmed = await confirmDialog(
        context,
        title: l10n.hmsStopConfirmTitle,
        message: l10n.hmsStopConfirmBody(widget.printerName),
        confirmLabel: l10n.hmsStopConfirmAction,
        destructive: true,
        id: 'printer.hms_stop_confirm',
      );
      if (!confirmed || !mounted) return;
    }
    setState(() => _pending = action);
    final result = await ref.read(controlsProvider.notifier).executeHmsAction(
          widget.printerId,
          printError: widget.error.fullCode!,
          action: action,
          jobId: widget.error.jobId,
        );
    if (mounted) setState(() => _pending = null);
    // Told through the messenger captured before the await, not through this
    // widget: the card is gone precisely when the command worked and the fault
    // cleared, and that is the outcome most worth reporting.
    messenger.snack(_resultText(result, l10n), clearQueue: true);
  }

  /// A 502 here is not a broken server: the command went out and the printer
  /// never answered, which the user can only resolve at the machine.
  String _resultText(ActionOutcome result, AppLocalizations l10n) =>
      switch (result) {
        ActionFailed(:final error) when error.statusCode == 502 =>
          l10n.hmsActionNotAcknowledged,
        _ => result.messageFor(l10n) ?? l10n.hmsActionSent,
      };

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final error = widget.error;
    final label = hmsLabel(
      error,
      description: HmsCatalog.instance.describe(error),
    );
    final url = hmsWikiUrl(error);
    // No `full_code`, no action: the server (pre-0.2.4.8) cannot tell the
    // firmware which fault a command is about, and a guessed code is dropped.
    final actions = error.fullCode == null
        ? const <String>[]
        : hmsRenderableActions(error.actions);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        // Its own tile inside the red panel: with several faults reported at
        // once, one unbroken column of text and buttons reads as a single long
        // error rather than as three separate things to decide about.
        color: t.subCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.subCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            InkWell(
              onTap: () => setState(() => _fullText = !_fullText),
              child: Text(
                label,
                maxLines: _fullText ? null : 2,
                overflow: _fullText ? null : TextOverflow.ellipsis,
                style: t.bodyPlain.copyWith(color: t.textPrimary, height: 1.25),
              ),
            ).tagged('printer.hms_description'),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  error.displayCode,
                  style: t.monoMicro,
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
                        style: t.microSoft.copyWith(color: scheme.primary),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.open_in_new, size: 14, color: scheme.primary),
                    ],
                  ),
                ).tagged('printer.open_url'),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            // A row per fault, not a button per line: the labels are short
            // enough that three fit across a phone, and Wrap still breaks
            // rather than overflowing when a translation or a font scale makes
            // them wider.
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final action in actions)
                  // One id per action, not one for the whole row: the log has
                  // to tell "resumed" from "stopped the print". Safe to
                  // interpolate — the key comes from `hmsEffectiveActions`, a
                  // fixed vocabulary, never from anything the user typed.
                  logTag(
                    'printer.hms_${action.toLowerCase()}',
                    FilledButton.tonal(
                      onPressed: widget.busy ? null : () => _run(action),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        minimumSize: const Size(0, 34),
                        textStyle: const TextStyle(
                          fontFamily: DashTokens.fontUi,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                        backgroundColor: action == hmsStopAction
                            ? scheme.errorContainer
                            : null,
                        foregroundColor: action == hmsStopAction
                            ? scheme.onErrorContainer
                            : null,
                      ),
                      child: _pending == action
                          ? const DashSpinner(size: 14)
                          : Text(hmsActionLabel(l10n, action)),
                    ),
                  ),
              ],
            ),
          ],
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
                    style: t.label.copyWith(color: t.textSecondary),
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
    // The 0/1 side the external holder is addressed by everywhere ids are
    // local — the slot routes, the inventory assignment and the load command.
    int trayIdOf(int i) => externalSideOf(spools[i].id) ?? 0;

    final blocks = <Widget>[
      for (var i = 0; i < ams.length; i++)
        _AmsSection(
          unit: ams[i],
          unitIndex: i,
          active: active,
          // The badge names a fixed side, so only a real `ams_extruder_map`
          // entry may fill it. A unit bound to a Filament Track Switch reaches
          // both nozzles and has none — [PrinterStatus.extruderForSlot] still
          // resolves it through the inlet, but that is where the slot rests
          // between prints, not a side to label the unit with.
          extruder: dual ? (status.amsExtruderMap?[ams[i].id]) : null,
          slotExtruder:
              dual ? status.extruderForSlot(ams[i].id ?? i, 0) : null,
          activeExtruder: activeExtruder,
          assigned: assigned,
          printerId: printerId,
          printerName: printerName,
          supportsDrying: status.supportsDrying ?? false,
          printing: status.isPrinting && !status.isPaused,
          nozzleDiameter: status.nozzleDiameterFor(ams[i].id ?? i, 0),
          printerModel: status.model,
          filaSwitch: status.filaSwitch,
          fedFrom: status.extruderSlots,
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
          trayIdOf: trayIdOf,
          printerId: printerId,
          printerName: printerName,
          printing: status.isPrinting && !status.isPaused,
          // The external holder is keyed under a unit no `ams_extruder_map`
          // mentions — the tray side is the whole answer there, so it has to be
          // asked per spool rather than per section.
          nozzleDiameterOf: (i) =>
              status.nozzleDiameterFor(externalHolderUnit, trayIdOf(i)),
          printerModel: status.model,
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
///
/// The humidity/temperature readings open their history chart, but only where
/// the server keeps one and this session may read it — otherwise they stay as
/// plain readings.
class _AmsSection extends ConsumerWidget {
  const _AmsSection({
    required this.unit,
    required this.unitIndex,
    required this.active,
    required this.extruder,
    required this.slotExtruder,
    required this.activeExtruder,
    required this.assigned,
    required this.printerId,
    required this.printerName,
    required this.supportsDrying,
    required this.printing,
    required this.nozzleDiameter,
    required this.printerModel,
    required this.filaSwitch,
    required this.fedFrom,
  });

  final AmsUnit unit;
  final int unitIndex;
  final AmsTray? active;

  /// The side to badge the unit with — a real `ams_extruder_map` entry only.
  final int? extruder;

  /// The nozzle this unit's slots currently rest on, which on a Filament Track
  /// Switch machine is known even when [extruder] is not. Travels to the slot
  /// configuration sheet, where it tells the printer's two calibration tables
  /// apart.
  final int? slotExtruder;
  final int? activeExtruder;
  final AssignedSpools assigned;
  final int printerId;
  final String? printerName;
  final bool supportsDrying;
  final bool printing;

  /// Nozzle this unit feeds, and the printer's model code — both travel to the
  /// slot configuration sheet, which needs them to filter presets and to name
  /// the calibration context.
  final String? nozzleDiameter;
  final String? printerModel;

  /// The Filament Track Switch and the hotend/slot pairing, for the load
  /// question the slot sheet has to ask when one is fitted — see [_SlotRef].
  final FilaSwitch? filaSwitch;
  final Map<int, ExtruderSlot>? fedFrom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final trays = unit.trays ?? const <AmsTray>[];
    final history = ref
        .watch(amsHistorySupportedProvider)
        .maybeWhen(data: (v) => v, orElse: () => false);

    VoidCallback? openHistory(AmsHistoryMetric metric) => history
        ? () => showAmsHistorySheet(
              context,
              printerId: printerId,
              amsId: unit.id ?? unitIndex,
              amsLabel: l10n.amsUnit(unitIndex + 1),
              initialMetric: metric,
            )
        : null;

    final metaParts = <Widget>[];
    if (unit.humidity != null) {
      metaParts.add(_AmsMeta(
        icon: Icons.water_drop_outlined,
        text: '${unit.humidity}%',
        onTap: openHistory(AmsHistoryMetric.humidity),
      ));
    }
    if (unit.temp != null) {
      metaParts.add(_AmsMeta(
        icon: Icons.thermostat,
        text: '${unit.temp!.toStringAsFixed(0)}°',
        onTap: openHistory(AmsHistoryMetric.temperature),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.amsUnit(unitIndex + 1).toUpperCase(),
              style: t.bodyBold.copyWith(color: t.textPrimary, letterSpacing: 0.4),
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
        // Under the header rather than beside the flame chip: a pending run has
        // a sentence to say (when, and what it is waiting for) and the chip is
        // one word wide.
        if (supportsDrying && unit.canDry)
          _ScheduledDryingBanner(
            printerId: printerId,
            amsId: unit.id ?? unitIndex,
            drying: unit.isDrying,
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
                printing: printing,
                loadTrayId: amsLoadTrayId(
                  amsId: unit.id ?? unitIndex,
                  trayId: trays[i].id ?? 0,
                ),
                canRereadRfid: true,
                tagUid: trays[i].tagUid,
                trayUuid: trays[i].trayUuid,
                trayInfoIdx: trays[i].trayInfoIdx,
                trayColour: trays[i].trayColor,
                caliIdx: trays[i].caliIdx,
                nozzleDiameter: nozzleDiameter,
                printerModel: printerModel,
                extruderId: slotExtruder,
                filaSwitch: filaSwitch,
                fedFrom: fedFrom,
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
    required this.printing,
    required this.nozzleDiameterOf,
    required this.printerModel,
  });

  final List<AmsTray> trays;
  final AmsTray? active;
  final int? Function(int index) extruderOf;
  final Spool? Function(int index) assignedOf;
  final int Function(int index) trayIdOf;
  final int printerId;
  final String? printerName;
  final bool printing;
  final String? Function(int index) nozzleDiameterOf;
  final String? printerModel;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.externalSpool.toUpperCase(),
          style: t.label.copyWith(color: t.textPrimary, letterSpacing: 0.4),
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
              amsId: externalHolderUnit,
              trayId: trayIdOf(i),
              label: switch (extruderOf(i)) {
                1 => l10n.extruderLeft,
                0 => l10n.extruderRight,
                _ => l10n.externalSpool,
              },
              printing: printing,
              loadTrayId: amsLoadTrayId(
                amsId: externalHolderUnit,
                trayId: trayIdOf(i),
              ),
              trayInfoIdx: trays[i].trayInfoIdx,
              trayColour: trays[i].trayColor,
              caliIdx: trays[i].caliIdx,
              nozzleDiameter: nozzleDiameterOf(i),
              printerModel: printerModel,
              extruderId: extruderOf(i),
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
              : DashedLine(color: t.dottedRule)
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
              onTap: () => dashSheet<void>(
                context,
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

  /// Null where there is no history to open — the chip stays as a reading.
  final VoidCallback? onTap;

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
              style: t.monoLabel,
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
    final forbidden =
        ref.watch(controlRefusedProvider(ControlPermission.control));
    if (forbidden) return const SizedBox.shrink();

    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final drying = unit.isDrying;
    final remain = unit.dryTime ?? 0;
    final color = drying ? t.accentOrange : t.textTertiary;
    final label =
        drying && remain > 0 ? formatMinutes(l10n, remain) : l10n.ctrlDry;

    return InkWell(
      onTap: () {
        // The sheet decides whether to offer the "later" modes from what the
        // listing last answered, so this is the moment to ask again: a server
        // that gained the route (or a session that gained the permission)
        // otherwise stays without them until the dashboard is pulled down.
        ref.invalidate(scheduledDryingsProvider);
        dashSurfaceSheet<void>(
          context,
          builder: (_) => _DryingSheet(
            printerId: printerId,
            amsId: amsId,
            amsLabel: amsLabel,
            unit: unit,
          ),
        );
      },
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
              style: t.monoLabel.copyWith(color: color),
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

class _DryingSheetState extends ConsumerState<_DryingSheet> {
  static const _durationPresets = [4, 6, 8, 12];

  String _filament = 'PLA';
  int _temp = 55;
  int _hours = 4;
  bool _busy = false;

  /// The table the pickers seed from — the server's own, or the bundled
  /// fallback until its settings have arrived.
  Map<String, DryPreset> _presets = defaultDryingPresets;

  /// Whether anything here has been chosen by hand. The server's table can land
  /// after this sheet opened — on a cold start it usually does — and it is
  /// adopted then, but only while this is false: a table arriving under the
  /// user's finger must not move a temperature they have just set.
  bool _touched = false;

  DryStartMode _startMode = DryStartMode.now;
  int _delayMinutes = 60;

  /// Chosen in [DryStartMode.atTime]; null until the picker has run once.
  DateTime? _startAt;

  /// AMS-HT tops out at 85 °C; AMS 2 Pro at 65 °C.
  bool get _isHt => widget.unit.isHtDryModule;
  int get _maxTemp => _isHt ? 85 : 65;
  List<int> get _tempPresets => _isHt ? const [45, 65, 75, 85] : const [45, 55, 65];

  @override
  void initState() {
    super.initState();
    // Directly, not through `setState`: this runs before the first build.
    _adopt(ref.read(dryingPresetsProvider));
  }

  /// Takes [presets] as the table to seed from, and re-seeds the pickers.
  void _adopt(Map<String, DryPreset> presets) {
    _presets = presets;
    // A table the server configured need not contain PLA — open on the first
    // filament it does have, so the dropdown always has its own value in it.
    if (!_presets.containsKey(_filament)) {
      _filament = _presets.keys.firstOrNull ?? _filament;
    }
    _applyFilament(_filament);
  }

  /// Selecting a filament sets the recommended temp + duration for this AMS
  /// module type (AMS 2 Pro vs AMS-HT). The user can still fine-tune the
  /// sliders. Callers own the `setState`, because two of them also have to
  /// record that the choice was the user's.
  ///
  /// A preset above what the module can reach is clamped rather than offered:
  /// the server validates 45-85 °C whatever the module is, while an AMS 2 Pro
  /// stops at 65, so a table configured for AMS-HT must not send a temperature
  /// this hardware cannot hold.
  void _applyFilament(String filament) {
    final p = _presets[filament];
    _filament = filament;
    if (p != null) {
      _temp = (_isHt ? p.htTemp : p.temp).clamp(45, _maxTemp);
      _hours = (_isHt ? p.htHours : p.hours).clamp(1, 24);
    }
  }

  Future<void> _run(Future<ActionOutcome> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final result = await action();
    if (!mounted) return;
    navigator.pop();
    final msg = result.messageFor(l10n);
    if (msg != null) {
      messenger.snack(msg, clearQueue: true);
    }
  }

  /// Hands the run to the server's scheduler instead of the printer.
  ///
  /// The sheet stays open until the server answers, and closes on the way out.
  /// The handles are still taken first, because the user can dismiss it under
  /// the request — see [detachFrom].
  Future<void> _schedule(DateTime startAfter) async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final (:providers, :messenger) = detachFrom(context);
    final repository = providers.read(scheduledDryingRepositoryProvider);
    setState(() => _busy = true);
    try {
      await repository.create(
        printerId: widget.printerId,
        amsId: widget.amsId,
        temp: _temp,
        durationHours: _hours,
        filament: _filament,
        startAfter: startAfter,
      );
      providers.invalidate(scheduledDryingsProvider);
      if (mounted) navigator.pop();
      messenger.snack(l10n.ctrlDryScheduled, clearQueue: true);
    } on AppApiException catch (e) {
      showApiFailure(mounted ? messenger : null, e, l10n,
          action: 'drying.schedule');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// No `firstDate`: a run can only be scheduled forward, so today is the
  /// earliest day worth showing.
  Future<void> _pickStartAt() async {
    final picked = await pickDateTime(context, initial: _startAt);
    if (picked == null || !mounted) return;
    setState(() => _startAt = picked);
  }

  @override
  Widget build(BuildContext context) {
    // The server's settings are fetched once per session and can land after
    // this sheet opened — see [_touched].
    ref.listen(dryingPresetsProvider, (_, next) {
      if (!_touched) setState(() => _adopt(next));
    });

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
              // Scrollable, and `Flexible` so a short sheet still ends where
              // its content does: filament, two sliders, the start-time picker
              // and the button are more than a 360×640 screen has room for at a
              // large system text size, and a sheet that overflows hides its
              // own Start button.
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            l10n.ctrlDry,
                            style: t.titleLg,
                          ),
                          const Spacer(),
                          Text(
                            widget.amsLabel,
                            style: t.body.copyWith(color: t.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Above both bodies: it explains a running cycle nobody
                      // started just as much as it explains one about to be.
                      const _AutoDryingNote(),
                      if (drying)
                        ..._runningBody(t, l10n)
                      else
                        ..._setupBody(t, l10n),
                    ],
                  ),
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
              remain > 0 ? formatMinutes(l10n, remain) : l10n.ctrlDrying,
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
        dashCombo<String>(
          context,
          id: 'drying.filament',
          initialSelection: _filament,
          menuHeight: 280,
          label: Text(l10n.ctrlDryFilament),
          textStyle: t.bodyStrong,
          // Tighter than the form chrome: this one sits inside a card, where
          // the 14 px radius and the taller field read as a second card.
          decorationTheme: InputDecorationTheme(
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
            if (v == null) return;
            setState(() {
              _touched = true;
              _applyFilament(v);
            });
          },
          entries: [
            // Preset keys are Bambu material names, so the pick rides in the
            // `mat` field instead of turning the identifier into content.
            for (final f in _presets.keys)
              DropdownMenuEntry(
                value: f,
                label: f,
                labelWidget:
                    logTagMaterial('drying.filament_option', f, Text(f)),
              ),
          ],
        ),
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
          onChanged: (v) => setState(() {
            _touched = true;
            _temp = v;
          }),
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
          onChanged: (v) => setState(() {
            _touched = true;
            _hours = v;
          }),
        ),
        ..._startWhen(l10n),
        const SizedBox(height: 20),
        // Two buttons rather than one with a chosen id: an identifier picked by
        // an expression is invisible to the scan that keeps the log's action
        // tags pointing at real controls (`action_tag_vocabulary_test`).
        if (_startMode == DryStartMode.now)
          _SheetButton(
            label: l10n.ctrlDryStart,
            id: 'drying.start',
            filled: true,
            busy: _busy,
            onTap: _busy ? null : _submit,
          )
        else
          _SheetButton(
            label: l10n.ctrlDrySchedule,
            id: 'drying.schedule',
            filled: true,
            busy: _busy,
            onTap: _busy ? null : _submit,
          ),
      ];

  /// The start-time picker, on a server that has somewhere to put a schedule.
  ///
  /// Before any answer the sheet shows nothing rather than a picker that could
  /// vanish under the user's finger; the listing behind it runs whenever a
  /// drying-capable card is built, so by the time this sheet opens it has
  /// almost always answered. `valueOrNull`, not a `data` match: opening the
  /// sheet re-asks, and a picker that blinked out during that refresh would be
  /// the very thing this is avoiding.
  List<Widget> _startWhen(AppLocalizations l10n) {
    final offered =
        ref.watch(scheduledDryingSupportedProvider).valueOrNull ?? false;
    if (!offered) return const [];
    return [
      const SizedBox(height: 16),
      _DryStartPicker(
        mode: _startMode,
        delayMinutes: _delayMinutes,
        at: _startAt,
        onMode: (v) => setState(() => _startMode = v),
        onDelay: (v) => setState(() => _delayMinutes = v),
        onPickTime: _pickStartAt,
      ),
    ];
  }

  /// Start now, or schedule — one button, because the mode above it already
  /// says which of the two it is.
  void _submit() {
    final l10n = AppLocalizations.of(context);
    final start = dryingStart(
      mode: _startMode,
      delayMinutes: _delayMinutes,
      at: _startAt,
    );
    final problem = start.problem;
    if (problem != null) {
      ScaffoldMessenger.of(context).snack(
        switch (problem) {
          DryingStartProblem.noTimePicked => l10n.ctrlDryPickTime,
          DryingStartProblem.timeInPast => l10n.ctrlDryScheduleTimePast,
        },
        clearQueue: true,
      );
      return;
    }
    final startAfter = start.startAfter;
    if (startAfter == null) {
      _run(() => ref.read(controlsProvider.notifier).startDrying(
            widget.printerId,
            amsId: widget.amsId,
            temp: _temp,
            duration: _hours,
            filament: _filament,
          ));
      return;
    }
    _schedule(startAfter);
  }
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
              style: t.body.copyWith(color: t.textSecondary),
            ),
            const Spacer(),
            Text(
              valueText,
              style: t.monoTitle,
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
                // Without it a reader announces the position as a percentage
                // ("25%"), which says nothing about a dryer: the same wording
                // the presets carry is what the value means.
                semanticFormatterCallback: (v) => presetLabel(v.round()),
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

/// Physical slot identification for spool assignment from a row.
class _SlotRef {
  const _SlotRef({
    required this.printerId,
    required this.printerName,
    required this.amsId,
    required this.trayId,
    required this.label,
    required this.printing,
    this.loadTrayId,
    this.canRereadRfid = false,
    this.tagUid,
    this.trayUuid,
    this.trayInfoIdx,
    this.trayColour,
    this.caliIdx,
    this.nozzleDiameter,
    this.printerModel,
    this.extruderId,
    this.filaSwitch,
    this.fedFrom,
  });

  final int printerId;
  final String? printerName;
  final int amsId;
  final int trayId;

  /// Readable slot label (e.g., "AMS 1 · 2" or "Left extruder").
  final String label;

  /// Whether a job is actively running on this printer. A paused one does not
  /// count: swapping a run-out spool is the reason people pause. Read from the
  /// status the card already renders rather than from the shared statuses map,
  /// so the slot the user tapped and the state that disables it come from one
  /// frame.
  final bool printing;

  /// Global tray number for the load command, or null where the slot cannot be
  /// addressed by it (AMS-HT) — see [amsLoadTrayId].
  final int? loadTrayId;

  /// Whether the slot has a tag to re-read. False for external spools: they
  /// have no RFID reader, and the web hides the action there too.
  final bool canRereadRfid;

  /// RFID identity of the spool sitting in the slot, for matching it against
  /// the inventory and for [canRegisterSpool].
  ///
  /// Left null for external spools even when the firmware reports a tag: the
  /// route that registers a slot looks it up in the printer's `ams` array, and
  /// an external spool is reported outside it, so it could only ever answer
  /// "slot is empty"
  /// (`backend/app/api/routes/inventory.py::create_spool_from_slot`).
  final String? tagUid;
  final String? trayUuid;

  /// Whether a spool can be created out of what this slot holds. Needs a
  /// readable tag — a tagless slot has no identity to re-link to, so the
  /// server refuses one rather than mint a fresh row per confirm.
  bool get canRegisterSpool =>
      normalizeTrayUuid(trayUuid).isNotEmpty ||
      normalizeTagUid(tagUid).isNotEmpty;

  /// What the printer currently holds in this slot, for the configuration
  /// sheet: the filament id identifies the preset in force, the colour is what
  /// the picker opens on.
  final String? trayInfoIdx;
  final String? trayColour;

  /// Calibration profile the slot is printing with, so the sheet reopens on it
  /// rather than offering to drop the printer back to its default K.
  final int? caliIdx;

  /// Diameter of the nozzle this slot feeds, or null when the printer has not
  /// reported its nozzles.
  final String? nozzleDiameter;

  /// Short model code, so the picker can hide presets meant for another
  /// printer.
  final String? printerModel;

  /// Nozzle this slot feeds on a dual-extruder printer, null on a single one.
  final int? extruderId;

  /// The printer's Filament Track Switch, null on one without the accessory.
  /// Read from the frame the card is rendering rather than from the shared
  /// statuses map, for the same reason [printing] is: the slot the user tapped
  /// and the question the sheet asks about it come from one frame.
  ///
  /// Left null for the external holder, which never asks the question: its two
  /// tray numbers name the side outright, and a switch cannot be fitted
  /// alongside one anyway.
  final FilaSwitch? filaSwitch;

  /// Which AMS slot each hotend is fed from, keyed by extruder id. Only read to
  /// grey out a hotend that already holds this very slot.
  final Map<int, ExtruderSlot>? fedFrom;

  AmsSlotTarget get configTarget => AmsSlotTarget(
        printerId: printerId,
        amsId: amsId,
        trayId: trayId,
        label: label,
        printerName: printerName,
        printerModel: printerModel,
        nozzleDiameter: nozzleDiameter,
        currentFilamentId: trayInfoIdx,
        currentColour: trayColour,
        currentCaliIdx: caliIdx,
        extruderId: extruderId,
      );
}

/// Printer-side filament actions for one slot: load it, unload whatever is in
/// the extruder, re-read the slot's RFID tag.
///
/// A refused control hides the buttons that needed it — the same rule the drying
/// control follows — and the tag re-read sits behind its own permission, so the
/// two disappear independently. While the printer prints, whatever is left stays
/// visible but disabled: these actions interrupt the filament path, and a job is
/// exactly what they would ruin.
class _SlotActions extends ConsumerWidget {
  const _SlotActions({required this.slot});

  final _SlotRef slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final canDrive =
        !ref.watch(controlRefusedProvider(ControlPermission.control));
    final canReread = slot.canRereadRfid &&
        !ref.watch(controlRefusedProvider(ControlPermission.amsRfid));
    // Load and unload share one gate and one row: both address the slot by its
    // global tray number, so a slot that has none can offer neither.
    final loadTrayId = slot.loadTrayId;
    final canLoad = canDrive && loadTrayId != null;
    // Configuring needs nothing but `printers:control`, so it survives where
    // loading does not: an AMS-HT slot has no global tray number to load by,
    // and the configure route addresses it by unit and slot like any other.
    if (!canDrive && !canReread) return const SizedBox.shrink();

    final busy = ref.watch(controlsProvider
        .select((s) => s.pendingFor(slot.printerId).isBusy(ControlAction.ams)));
    final enabled = !busy && !slot.printing;
    final controls = ref.read(controlsProvider.notifier);

    // Two equal halves and a full-width third, rather than a Wrap: the buttons
    // are three different lengths, and letting them flow left them ragged with
    // a stray one on its own line.
    final load = OutlinedButton.icon(
      onPressed: enabled && canLoad
          ? () => _startLoad(context, l10n, controls, loadTrayId)
          : null,
      icon: const Icon(Icons.login, size: 18),
      label: Text(l10n.amsLoad),
    ).tagged('assign_spool.ams_load');

    final unload = OutlinedButton.icon(
      onPressed: enabled
          ? () => _run(
                context,
                l10n,
                // Naming the slot is what tells two hotends apart: `tray_now` is
                // one value for the whole printer, so an unaddressed unload on a
                // dual-nozzle machine empties whichever hotend that field
                // happens to name, not the slot the sheet is about. A server
                // that does not know the parameter ignores it and keeps the old
                // printer-wide behaviour.
                () => controls.amsUnload(slot.printerId, trayId: loadTrayId),
                l10n.amsUnloadStarted,
                // The one status this route answers for a reason the user can
                // act on, and which "server returned error 409" would hide.
                wordFailure: (e) => e.statusCode == 409
                    ? l10n.amsUnloadSlotNotLoaded
                    : null,
              )
          : null,
      icon: const Icon(Icons.logout, size: 18),
      label: Text(l10n.amsUnload),
    ).tagged('assign_spool.ams_unload');

    final reread = OutlinedButton.icon(
      onPressed: enabled
          ? () => _run(
                context,
                l10n,
                () => controls.refreshAmsSlot(
                  slot.printerId,
                  amsId: slot.amsId,
                  slotId: slot.trayId,
                ),
                l10n.amsRfidRereadStarted,
              )
          : null,
      icon: const Icon(Icons.nfc, size: 18),
      label: Text(l10n.amsRfidReread),
    ).tagged('assign_spool.rfid_reread');

    // Opening the configuration is not itself a command, so it stays available
    // mid-print: reading what a slot is set to is harmless, and the sheet's own
    // buttons are what the job blocks.
    final configure = OutlinedButton.icon(
      onPressed: busy ? null : () => _openConfig(context),
      icon: const Icon(Icons.tune, size: 18),
      label: Text(l10n.amsSlotConfigure),
    ).tagged('assign_spool.configure');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.amsSlotFilament, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        if (canLoad)
          Row(
            children: [
              Expanded(child: load),
              const SizedBox(width: 8),
              Expanded(child: unload),
            ],
          ),
        if (canLoad && canReread) const SizedBox(height: 8),
        if (canReread) reread,
        if (canDrive) ...[
          if (canLoad || canReread) const SizedBox(height: 8),
          configure,
        ],
        if (slot.printing) ...[
          const SizedBox(height: 8),
          Text(
            l10n.amsActionsWhilePrinting,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  /// Swaps this sheet for the slot configuration one. The assignment sheet
  /// closes first so the back gesture returns to the card, not to a list the
  /// user is done with.
  void _openConfig(BuildContext context) {
    Navigator.of(context).pop();
    dashSheet<void>(
      context,
      builder: (_) => AmsSlotConfigSheet(target: slot.configTarget),
    );
  }

  /// Closes the sheet before the command lands: these actions take tens of
  /// seconds at the printer and there is nothing to watch here meanwhile.
  ///
  /// [wordFailure] is for a status this route means something specific by, which
  /// the generic wording would bury; anything it answers null for falls through
  /// to `messageFor`.
  Future<void> _run(
    BuildContext context,
    AppLocalizations l10n,
    Future<ActionOutcome> Function() action,
    String startedMessage, {
    String? Function(ApiException error)? wordFailure,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    final outcome = await action();
    final failure = switch (outcome) {
      ActionFailed(error: final ApiException e) => wordFailure?.call(e),
      _ => null,
    };
    messenger.snack(
      failure ?? outcome.messageFor(l10n) ?? startedMessage,
      clearQueue: true,
    );
  }

  /// Loads the slot, asking which hotend to feed first where that question has
  /// an answer the printer cannot work out for itself.
  ///
  /// Without a Filament Track Switch every AMS is wired to one hotend and the
  /// firmware derives the target, so the command names none. With one fitted the
  /// AMS is bound to a switch inlet instead and both hotends are reachable — the
  /// firmware then has nothing to derive from and drops a command that does not
  /// say where the filament is going. Bambu Studio asks the same question in the
  /// same place.
  Future<void> _startLoad(
    BuildContext context,
    AppLocalizations l10n,
    ControlsNotifier controls,
    int loadTrayId,
  ) async {
    final filaSwitch = slot.filaSwitch;
    // The external holder answers the question by itself — its two tray numbers
    // name the side (254 = Ext-L, 255 = Ext-R) — and a switch cannot be fitted
    // alongside one anyway: it would occupy an extruder channel permanently,
    // which is why Bambu's own guidance is to take the switch off first.
    // An AMS-HT never reaches here at all: it has no global tray number, so the
    // button is hidden rather than disabled.
    final asks = (filaSwitch?.installed ?? false) && slot.amsId != 255;
    if (!asks) {
      await _run(
        context,
        l10n,
        () => controls.amsLoad(slot.printerId, loadTrayId),
        l10n.amsLoadStarted,
      );
      return;
    }
    if (!filaSwitch!.ready) {
      // Nothing can be routed until every AMS is bound to an inlet, so say so
      // rather than send a command the firmware would drop whatever hotend it
      // named. The sheet stays open — the fix is on the printer's own screen,
      // and the user comes back to the same slot.
      ScaffoldMessenger.of(context).snack(l10n.amsSwitchNotReady);
      return;
    }
    final extruderId = await _askFeedDirection(context, l10n);
    if (extruderId == null || !context.mounted) return;
    await _run(
      context,
      l10n,
      () => controls.amsLoad(slot.printerId, loadTrayId,
          extruderId: extruderId),
      l10n.amsLoadStarted,
    );
  }

  /// Asks which hotend to feed, or answers null when the user backs out.
  ///
  /// A hotend already fed from this very slot is offered as disabled: loading it
  /// again is a no-op the printer would accept and then do nothing about. The
  /// pairing is the one the sheet was opened on — a slot that becomes loaded
  /// while the dialog is up costs one refused command, which is a far smaller
  /// trap than a button that moves under the finger.
  Future<int?> _askFeedDirection(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    final fed = slot.fedFrom;
    bool alreadyFed(int extruderId) =>
        fed?[extruderId]?.holds(amsId: slot.amsId, slotId: slot.trayId) ??
        false;

    Widget option(BuildContext ctx, int extruderId, String label, String id) {
      final taken = alreadyFed(extruderId);
      return logTag(
        id,
        OutlinedButton(
          onPressed: taken ? null : () => Navigator.pop(ctx, extruderId),
          child: Text(taken ? '$label — ${l10n.amsFeedAlreadyLoaded}' : label),
        ),
      );
    }

    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.amsFeedTitle(slot.label)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.amsFeedPrompt),
            const SizedBox(height: 16),
            option(ctx, 1, l10n.extruderLeft, 'feed_direction.left'),
            const SizedBox(height: 8),
            option(ctx, 0, l10n.extruderRight, 'feed_direction.right'),
          ],
        ),
        actions: [
          logTag(
            'feed_direction.cancel',
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Assign spool to this slot" sheet opened from a filament row. Slot is known
/// from context, so the user picks ONLY the spool. Shows the current assignment
/// (with unassign) and the list of active spools from inventory.
class _AssignSlotSheet extends ConsumerStatefulWidget {
  const _AssignSlotSheet({required this.slot});

  final _SlotRef slot;

  @override
  ConsumerState<_AssignSlotSheet> createState() => _AssignSlotSheetState();
}

class _AssignSlotSheetState extends ConsumerState<_AssignSlotSheet> {
  String _query = '';

  _SlotRef get slot => widget.slot;

  @override
  Widget build(BuildContext context) {
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
    final offered = [
      for (final s in spools)
        if (!s.isArchived && s.id != current?.id) s,
    ];
    final options = [
      for (final s in offered)
        if (s.matchesSearch(_query)) s,
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
            _SlotActions(slot: slot),
            if (_offersRegister(inv, current)) ...[
              FilledButton.tonalIcon(
                onPressed: () => _registerFromSlot(context, ref, l10n),
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: Text(l10n.inventoryFromSlot),
              ).tagged('assign_spool.add_to_inventory'),
              const SizedBox(height: 6),
              Text(
                l10n.inventoryFromSlotHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Divider(height: 24),
            ],
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
                onTap: () => _openInInventory(context, current!.id),
                trailing: TextButton.icon(
                  onPressed: () => _unassign(context, ref, l10n),
                  icon: const Icon(Icons.link_off, size: 18),
                  label: Text(l10n.inventoryUnassign),
                ).taggedMaterial('assign_spool.unassign', current.material),
              ).taggedMaterial('assign_spool.current', current.material),
              const Divider(height: 24),
            ],
            Text(l10n.inventoryAssignPick, style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            _spoolSearchRow(l10n),
            const SizedBox(height: 8),
            if (options.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  // Told apart on purpose: an empty inventory and a search that
                  // matched nothing look identical otherwise, and only one of
                  // them is fixed by clearing the field.
                  offered.isEmpty ? l10n.inventoryEmpty : l10n.noSearchResults(_query),
                  style: theme.textTheme.bodyMedium,
                ),
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

  /// Leaves the printer for the spool's own card on Filaments.
  ///
  /// The row names a spool and until now did nothing when pressed, while the
  /// identical row in the list below assigns — so the one that cannot assign
  /// (it is already here) leads to where the rest of its story is: usage
  /// history, cost, editing.
  void _openInInventory(BuildContext context, int spoolId) {
    Navigator.of(context).pop();
    unawaited(openSpoolInInventory(context, ref, spoolId));
  }

  /// Whether to offer registering what the slot holds as a new spool.
  ///
  /// Four things have to line up, and each one is a request the server would
  /// otherwise refuse or a row it would duplicate:
  ///
  /// * the slot reports a readable RFID tag — see [_SlotRef.canRegisterSpool];
  /// * no spool is pinned here yet;
  /// * the inventory is loaded and does not already know that tag. The route
  ///   creates unconditionally, so offering it for a tag that is already on a
  ///   spool would mint a second one; that spool is in the list below, which
  ///   is where the user should pick it up from;
  /// * the session is not an API key against a Spoolman inventory. Spoolman's
  ///   own from-slot route is gated on `filaments:update`, which sits outside
  ///   the API-key scope allowlist entirely, so it answers 403 to every key
  ///   whatever its scopes (`backend/app/core/auth.py`). Under a JWT it works,
  ///   so only the pair is refused.
  bool _offersRegister(InventoryState? inv, Spool? current) {
    if (current != null || !slot.canRegisterSpool || inv == null) return false;
    if (inv.spoolForTag(tagUid: slot.tagUid, trayUuid: slot.trayUuid) != null) {
      return false;
    }
    final onSpoolman =
        ref.watch(inventoryBackendProvider) == InventoryBackend.spoolman;
    final keyed = ref.watch(serverProfileProvider)?.authMode == AuthMode.apiKey;
    return !(onSpoolman && keyed);
  }

  /// Registers the slot's spool and pins it there, in the server's one call.
  ///
  /// The sheet closes first, like every other action here. The refusals worth
  /// their own words are the ones the user can act on: a 404 that is the route
  /// missing rather than the printer being away tells them their server is too
  /// old, and both 400s mean the slot stopped reporting a tag since the sheet
  /// was drawn. Everything else — 403 above all, where the server names the
  /// permission — goes through the shared wording.
  Future<void> _registerFromSlot(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    try {
      await ref
          .read(inventoryProvider.notifier)
          .createSpoolFromSlot(slot.printerId, slot.amsId, slot.trayId);
      messenger.snack(l10n.inventoryFromSlotDone);
    } on AppApiException catch (e) {
      showApiFailure(
        messenger,
        e,
        l10n,
        action: 'assign_spool.add_to_inventory',
        message: _registerFailure(e, l10n),
      );
    } on Object {
      messenger.snack(l10n.inventoryActionFailed);
    }
  }

  /// The wording for a refusal this screen says better than the shared one,
  /// or null to fall through to it.
  String? _registerFailure(AppApiException e, AppLocalizations l10n) {
    final detail = e.detail?.toLowerCase() ?? '';
    return switch (e.statusCode) {
      // FastAPI's own "Not Found" for a route that does not exist on this
      // server; the route's own 404 says the printer is not connected.
      404 when detail.contains('not found') => l10n.inventoryFromSlotUnsupported,
      404 => l10n.inventoryFromSlotOffline,
      400 => l10n.inventoryFromSlotNoTag,
      _ => null,
    };
  }

  /// Narrow the list, or skip it entirely by scanning the spool's label.
  ///
  /// Same pair as the Filaments tab, and the same 48pt square beside the field
  /// — this is the other place a spool has to be found, and finding it by
  /// scrolling a hundred rows at the printer is the case both exist to avoid.
  Widget _spoolSearchRow(AppLocalizations l10n) {
    final t = DashTokens.of(context);
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: DashSearchField(
              id: 'assign_spool.search',
              hintText: l10n.inventorySearchHint,
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: l10n.inventoryScanSpool,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Material(
                color: t.subCard,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _scanAndAssign(l10n),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: t.subCardBorder),
                    ),
                    child: Icon(Icons.qr_code_scanner, color: t.textSecondary),
                  ),
                ),
              ),
            ),
          ).tagged('assign_spool.scan'),
        ],
      ),
    );
  }

  /// Scan a spool's QR label and put it in this slot.
  ///
  /// Straight to the assignment rather than into the search field: the slot is
  /// already known, so a scan says everything the sheet was asking for. It goes
  /// through [_assign], so taking a spool off another slot still asks first.
  Future<void> _scanAndAssign(AppLocalizations l10n) async {
    final messenger = ScaffoldMessenger.of(context);
    final id = await Navigator.of(context, rootNavigator: true)
        .push<int>(MaterialPageRoute(builder: (_) => const SpoolScannerScreen()));
    if (id == null || !mounted) return;

    Spool? scanned() {
      for (final s in ref.read(inventoryProvider).valueOrNull?.spools ?? const <Spool>[]) {
        if (s.id == id) return s;
      }
      return null;
    }

    var spool = scanned();
    if (spool == null) {
      // Added on the server since this list was loaded — worth one refresh
      // before telling the user their label is unknown.
      await ref.read(inventoryProvider.notifier).refresh();
      if (!mounted) return;
      spool = scanned();
    }
    if (spool == null) {
      messenger.snack(l10n.inventoryScanNotFound(id));
      return;
    }

    // An archived spool is not offered in the list but is accepted here: the
    // user is holding it against the printer, which outranks a bookkeeping flag.
    final from = ref.read(inventoryProvider).valueOrNull?.assignmentFor(spool.id);
    if (from != null &&
        from.printerId == slot.printerId &&
        from.amsId == slot.amsId &&
        from.trayId == slot.trayId) {
      // Already where it is being put. Nothing to send, and asking to move it
      // off itself would be nonsense.
      Navigator.of(context).pop();
      messenger.snack(l10n.inventorySpoolAssigned);
      return;
    }
    await _assign(context, ref, l10n, spool, from: from);
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
      messenger.snack(l10n.inventorySpoolAssigned);
    } on AppApiException catch (e) {
      showApiFailure(messenger, e, l10n, action: 'sheet.assign_spool');
    } on Object {
      messenger.snack(l10n.inventoryActionFailed);
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
      messenger.snack(l10n.inventorySpoolUnassigned);
    } on AppApiException catch (e) {
      showApiFailure(messenger, e, l10n, action: 'printer.ams_slot');
    } on Object {
      messenger.snack(l10n.inventoryActionFailed);
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
            style: t.monoLabel.copyWith(color: color),
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
