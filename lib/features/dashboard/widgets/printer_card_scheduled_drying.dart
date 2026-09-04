part of 'printer_card.dart';

/// The runs the server is holding for one AMS unit, under that unit's header.
///
/// Pending rows say when they will start and, once they are due, why they have
/// not; a failed one says what went wrong and offers to be dismissed. Nothing
/// at all on a server without the route — [ScheduledDryingRepository.list]
/// answers an empty list there rather than throwing.
class _ScheduledDryingBanner extends ConsumerStatefulWidget {
  const _ScheduledDryingBanner({
    required this.printerId,
    required this.amsId,
    required this.drying,
  });

  final int printerId;
  final int amsId;

  /// Whether this AMS is drying right now. Not drawn — watched: the live status
  /// reports a dispatched run long before anything else would ask the server
  /// again, and until it does the banner would still be promising a run that
  /// has already started.
  final bool drying;

  @override
  ConsumerState<_ScheduledDryingBanner> createState() =>
      _ScheduledDryingBannerState();
}

class _ScheduledDryingBannerState
    extends ConsumerState<_ScheduledDryingBanner> {
  @override
  void didUpdateWidget(_ScheduledDryingBanner old) {
    super.didUpdateWidget(old);
    if (widget.drying && !old.drying) {
      ref.invalidate(scheduledDryingsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(scheduledDryingsProvider).valueOrNull;
    if (all == null) return const SizedBox.shrink();
    final rows = scheduledDryingsFor(
      all,
      printerId: widget.printerId,
      amsId: widget.amsId,
    );
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _ScheduledDryingRow(row: row),
            ),
        ],
      ),
    );
  }
}

/// One scheduled run: what it is waiting for, and the button that drops it.
class _ScheduledDryingRow extends ConsumerStatefulWidget {
  const _ScheduledDryingRow({required this.row});

  final ScheduledDrying row;

  @override
  ConsumerState<_ScheduledDryingRow> createState() =>
      _ScheduledDryingRowState();
}

class _ScheduledDryingRowState extends ConsumerState<_ScheduledDryingRow> {
  bool _busy = false;

  Future<void> _drop() async {
    final l10n = AppLocalizations.of(context);
    // The card this row sits in is rebuilt by every status frame, so the row
    // can be gone before the DELETE answers — see [detachFrom].
    final (:providers, :messenger) = detachFrom(context);
    final repository = providers.read(scheduledDryingRepositoryProvider);
    setState(() => _busy = true);
    try {
      await repository.cancel(widget.row.id);
      providers.invalidate(scheduledDryingsProvider);
    } on AppApiException catch (e) {
      showApiFailure(mounted ? messenger : null, e, l10n,
          action: 'printer.drying_schedule_cancel');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final row = widget.row;
    final failed = row.isFailed;
    final accent = failed ? t.danger : t.accentOrangeInk;

    final headline = failed
        ? l10n.ctrlDryScheduleFailed(
            row.errorMessage ?? l10n.ctrlDryScheduleFailedUnknown,
          )
        : row.startAfter == null
            ? l10n.ctrlDryScheduledAsap
            : l10n.ctrlDryScheduledFor(
                DateTimeFormats.of(context).dateTime(row.startAfter!),
              );
    // Only while it is still pending: a failed row's error message already says
    // what happened, and the reason the scheduler last wrote is what it was
    // waiting for before that.
    final waiting = failed ? null : _waitingText(l10n, row.waitingReason);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            failed ? Icons.error_outline : Icons.schedule,
            size: 16,
            color: accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headline, style: t.bodyPlain.copyWith(color: t.textPrimary)),
                if (waiting != null)
                  Text(
                    waiting,
                    style: t.body.copyWith(color: t.textSecondary),
                  ),
              ],
            ),
          ),
          // One id for both wordings, unlike the sheet's Start/Schedule pair:
          // this is the same DELETE either way, and a log that split it would
          // be naming the row's status rather than the button that was pressed.
          _HeaderIconButton(
            id: 'printer.drying_schedule_cancel',
            icon: Icons.close_rounded,
            tooltip: failed
                ? l10n.ctrlDryScheduleDismiss
                : l10n.ctrlDryScheduleCancel,
            color: accent,
            borderColor: accent.withValues(alpha: 0.5),
            onPressed: _busy ? null : _drop,
          ),
        ],
      ),
    );
  }
}

/// Wording for the scheduler's `waiting_reason`, or null when there is nothing
/// to explain — the run is not due yet, or the token is one this build does not
/// know (a newer server adding a reason must not print its identifier at the
/// user).
String? _waitingText(AppLocalizations l10n, DryingWaitReason? reason) =>
    switch (reason) {
      null || DryingWaitReason.unknown => null,
      DryingWaitReason.powerRequired => l10n.ctrlDryWaitPower,
      DryingWaitReason.retractFilament => l10n.ctrlDryWaitRetract,
      DryingWaitReason.blocked => l10n.ctrlDryWaitBlocked,
      DryingWaitReason.amsNotFound => l10n.ctrlDryWaitAmsNotFound,
      DryingWaitReason.printerOffline => l10n.ctrlDryWaitOffline,
      DryingWaitReason.printerBusy => l10n.ctrlDryWaitBusy,
      DryingWaitReason.alreadyDrying => l10n.ctrlDryWaitAlreadyDrying,
      DryingWaitReason.interrupted => l10n.ctrlDryWaitInterrupted,
    };

/// The start-time picker of the drying sheet: three modes, and whichever second
/// row the chosen one needs.
///
/// Only built when the server has the route; on an older one the sheet keeps
/// its single Start button, because a schedule it cannot accept is worse than
/// no offer at all.
class _DryStartPicker extends StatelessWidget {
  const _DryStartPicker({
    required this.mode,
    required this.delayMinutes,
    required this.at,
    required this.onMode,
    required this.onDelay,
    required this.onPickTime,
  });

  final DryStartMode mode;
  final int delayMinutes;

  /// The instant chosen in [DryStartMode.atTime], or null while none has been.
  final DateTime? at;

  final ValueChanged<DryStartMode> onMode;
  final ValueChanged<int> onDelay;
  final VoidCallback onPickTime;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.ctrlDryStartWhen,
          style: t.body.copyWith(color: t.textSecondary),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in DryStartMode.values)
              _PresetChip(
                label: switch (m) {
                  DryStartMode.now => l10n.ctrlDryStartNow,
                  DryStartMode.delay => l10n.ctrlDryStartAfter,
                  DryStartMode.atTime => l10n.ctrlDryStartAt,
                },
                // One id per mode, like the statistics range menu: which of
                // three a user chose is the whole question a report about a
                // schedule that started at the wrong time would ask.
                id: switch (m) {
                  DryStartMode.now => 'drying.start_mode.now',
                  DryStartMode.delay => 'drying.start_mode.delay',
                  DryStartMode.atTime => 'drying.start_mode.at_time',
                },
                selected: mode == m,
                onTap: () => onMode(m),
              ),
          ],
        ),
        if (mode == DryStartMode.delay) ...[
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final minutes in dryingDelayPresets)
                _PresetChip(
                  label: formatMinutes(l10n, minutes),
                  id: 'drying.start_delay',
                  selected: delayMinutes == minutes,
                  onTap: () => onDelay(minutes),
                ),
            ],
          ),
        ],
        if (mode == DryStartMode.atTime) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.event_outlined, size: 18, color: t.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  at == null
                      ? l10n.ctrlDryPickTime
                      : DateTimeFormats.of(context).dateTime(at!),
                  style: at == null
                      ? t.body.copyWith(color: t.textSecondary)
                      : t.monoValue,
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: t.textPrimary,
                  side: BorderSide(color: t.subCardBorder),
                ),
                onPressed: onPickTime,
                child: Text(l10n.ctrlDryPickTime),
              ).tagged('drying.pick_time'),
            ],
          ),
        ],
      ],
    );
  }
}

/// Says that the server dries on its own, when it does.
///
/// Not a control: the three settings behind it are `settings:update`, which an
/// API key can never hold, so there is nothing here to switch. It is here
/// because a cycle the user did not start otherwise reads as a fault — the
/// flame chip lights up, the sheet offers Stop, and nothing says why.
class _AutoDryingNote extends ConsumerWidget {
  const _AutoDryingNote();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auto = ref.watch(autoDryingProvider);
    // `whilePrinting` alone changes nothing — it only widens the two automations
    // above it to a printer that is busy.
    if (!auto.whenIdle && !auto.betweenPrints) return const SizedBox.shrink();

    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    // Idle drying is the wider of the two and covers the queue case as well, so
    // naming both would say the same thing twice.
    final what = auto.whenIdle ? l10n.ctrlDryAutoIdle : l10n.ctrlDryAutoQueue;
    final text = auto.whilePrinting
        ? '$what ${l10n.ctrlDryAutoWhilePrinting}'
        : what;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.autorenew, size: 15, color: t.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: t.body.copyWith(color: t.textSecondary)),
          ),
        ],
      ),
    );
  }
}
