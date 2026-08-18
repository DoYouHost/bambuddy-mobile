import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/ams_filament_preset.dart';
import '../../core/models/k_profile.dart';
import '../../providers.dart';

/// Identifies one slot for the per-slot providers below. A record rather than a
/// class so the family key compares by value for free.
typedef SlotKey = ({int printerId, int amsId, int trayId});

/// Everything the filament picker needs that is not per-slot: the three preset
/// tiers and the printer-model registry.
///
/// Fetched as one unit because the picker cannot show a partial list sensibly —
/// tier order and deduplication only mean something once all three have
/// answered. Each source degrades on its own: a tier that fails contributes
/// nothing and the rest still work.
class SlotPresetSources {
  const SlotPresetSources({
    this.cloud = const [],
    this.local = const [],
    this.builtin = const [],
    this.printerModels = const {},
    this.cloudNeedsLogin = false,
  });

  final List<AmsFilamentPreset> cloud;
  final List<AmsFilamentPreset> local;
  final List<AmsFilamentPreset> builtin;
  final Map<String, String> printerModels;

  /// The cloud tier is missing because nobody is logged in to Bambu Cloud —
  /// worth an offer to log in, unlike a tier that merely failed. Kept apart
  /// from "empty" so the sheet never nags a user who is logged in and simply
  /// has no presets of their own.
  final bool cloudNeedsLogin;

  /// Whether anything at all can be picked. The built-in table normally
  /// guarantees this, so false means every source was refused or unreachable.
  bool get isEmpty => cloud.isEmpty && local.isEmpty && builtin.isEmpty;
}

/// [SlotPresetSources], fetched once per server profile.
///
/// Deliberately not auto-disposed: the registry and the built-in table are
/// static, cloud presets change when the user edits them in the slicer, and the
/// sheet opens once per slot — refetching three times on every open would be
/// three round trips to show the same list.
final slotPresetSourcesProvider = FutureProvider<SlotPresetSources>((ref) async {
  final repo = ref.watch(amsSlotConfigRepositoryProvider);

  // A tier that cannot be read is one tier fewer, not a failed sheet: the
  // cloud needs a Bambu login, the imported presets need `settings:read`, and
  // a key can hold neither. All four run at once — they are independent, and
  // the sheet waits for the slowest either way.
  Future<T> orElse<T>(Future<T> Function() read, T fallback) async {
    try {
      return await read();
    } on AppApiException {
      return fallback;
    }
  }

  var needsLogin = false;
  Future<List<AmsFilamentPreset>> readCloud() async {
    try {
      return await repo.cloudFilaments();
    } on AppApiException catch (e) {
      // 401 here means "no Bambu Cloud login", which is worth offering to fix.
      // Any other refusal is just a tier we do without.
      needsLogin = e.code == AppErrorCode.unauthorized;
      return const [];
    }
  }

  final (cloud, local, builtin, models) = await (
    readCloud(),
    orElse(repo.localFilaments, const <AmsFilamentPreset>[]),
    orElse(repo.builtinFilaments, const <AmsFilamentPreset>[]),
    // Without the registry every preset classifies as "names no printer", and
    // the catalogue's fail-open rule keeps them all visible: fewer presets are
    // hidden than should be, none that should not.
    orElse(repo.printerModels, const <String, String>{}),
  ).wait;

  return SlotPresetSources(
    cloud: cloud,
    local: local,
    builtin: builtin,
    printerModels: models,
    cloudNeedsLogin: needsLogin,
  );
});

/// Which printer's calibration table to read, and for which nozzle.
typedef KProfileKey = ({int printerId, String nozzleDiameter});

/// The printer's calibration table, and whether reading it worked.
///
/// [failed] tells "this printer has no stored profiles" apart from "we could
/// not ask it" — both leave the picker with nothing to offer, and only one of
/// them is worth explaining.
typedef KProfileTable = ({List<KProfile> profiles, bool failed});

/// The pressure-advance profiles a printer holds for one nozzle size.
///
/// Never an error state: the table is read off the printer over MQTT, so a
/// disconnected machine answers 400 and a key without `kprofiles:read` answers
/// 403, and neither should take down a sheet whose other half still works. The
/// write then falls back to the printer's default K.
final kProfilesProvider =
    FutureProvider.autoDispose.family<KProfileTable, KProfileKey>(
  (ref, key) async {
    try {
      final profiles =
          await ref.watch(amsSlotConfigRepositoryProvider).kProfiles(
                key.printerId,
                nozzleDiameter: key.nozzleDiameter,
              );
      return (profiles: profiles, failed: false);
    } on Object {
      // Deliberately every failure, not just `AppApiException`: whatever went
      // wrong, the honest report is "the printer's calibrations are not
      // available", and a picker that vanishes instead reads as a missing
      // feature.
      return (profiles: const <KProfile>[], failed: true);
    }
  },
);

/// The preset a slot was configured with, or null when it has none.
///
/// Auto-disposed and per slot: unlike the catalogue this is state the user is
/// about to change, so a stale copy would preselect the wrong entry.
final slotPresetProvider =
    FutureProvider.autoDispose.family<SlotPreset?, SlotKey>((ref, slot) {
  return ref.watch(amsSlotConfigRepositoryProvider).slotPreset(
        slot.printerId,
        amsId: slot.amsId,
        trayId: slot.trayId,
      );
});
