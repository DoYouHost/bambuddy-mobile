import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ams/drying_presets.dart';
import '../../core/models/scheduled_drying.dart';
import '../../providers.dart';

/// Every drying run the server is holding for later — the whole fleet in one
/// request, not one per printer.
///
/// A card filters it with [scheduledDryingsFor]; a `family` keyed by printer
/// would put a request behind every card for a list that is almost always
/// empty. Not `autoDispose` either — the dashboard rebuilds these cards on
/// every status frame, and a provider dying in between would refetch each time.
final scheduledDryingsProvider = FutureProvider<List<ScheduledDrying>>(
  (ref) => ref.watch(scheduledDryingRepositoryProvider).list(),
);

/// Whether the drying sheet offers the "later" start modes at all. False on a
/// server without the route; what the listing ([scheduledDryingsProvider])
/// finds reaches it the moment it lands.
final scheduledDryingSupportedProvider = capabilityGate(
  (ref) => ref.watch(scheduledDryingRepositoryProvider).schedulingCapability,
);

/// The rows a given AMS unit's card should show: this printer's `pending` and
/// `failed` runs for that unit.
///
/// `running` is left out because the AMS reports its own countdown beside the
/// flame chip; `failed` is in because dispatch is the only place a run can fail
/// and without the row the schedule would simply disappear.
List<ScheduledDrying> scheduledDryingsFor(
  List<ScheduledDrying> all, {
  required int printerId,
  required int amsId,
}) => [
  for (final row in all)
    if (row.printerId == printerId &&
        row.amsId == amsId &&
        (row.isPending || row.isFailed))
      row,
];

/// The drying temperatures and durations the server itself uses, from its
/// `drying_presets` setting — the same table the web's Queue Auto-Drying page
/// edits and the scheduler dries by.
///
/// Falls back to [defaultDryingPresets] when the setting is absent, empty or
/// unreadable — which includes a session that may not read settings at all,
/// since `settings:read` rides on an API key's `can_read_status` scope.
final dryingPresetsProvider = serverValue<Map<String, DryPreset>>(
  (settings) => dryingPresetsFrom(settings['drying_presets']),
);

/// Whether the server dries on its own, and how. Read-only — see [AutoDrying].
final autoDryingProvider = serverValue<AutoDrying>(autoDryingFrom);
