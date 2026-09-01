import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/printer_status.dart';
import '../../core/notifications/hms_actions.dart';
import '../../core/notifications/hms_catalog.dart';
import '../../data/printers_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../wear_action.dart';
import '../wear_error.dart';
import '../wear_providers.dart';
import '../wear_status.dart';
import '../wear_theme.dart';
import '../wear_transport.dart';
import '../widgets/wear_confirm_dialog.dart';
import '../widgets/wear_face.dart';
import '../widgets/wear_header.dart';
import '../widgets/wear_screen.dart';
import '../widgets/wear_scroll_view.dart';
import '../widgets/wear_settings_entry.dart';
import '../widgets/wear_spinner.dart';
import '../widgets/wear_status_chip.dart';
import '../widgets/wear_toast.dart';

/// Full-screen control page (pushed from the picker). Wraps the body in a
/// Scaffold so it gets its own back-swipe route.
class WearPrinterControlScreen extends StatelessWidget {
  const WearPrinterControlScreen({super.key, required this.printerId});

  final int printerId;

  @override
  Widget build(BuildContext context) =>
      WearScreen(child: WearPrinterControlBody(printerId: printerId));
}

/// Status readout + the four watch actions for one printer. Reads live data
/// from the polled [wearFleetProvider]; actions go through [wearActionsProvider].
class WearPrinterControlBody extends ConsumerStatefulWidget {
  const WearPrinterControlBody({
    super.key,
    required this.printerId,
    this.showSettings = false,
  });

  /// Whether to park the settings entry at the end of the scroll. True only
  /// where this body *is* the home screen (a single printer, no picker to hang
  /// it off); pushed from the list it would be a second door to the same place.
  final bool showSettings;

  final int printerId;

  @override
  ConsumerState<WearPrinterControlBody> createState() =>
      _WearPrinterControlBodyState();
}

class _WearPrinterControlBodyState
    extends ConsumerState<WearPrinterControlBody> with WearAction {

  PrinterWithStatus? _find(List<PrinterWithStatus> printers) =>
      printers.firstWhereOrNull((p) => p.printer.id == widget.printerId);

  @override
  Widget build(BuildContext context) {
    final fleet = ref.watch(wearFleetProvider).valueOrNull;
    final printers = fleet?.printers ?? const <PrinterWithStatus>[];
    final l10n = AppLocalizations.of(context);
    final item = _find(printers);
    if (item == null) {
      // The one thing on this screen that never reaches `WearScrollView`, so
      // the only one that has to ask for the round-safe rectangle itself.
      return WearFace(
        child: Center(
          child: Text(l10n.wearPrinterUnavailable,
              textAlign: TextAlign.center, style: WearText.body),
        ),
      );
    }
    final status = item.status;
    final state = wearStateOf(status);
    final requirePlateClear =
        ref.watch(requirePlateClearProvider).valueOrNull ?? false;

    return Stack(
      children: [
        WearScrollView(
          // Short items all the way down — a title, a chip, a readout, buttons
          // — which is what the curve is for. The one exception carries itself:
          // a fault card is taller than the radius, so `WearFaceCurve` clips it
          // to the round-safe band exactly as the rectangle viewport used to.
          curved: true,
          onRefresh: () => ref.read(wearFleetProvider.notifier).refresh(),
          children: [
            WearHeader(item.printer.name),
            const SizedBox(height: 6),
            Center(child: WearStatusChip(state: state)),
            const SizedBox(height: 10),
            if (state == WearState.printing || state == WearState.paused)
              _progress(l10n, status),
            const SizedBox(height: 10),
            ..._faults(item),
            ..._actions(item, state, requirePlateClear, fleet?.queuePending),
            if (widget.showSettings) ...[
              const SizedBox(height: 4),
              const WearSettingsEntry(),
            ],
          ],
        ),
        if (busy) wearBusyVeil,
      ],
    );
  }

  Widget _progress(AppLocalizations l10n, PrinterStatus? s) {
    final pct = (s?.progress ?? 0).clamp(0, 100).toDouble();
    final eta = formatEta(l10n, s?.remainingTime);
    final layers = (s?.layerNum != null && s?.totalLayers != null)
        ? 'L ${s!.layerNum}/${s.totalLayers}'
        : '';
    final line = [
      '${pct.round()}%',
      if (eta.isNotEmpty) eta,
      if (layers.isNotEmpty) layers,
    ].join('  ·  ');
    // The radius is the height so the bar's ends are round rather than merely
    // softened; two numbers that have to agree, written once.
    const barHeight = 6.0;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(barHeight),
          child: LinearProgressIndicator(
            value: pct / 100,
            minHeight: barHeight,
            backgroundColor: wearSurfaceHigh,
          ),
        ),
        const SizedBox(height: 6),
        // One line whatever the watch's font scale is: wrapped, its second line
        // lands in the viewport's fade, and a half-dimmed "111/264" reads as a
        // rendering fault rather than a readout. Only ever shrinks — at the
        // default scale nothing is scaled at all.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            line,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: WearText.body,
          ),
        ),
      ],
    );
  }

  /// Faults worth putting on screen — none at all while the printer is out of
  /// reach. `hms_errors` is carried forward across a disconnect, so without this
  /// the last-known faults would sit under the OFFLINE chip looking current,
  /// each offering buttons the server answers with "Printer not connected".
  List<HmsError> _displayableFaults(PrinterWithStatus item) {
    if (wearStateOf(item.status) == WearState.offline) return const [];
    return [
      for (final e in item.status?.hmsErrors ?? const <HmsError>[])
        if (hmsIsDisplayable(e, description: HmsCatalog.instance.describe(e))) e,
    ];
  }

  /// Every action the faults on screen are offering, so the generic lifecycle
  /// buttons can stand down where they would duplicate one.
  Set<String> _faultActions(PrinterWithStatus item) => {
        for (final e in _displayableFaults(item))
          if (e.fullCode != null) ...hmsRenderableActions(e.actions),
      };

  /// Active faults, each with the buttons its firmware offers.
  ///
  /// The same rule as the phone decides what appears: a fault the catalog
  /// cannot name is not shown, and a fault without a `full_code` gets no
  /// buttons because nothing would identify it to the printer. What differs is
  /// the shape — a watch has no room for a row of buttons, so each action is a
  /// full-width row, and the description is capped at three lines with the rest
  /// a tap away.
  List<Widget> _faults(PrinterWithStatus item) {
    final l10n = AppLocalizations.of(context);
    final faults = _displayableFaults(item);
    if (faults.isEmpty) return const [];

    final actions = ref.read(wearActionsProvider);
    final id = widget.printerId;
    return [
      for (final fault in faults)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _WearFault(
            fault: fault,
            busy: busy,
            onAction: (action) => action == hmsStopAction
                ? _confirmHmsStop(actions, id, fault, item.printer.name)
                : _run(() => actions.executeHmsAction(id,
                    printError: fault.fullCode!,
                    action: action,
                    jobId: fault.jobId)),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _btn(
          l10n.hmsDismissAll,
          Icons.done_all,
          () => actions.clearHmsErrors(id),
          okMsg: l10n.hmsDismissed,
        ),
      ),
    ];
  }

  Future<void> _confirmHmsStop(
      WearActions actions, int id, HmsError fault, String name) async {
    final ok = await wearConfirm(
      context,
      icon: Icons.stop_rounded,
      title: AppLocalizations.of(context).hmsStopConfirmTitle,
      subtitle: name,
    );
    if (!ok) return;
    await _run(() => actions.executeHmsAction(id,
        printError: fault.fullCode!,
        action: hmsStopAction,
        jobId: fault.jobId));
  }

  List<Widget> _actions(PrinterWithStatus item, WearState state,
      bool requirePlateClear, int? queuePending) {
    final l10n = AppLocalizations.of(context);
    final status = item.status;
    final id = widget.printerId;
    final actions = ref.read(wearActionsProvider);
    final buttons = <Widget>[];
    // What the faults above already offer. Two identical buttons stacked on a
    // 1.4" screen is a coin flip, and the fault's own is the one that carries
    // the code the firmware needs — so the generic one steps aside.
    final offeredByFaults = _faultActions(item);

    if (state == WearState.printing) {
      buttons.add(_btn(l10n.ctrlPause, Icons.pause, () => actions.pause(id)));
    } else if (state == WearState.paused &&
        offeredByFaults.intersection(hmsResumeActions).isEmpty) {
      buttons.add(
          _btn(l10n.ctrlResume, Icons.play_arrow, () => actions.resume(id)));
    }

    // Clear plate: only when the printer is waiting AND the server enforces it.
    if (requirePlateClear && (status?.awaitingPlateClear ?? false)) {
      buttons.add(_btn(l10n.wearClearPlate, Icons.cleaning_services,
          () => actions.clearPlate(id),
          okMsg: l10n.wearPlateCleared));
    }

    // Start next from queue: offered when the printer isn't actively printing
    // AND something is actually waiting (null count = unknown → keep offering).
    // Items already printing don't count as pending.
    if (state != WearState.printing && state != WearState.paused) {
      if (queuePending == null || queuePending > 0) {
        buttons.add(_btn(l10n.queueStartNext, Icons.playlist_play,
            () => actions.startNext(id),
            okMsg: l10n.wearStarted));
      } else {
        buttons.add(_hint(Icons.playlist_remove, l10n.queueEmpty));
      }
    }

    // Stop: destructive → behind a confirm dialog. Skipped when a fault already
    // offers its own stop, for the same reason as resume above.
    if ((state == WearState.printing || state == WearState.paused) &&
        !offeredByFaults.contains(hmsStopAction)) {
      buttons.add(_btn(l10n.ctrlStop, Icons.stop,
          () => _confirmStop(actions, id, item.printer.name),
          color: wearDestructive));
    }

    if (buttons.isEmpty) {
      buttons.add(_hint(Icons.block, l10n.wearNoActions));
    }
    return [
      for (final b in buttons)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: b),
    ];
  }

  Widget _btn(String label, IconData icon, Future<void> Function() action,
          {String? okMsg, Color? color}) =>
      FilledButton.icon(
        onPressed: busy ? null : () => _run(action, okMsg: okMsg),
        icon: Icon(icon),
        label: _label(label),
        style: color != null
            ? FilledButton.styleFrom(backgroundColor: color)
            : null,
      );

  /// Non-actionable placeholder (empty queue / no actions): a button that is
  /// not on offer, so an actually disabled one rather than a pill shaped to
  /// pass for it.
  ///
  /// It used to restate the theme by hand — height 44, radius 22,
  /// `WearText.strong` — which is the trap this repo has a rule about: three
  /// numbers that have to be edited in two places to stay true, and the button
  /// theme is the one that moves. Disabled, it takes its height, its stadium
  /// and its type from the same place as the buttons it stands among, and a
  /// screen reader gets "dimmed button" instead of a shape it cannot name.
  Widget _hint(IconData icon, String label) => FilledButton.icon(
        onPressed: null,
        icon: Icon(icon),
        label: _label(label),
        style: FilledButton.styleFrom(
          disabledBackgroundColor: wearSurfaceHigh,
          disabledForegroundColor: wearInert,
        ),
      );

  /// Ellipsized rather than wrapped, for every button on this screen: a label
  /// that wraps takes the row's height with it, and the round-safe width is
  /// narrower than any of these labels was written against.
  Widget _label(String label) =>
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);

  Future<void> _confirmStop(WearActions actions, int id, String name) async {
    final ok = await wearConfirm(
      context,
      icon: Icons.stop_rounded,
      title: AppLocalizations.of(context).ctrlStopConfirmTitle,
      subtitle: name,
    );
    // Called directly, and correctly so: this whole method already runs inside
    // `_run`, because `_btn` wraps whatever it is given. Wrapping again is not
    // belt and braces — `WearAction.run` opens with `if (_busy) return`, so the
    // inner call is a silent no-op and the button stops working. The fault
    // card's own stop looks different for the same reason: it reaches
    // `_confirmHmsStop` without passing through `_btn`, so it wraps itself.
    if (ok) await actions.stop(id);
  }

  /// Runs an action behind the full-screen busy veil, then refreshes the poll.
  ///
  /// Both outcomes go to a passing message rather than to text on the screen:
  /// these are commands on live printer state, repeatable by tapping again, and
  /// a red line under one of eight buttons in a scrolling list is missed. The
  /// refresh is why this wrapper still exists on top of [run] — nothing else on
  /// the watch has a poll to pull.
  Future<void> _run(Future<void> Function() action, {String? okMsg}) => run(
        () async {
          await action();
          await ref.read(wearFleetProvider.notifier).refresh();
        },
        onDone: () {
          if (okMsg != null) {
            wearToast(context, okMsg, tone: WearToastTone.success);
          }
        },
        onError: (error) => wearToast(
          context,
          _shortError(AppLocalizations.of(context), error),
          tone: WearToastTone.failure,
        ),
      );
}

/// One fault on the watch: what it is, then a full-width button per action.
///
/// Buttons never share a row here — a 1.4" screen turns two side by side into
/// two things nobody can hit, and hitting the wrong one means stopping a print.
class _WearFault extends StatefulWidget {
  const _WearFault({
    required this.fault,
    required this.busy,
    required this.onAction,
  });

  final HmsError fault;
  final bool busy;
  final void Function(String action) onAction;

  @override
  State<_WearFault> createState() => _WearFaultState();
}

class _WearFaultState extends State<_WearFault> {
  bool _fullText = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final description = hmsLabel(
      widget.fault,
      description: HmsCatalog.instance.describe(widget.fault),
    );
    // Bambu's descriptions run to 330 characters; three lines is what a watch
    // can spend before the buttons fall off the screen.
    final actions = widget.fault.fullCode == null
        ? const <String>[]
        : hmsRenderableActions(widget.fault.actions);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: wearTintedBox(wearDestructive),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 14, color: wearFaultText),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.fault.displayCode,
                  style: WearText.small
                      .copyWith(color: wearFaultText, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => setState(() => _fullText = !_fullText),
              child: Text(
                description,
                maxLines: _fullText ? null : 3,
                overflow: _fullText ? null : TextOverflow.ellipsis,
                // Looser lines: this runs to three of them and is the only
                // paragraph on the watch anyone has to actually read.
                style: WearText.body.copyWith(height: 1.25),
              ),
            ),
          ],
          for (final action in actions) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    widget.busy ? null : () => widget.onAction(action),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  // A step down from the theme's button text: these stack one
                  // per action inside an already-boxed fault.
                  textStyle:
                      WearText.body.copyWith(fontWeight: FontWeight.w600),
                  backgroundColor:
                      action == hmsStopAction ? wearDestructive : null,
                ),
                child: Text(
                  hmsActionLabel(l10n, action),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _shortError(AppLocalizations l10n, Object e) {
  if (e is StateError && e.message == 'empty-queue') return l10n.queueEmpty;
  if (e is WearRelayUnreachable) return l10n.wearPhoneUnreachable;
  if (e is WearRelayTimeout) return l10n.wearPhoneNoResponse;
  // Relayed server error: the phone forwards the AppErrorCode name.
  if (e is WearRelayRemoteError) {
    final reason = e.reason;
    if (e.code != AppErrorCode.forbidden.name) return l10n.ctrlFailed;
    // Same policy as the phone: quote the server when it explained itself.
    return reason == null ? l10n.errForbidden : l10n.errForbiddenDetail(reason);
  }
  if (e is AppApiException) return e.localized(l10n);
  // Not localizable, so it is quoted as-is — trimmed to what the message can
  // hold before it takes itself away.
  return wearShortText(e.toString(), max: wearToastMaxChars);
}
