import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/models/printer.dart';
import '../../l10n/app_localizations.dart';
import '../archive/archive_providers.dart' show printersForPickerProvider;

/// Shared printer picker bottom sheet: one printer → returned immediately (no
/// sheet); zero → snackbar + `null`; several → tap-to-choose sheet. Replaces
/// the near-identical `_pickPrinter` previously duplicated in the archive and
/// file-manager screens.
///
/// Not used by the queue start flow — that one is intentionally different: it
/// lists [PrinterCandidate]s (offline printers included, bambuddy wakes them)
/// from a different provider, not this plain [Printer] list.
Future<Printer?> pickPrinterSheet(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final List<Printer> printers;
  try {
    printers = await ref.read(printersForPickerProvider.future);
  } on AppApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(_errText(e, l10n))));
    return null;
  }
  if (!context.mounted) return null;
  if (printers.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.noPrintersAvailable)));
    return null;
  }
  if (printers.length == 1) return printers.first;

  return showModalBottomSheet<Printer>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(l10n.pickPrinterTitle,
                style: Theme.of(ctx).textTheme.titleMedium),
          ),
          for (final p in printers)
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: Text(p.name),
              subtitle: p.model == null ? null : Text(p.model!),
              onTap: () => Navigator.pop(ctx, p),
            ).tagged('printer_picker.printer'),
        ],
      ),
    ),
  );
}

String _errText(AppApiException e, AppLocalizations l10n) =>
    e is AuthException && e.code == AppErrorCode.forbidden
        ? l10n.ctrlForbidden
        : l10n.ctrlFailed;
