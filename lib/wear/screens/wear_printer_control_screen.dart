import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/printer_status.dart';
import '../../data/printers_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';
import '../wear_providers.dart';
import '../wear_status.dart';
import '../wear_transport.dart';
import '../widgets/wear_confirm_dialog.dart';
import '../widgets/wear_status_chip.dart';

/// Full-screen control page (pushed from the picker). Wraps the body in a
/// Scaffold so it gets its own back-swipe route.
class WearPrinterControlScreen extends StatelessWidget {
  const WearPrinterControlScreen({super.key, required this.printerId});

  final int printerId;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(child: WearPrinterControlBody(printerId: printerId)),
      );
}

/// Status readout + the four watch actions for one printer. Reads live data
/// from the polled [wearFleetProvider]; actions go through [wearActionsProvider].
class WearPrinterControlBody extends ConsumerStatefulWidget {
  const WearPrinterControlBody({super.key, required this.printerId});

  final int printerId;

  @override
  ConsumerState<WearPrinterControlBody> createState() =>
      _WearPrinterControlBodyState();
}

class _WearPrinterControlBodyState
    extends ConsumerState<WearPrinterControlBody> {
  bool _busy = false;

  PrinterWithStatus? _find(List<PrinterWithStatus> printers) =>
      printers.firstWhereOrNull((p) => p.printer.id == widget.printerId);

  @override
  Widget build(BuildContext context) {
    final fleet = ref.watch(wearFleetProvider).valueOrNull;
    final printers = fleet?.printers ?? const <PrinterWithStatus>[];
    final l10n = AppLocalizations.of(context);
    final item = _find(printers);
    if (item == null) {
      return Center(child: Text(l10n.wearPrinterUnavailable));
    }
    final status = item.status;
    final state = wearStateOf(status);
    final requirePlateClear =
        ref.watch(requirePlateClearProvider).valueOrNull ?? false;

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => ref.read(wearFleetProvider.notifier).refresh(),
          child: ListView(
            // Always scrollable so the pull gesture works even when the few
            // action buttons don't fill the screen.
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
            children: [
              Center(
                child: Text(
                  item.printer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 6),
              Center(child: WearStatusChip(state: state)),
              const SizedBox(height: 10),
              if (state == WearState.printing || state == WearState.paused)
                _progress(status),
              const SizedBox(height: 10),
              ..._actions(item, state, requirePlateClear, fleet?.queuePending),
            ],
          ),
        ),
        if (_busy)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x99000000),
              child: Center(
                  child: SizedBox(
                      width: 30, height: 30, child: CircularProgressIndicator())),
            ),
          ),
      ],
    );
  }

  Widget _progress(PrinterStatus? s) {
    final pct = (s?.progress ?? 0).clamp(0, 100).toDouble();
    final eta = formatEta(s?.remainingTime);
    final layers = (s?.layerNum != null && s?.totalLayers != null)
        ? 'L ${s!.layerNum}/${s.totalLayers}'
        : '';
    final line = [
      '${pct.round()}%',
      if (eta.isNotEmpty) eta,
      if (layers.isNotEmpty) layers,
    ].join('  ·  ');
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: pct / 100,
            minHeight: 6,
            backgroundColor: const Color(0xFF2A2A2C),
          ),
        ),
        const SizedBox(height: 6),
        Text(line, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  List<Widget> _actions(PrinterWithStatus item, WearState state,
      bool requirePlateClear, int? queuePending) {
    final l10n = AppLocalizations.of(context);
    final status = item.status;
    final id = widget.printerId;
    final actions = ref.read(wearActionsProvider);
    final buttons = <Widget>[];

    if (state == WearState.printing) {
      buttons.add(_btn(l10n.ctrlPause, Icons.pause, () => actions.pause(id)));
    } else if (state == WearState.paused) {
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

    // Stop: destructive → behind a confirm dialog.
    if (state == WearState.printing || state == WearState.paused) {
      buttons.add(_btn(l10n.ctrlStop, Icons.stop,
          () => _confirmStop(actions, id, item.printer.name),
          color: const Color(0xFFB3261E)));
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
        onPressed: _busy ? null : () => _run(action, okMsg: okMsg),
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: color != null
            ? FilledButton.styleFrom(backgroundColor: color)
            : null,
      );

  /// Non-actionable placeholder (empty queue / no actions). Shares the button
  /// row's height and shape so the layout doesn't jump, but reads as inert:
  /// a muted fill instead of the accent, with an icon + brighter-than-white54
  /// label so it's actually legible on the OLED black.
  Widget _hint(IconData icon, String label) => Container(
        height: 44,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2C),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white70),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );

  Future<void> _confirmStop(WearActions actions, int id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => WearConfirmDialog(
        icon: Icons.stop_rounded,
        title: AppLocalizations.of(ctx).ctrlStopConfirmTitle,
        subtitle: name,
        confirmColor: const Color(0xFFB3261E),
      ),
    );
    if (ok == true) await actions.stop(id);
  }

  /// Runs an action with a full-screen busy veil, then refreshes the poll.
  /// Errors surface as a short SnackBar; the screen never crashes on failure.
  Future<void> _run(Future<void> Function() action, {String? okMsg}) async {
    setState(() => _busy = true);
    try {
      await action();
      await ref.read(wearFleetProvider.notifier).refresh();
      if (okMsg != null && mounted) _toast(okMsg);
    } catch (e) {
      if (mounted) _toast(_shortError(AppLocalizations.of(context), e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 12)),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
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
  final s = e.toString();
  return s.length > 60 ? '${s.substring(0, 60)}…' : s;
}
