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
/// server without the route, and until the first listing has answered.
final scheduledDryingSupportedProvider = FutureProvider<bool>((ref) async {
  // Waits for the listing rather than racing it: that request is what sets the
  // latch this reads, so asking first would repeat the version table's guess
  // and never be asked again. Only a 404 or a 403 moves the latch, so a listing
  // that failed otherwise is swallowed and the latch still decides.
  try {
    await ref.watch(scheduledDryingsProvider.future);
  } on Object {
    // Deliberately ignored; see above.
  }
  return ref.watch(scheduledDryingRepositoryProvider).supportsScheduling();
});

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
