import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../dashboard/controls_providers.dart';
import '../dashboard/widgets/printer_card.dart';
import 'controller_controls.dart';
import 'controller_providers.dart';

/// The fault count in the top bar, opening the fault view. Absent while the
/// printer reports none.
class ControllerFaultChip extends ConsumerWidget {
  const ControllerFaultChip({super.key, required this.printerId});

  final int printerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(
      controllerErrorsProvider(printerId).select((e) => e.length),
    );
    if (count == 0) return const SizedBox.shrink();
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final radius = BorderRadius.circular(ControllerSection.headerHeight / 2);
    return logTag(
      'controller.faults',
      Semantics(
        button: true,
        label: l10n.hmsErrorsCount(count),
        // The count is spoken as words above, not as a bare digit.
        excludeSemantics: true,
        child: Material(
          color: t.danger.withValues(alpha: 0.16),
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: t.danger.withValues(alpha: 0.5)),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: () => showControllerFaults(context, printerId),
            child: SizedBox(
              height: ControllerSection.headerHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: DashSpace.md),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: DashSpace.xl,
                      color: t.dangerInk,
                    ),
                    const SizedBox(width: DashSpace.xs),
                    Text(
                      '$count',
                      style: t.monoTitle.copyWith(color: t.dangerInk),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the printer's faults. [title] replaces the count in the header, for the
/// alert that opens it on its own ("Print paused"). Does nothing while the view
/// is already open for that printer — from the chip or from the alert — so the
/// two never stack.
Future<void> showControllerFaults(
  BuildContext context,
  int printerId, {
  String? title,
}) async {
  // Claimed before the dialog is built, so a second call in the same frame is
  // turned away too.
  if (!_openFaultViews.add(printerId)) return;
  try {
    await showDialog<void>(
      context: context,
      builder: (_) => ControllerFaults(printerId: printerId, title: title),
    );
  } finally {
    _openFaultViews.remove(printerId);
  }
}

/// The printers whose fault view is on screen. Released both when the dialog
/// returns and when the view's state is disposed: the dialog's future does not
/// complete when the tree under it is torn down.
final _openFaultViews = <int>{};

/// Every active fault of the printer, each with the actions its firmware offers
/// (the printer card's own [HmsErrorCard]), and Dismiss all. Closes itself
/// when the last fault clears, so an answered fault does not leave an empty
/// dialog behind.
class ControllerFaults extends ConsumerStatefulWidget {
  const ControllerFaults({super.key, required this.printerId, this.title});

  final int printerId;
  final String? title;

  @override
  ConsumerState<ControllerFaults> createState() => _ControllerFaultsState();
}

class _ControllerFaultsState extends ConsumerState<ControllerFaults> {
  static const _maxWidth = 720.0;

  @override
  void initState() {
    super.initState();
    ref.listenManual(controllerErrorsProvider(widget.printerId), (_, next) {
      if (next.isNotEmpty || !mounted) return;
      // A printer off the network lists no faults; they have not cleared.
      final connected =
          ref
              .read(controllerPrinterProvider(widget.printerId))
              .item
              ?.status
              ?.connected ??
          false;
      if (!connected) return;
      // Its own route, not the top one: a Stop confirmation opened from the
      // view may sit above it, and a bare pop would close that instead.
      final route = ModalRoute.of(context);
      if (route == null) return;
      if (route.isCurrent) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).removeRoute(route);
      }
    });
  }

  @override
  void dispose() {
    _openFaultViews.remove(widget.printerId);
    super.dispose();
  }

  Future<void> _dismissAll() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(controlsProvider.notifier)
        .clearHmsErrors(widget.printerId);
    messenger.snack(
      result.messageFor(l10n) ?? l10n.hmsDismissed,
      clearQueue: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final errors = ref.watch(controllerErrorsProvider(widget.printerId));
    final item = ref.watch(controllerPrinterProvider(widget.printerId)).item;
    final busy = ref.watch(
      controlsProvider.select(
        (s) => s.pendingFor(widget.printerId).isBusy(ControlAction.hms),
      ),
    );
    return Dialog(
      insetPadding: const EdgeInsets.all(DashSpace.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(DashSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: DashSpace.xl,
                    color: t.dangerInk,
                  ),
                  const SizedBox(width: DashSpace.sm),
                  Expanded(
                    child: Text(
                      widget.title ?? l10n.hmsErrorsCount(errors.length),
                      style: t.titleLg,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  logTag(
                    'controller.faults_close',
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      iconSize: DashSpace.xl,
                      constraints: const BoxConstraints.tightFor(
                        width: controllerButtonHeight,
                        height: controllerButtonHeight,
                      ),
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final e in errors)
                      // Keyed by the fault, as on the card: a frame can drop
                      // one from the middle while a command is in the air.
                      HmsErrorCard(
                        key: ValueKey(e.fullCode ?? e.displayCode),
                        printerId: widget.printerId,
                        printerName: item?.printer.name ?? '',
                        error: e,
                        busy: busy,
                        area: 'controller',
                        large: true,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: DashSpace.md),
              Align(
                alignment: Alignment.centerRight,
                child: logTag(
                  'controller.faults_dismiss_all',
                  FilledButton.icon(
                    style: controllerButtonStyle(
                      DashTokens.of(context),
                      minimumSize: const Size(0, controllerButtonHeight),
                    ),
                    onPressed: busy ? null : _dismissAll,
                    icon: const Icon(Icons.done_all),
                    label: Text(l10n.hmsDismissAll),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
