import 'package:flutter/material.dart';

import 'package:app_diagnostics/app_diagnostics.dart';
import '../../core/models/printer.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';

/// Where a bulk "Add to queue" sends its files: one printer, any printer of one
/// model, or — both null — the model each file was sliced for.
typedef QueueTarget = ({int? printerId, String? model});

/// Asks where [fileCount] library files should print. Null when the user
/// backed out, which queues nothing.
///
/// Only active printers are offered, and only their models: the server refuses
/// a model no active printer has, and an inactive printer is not going to take
/// the job either.
Future<QueueTarget?> showQueueTargetSheet(
  BuildContext context, {
  required int fileCount,
  required List<Printer> printers,
}) {
  final active = [
    for (final p in printers)
      if (p.isActive != false) p,
  ];
  final models = distinctPrinterModels(active);
  return dashSheet<QueueTarget>(
    context,
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx);
      return logTag(
        'sheet.queue_target',
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l10n.fmQueueTargetTitle(fileCount),
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(Icons.auto_awesome_outlined),
                    title: Text(l10n.fmQueueTargetAuto),
                    subtitle: Text(l10n.fmQueueTargetAutoHint),
                    onTap: () =>
                        Navigator.pop(ctx, (printerId: null, model: null)),
                  ).tagged('queue_target.auto'),
                  for (final m in models)
                    ListTile(
                      leading: const Icon(Icons.groups_outlined),
                      title: Text(l10n.queueEditAnyModel(m)),
                      onTap: () =>
                          Navigator.pop(ctx, (printerId: null, model: m)),
                    ).tagged('queue_target.model'),
                  for (final p in active)
                    ListTile(
                      leading: const Icon(Icons.print_outlined),
                      title: Text(p.name),
                      subtitle: p.model == null ? null : Text(p.model!),
                      onTap: () =>
                          Navigator.pop(ctx, (printerId: p.id, model: null)),
                    ).tagged('queue_target.printer'),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
