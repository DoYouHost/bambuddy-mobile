import 'dart:async';

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/dash_theme.dart';
import '../../data/printers_repository.dart';
import '../../l10n/app_localizations.dart';
import '../dashboard/widgets/printer_state_pill.dart';
import '../wall/wall_providers.dart';

/// Opens the controller: for the only printer there is, straight away, and
/// otherwise after the user picks one. [replace] swaps the controller that is
/// open for the new one, which is how its printer name switches printers.
///
/// Pushed, never `go`: the dashboard under it owns the foreground service
/// ([docs/tv-flavor.md] §13.2).
Future<void> openController(
  BuildContext context,
  WidgetRef ref, {
  bool replace = false,
}) async {
  final printers = ref.read(wallRosterProvider);
  if (printers == null || printers.isEmpty) return;
  final id = printers.length == 1
      ? printers.single.printer.id
      : await showDialog<int>(
          context: context,
          builder: (_) => _PickerDialog(printers: printers),
        );
  if (id == null || !context.mounted) return;
  final path = '/controller/$id';
  if (replace) {
    context.pushReplacement(path);
  } else {
    unawaited(context.push(path));
  }
}

class _PickerDialog extends StatelessWidget {
  const _PickerDialog({required this.printers});

  final List<PrinterWithStatus> printers;

  /// Wide enough for a name beside its state, narrow enough for a phone held
  /// sideways.
  static const _width = 420.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.controllerTitle),
      content: SizedBox(
        width: _width,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: printers.length,
          separatorBuilder: (_, _) => const SizedBox(height: DashSpace.sm),
          itemBuilder: (context, i) => _PrinterRow(item: printers[i]),
        ),
      ),
    );
  }
}

class _PrinterRow extends StatelessWidget {
  const _PrinterRow({required this.item});

  final PrinterWithStatus item;

  static const _minHeight = 56.0;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final l10n = AppLocalizations.of(context);
    final status = item.status;
    // A printer that does not answer has nothing to control; the dashboard's
    // debounce is not worth a countdown in a list that is read once.
    final reachable = status != null && (status.connected ?? false);
    final radius = BorderRadius.circular(DashSpace.md + DashSpace.xs);
    return Opacity(
      opacity: reachable ? 1 : 0.5,
      child: logTag(
        'controller.pick_printer',
        Material(
          color: t.subCard,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: reachable
                ? () => Navigator.of(context).pop(item.printer.id)
                : null,
            child: Container(
              constraints: const BoxConstraints(minHeight: _minHeight),
              padding: const EdgeInsets.symmetric(horizontal: DashSpace.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.printer.name,
                      style: t.titleMd,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: DashSpace.sm),
                  printerStatePill(t, l10n, status, offline: !reachable),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
