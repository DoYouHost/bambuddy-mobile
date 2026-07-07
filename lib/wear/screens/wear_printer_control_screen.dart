import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/printer_status.dart';
import '../../data/printers_repository.dart';
import '../../providers.dart';
import '../wear_providers.dart';
import '../wear_status.dart';

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
    final printers = ref.watch(wearFleetProvider).valueOrNull ?? const [];
    final item = _find(printers);
    if (item == null) {
      return const Center(child: Text('Printer unavailable'));
    }
    final status = item.status;
    final state = wearStateOf(status);
    final requirePlateClear =
        ref.watch(requirePlateClearProvider).valueOrNull ?? false;

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
          children: [
            Center(
              child: Text(
                item.printer.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 2),
            Center(
              child: Text(state.label,
                  style: TextStyle(
                      color: state.color, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 10),
            if (state == WearState.printing || state == WearState.paused)
              _progress(status),
            const SizedBox(height: 10),
            ..._actions(state, status, requirePlateClear),
          ],
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

  List<Widget> _actions(
      WearState state, PrinterStatus? status, bool requirePlateClear) {
    final id = widget.printerId;
    final actions = ref.read(wearActionsProvider);
    final buttons = <Widget>[];

    if (state == WearState.printing) {
      buttons.add(_btn('Pause', Icons.pause, () => actions.pause(id)));
    } else if (state == WearState.paused) {
      buttons.add(_btn('Resume', Icons.play_arrow, () => actions.resume(id)));
    }

    // Clear plate: only when the printer is waiting AND the server enforces it.
    if (requirePlateClear && (status?.awaitingPlateClear ?? false)) {
      buttons.add(_btn('Clear plate', Icons.cleaning_services,
          () => actions.clearPlate(id),
          okMsg: 'Plate cleared'));
    }

    // Start next from queue: offered whenever the printer isn't actively printing.
    if (state != WearState.printing && state != WearState.paused) {
      buttons.add(_btn('Start next', Icons.playlist_play,
          () => actions.startNext(id),
          okMsg: 'Started'));
    }

    // Stop: destructive → behind a confirm dialog.
    if (state == WearState.printing || state == WearState.paused) {
      buttons.add(_btn('Stop', Icons.stop, () => _confirmStop(actions, id),
          color: const Color(0xFFB3261E)));
    }

    if (buttons.isEmpty) {
      buttons.add(const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('No actions available',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.white54)),
      ));
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

  Future<void> _confirmStop(WearActions actions, int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('Stop print?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Stop')),
        ],
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
      if (mounted) _toast(_shortError(e));
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

String _shortError(Object e) {
  if (e is StateError && e.message == 'empty-queue') return 'Queue empty';
  final s = e.toString();
  return s.length > 60 ? '${s.substring(0, 60)}…' : s;
}
