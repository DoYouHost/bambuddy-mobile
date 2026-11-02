import 'package:material_ui/material_ui.dart';

import 'package:app_diagnostics/app_diagnostics.dart';
import '../../core/models/cost_center.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';

/// Asks which of [centers] a bulk "Add to queue" of [jobCount] jobs is charged
/// to; billing refuses a job without one, and no form here sets it per file.
/// The id, or null when the user backed out, which queues nothing.
///
/// The user's own center comes first, as in the print form. A center's name is
/// the user's own words, so every row is one diagnostic id.
Future<int?> showQueueCostCenterSheet(
  BuildContext context, {
  required int jobCount,
  required List<CostCenter> centers,
}) => dashSheet<int>(
  context,
  builder: (ctx) {
    final l10n = AppLocalizations.of(ctx);
    return logTag(
      'sheet.queue_cost_center',
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DashSpace.gutter,
              0,
              DashSpace.gutter,
              DashSpace.sm,
            ),
            child: Text(
              l10n.fmQueueCostCenterTitle(jobCount),
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in centers)
                  ListTile(
                    leading: Icon(
                      c.isPrivate
                          ? Icons.person_outline
                          : Icons.account_balance_wallet_outlined,
                    ),
                    title: Text(
                      c.isPrivate
                          ? l10n.queueCostCenterPersonal(c.name)
                          : c.name,
                    ),
                    onTap: () => Navigator.pop(ctx, c.id),
                  ).tagged('queue_cost_center.center'),
              ],
            ),
          ),
        ],
      ),
    );
  },
);
