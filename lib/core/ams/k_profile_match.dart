/// Which of the printer's calibration profiles belong to the filament a slot is
/// being configured with.
///
/// The printer stores K profiles under a name the user typed in the slicer and a
/// filament id, and nothing links them to a preset — so the pairing is guesswork
/// over both, ported from the web's `ConfigureAmsSlotModal`. Two rules run
/// through all of it: a guess is never allowed to *hide* a profile (everything
/// unmatched is still offered), and the profile the slot is already printing
/// with is never dropped, whatever the guess says.
library;

import '../models/k_profile.dart';
import 'filament_naming.dart';

/// The picker's two groups: profiles that look like they belong to the selected
/// preset, and everything else the printer holds.
typedef KProfileChoices = ({List<KProfile> matching, List<KProfile> other});

extension KProfileChoicesX on KProfileChoices {
  /// Whether the printer offered anything at all. False hides the picker: a
  /// machine with an empty calibration table has no choice to present, only the
  /// default it would use anyway.
  bool get any => matching.isNotEmpty || other.isNotEmpty;

  /// The profile [optionId] names, or null for the default.
  KProfile? byOptionId(String? optionId) {
    if (optionId == null || optionId.isEmpty) return null;
    for (final p in matching) {
      if (p.optionId == optionId) return p;
    }
    for (final p in other) {
      if (p.optionId == optionId) return p;
    }
    return null;
  }
}

/// Materials the printer's users spell differently from the preset.
const _materialAliases = <String, List<String>>{
  'NYLON': ['PA', 'PA-CF', 'PA6'],
  'PA': ['NYLON'],
};

/// Split [profiles] into the ones that fit [presetName] and the rest.
///
/// [presetFilamentId] is the Bambu id behind the selected preset, when it has
/// one — an exact match on it beats every name heuristic, because it is the key
/// the printer's own calibration table is organised by. [extruderId] is the
/// nozzle this slot feeds, used only to choose between a dual-nozzle printer's
/// duplicate rows. [activeCaliIdx] is the profile the slot is printing with now.
KProfileChoices matchKProfiles({
  required List<KProfile> profiles,
  String? presetName,
  String? presetFilamentId,
  int? extruderId,
  int? activeCaliIdx,
}) {
  final matching = _matching(
    profiles: profiles,
    presetName: presetName,
    presetFilamentId: presetFilamentId,
    extruderId: extruderId,
    activeCaliIdx: activeCaliIdx,
  );

  final claimed = {for (final p in matching) p.optionId};
  final other = _dedupe(
    profiles.where((p) => !claimed.contains(p.optionId)),
    extruderId,
  )..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  return (matching: matching, other: other);
}

List<KProfile> _matching({
  required List<KProfile> profiles,
  required String? presetName,
  required String? presetFilamentId,
  required int? extruderId,
  required int? activeCaliIdx,
}) {
  final active = _active(profiles, activeCaliIdx, extruderId);

  final name = presetName?.trim();
  if (name == null || name.isEmpty) {
    // Nothing picked yet, so nothing to match against — but a slot that is
    // already calibrated still has to show it, or the sheet would claim the
    // printer is on the default K when it is not.
    return [?active];
  }

  final parsed = parsePresetName(name);
  final material = parsed.material.toUpperCase();
  // "Generic" leads every built-in Bambu preset name and is not a manufacturer.
  // Read as one it puts the filter into brand-gated mode and then demands
  // "GENERIC" in the profile's name, which no real profile has — so picking a
  // built-in generic preset would match nothing at all.
  final brand =
      parsed.brand.toUpperCase() == 'GENERIC' ? '' : parsed.brand.toUpperCase();
  final fullName = presetNameWithoutPrinter(name).toUpperCase();

  // A one-letter material would match half the table on substring alone.
  final usable = material.length >= 2;
  final matched = !usable
      ? const <KProfile>[]
      : profiles.where((p) =>
          _matchesFilamentId(p, presetFilamentId) ||
          _matchesName(p, brand: brand, material: material, fullName: fullName));

  final result = _dedupe(matched, extruderId);

  // The slot's own profile goes in front even when neither its name nor its
  // filament id agrees with the preset: a spool configured as "Generic PLA" can
  // be printing under a profile calibrated for something else, and the sheet
  // must not offer to silently replace it with the default.
  if (active != null && !result.any((p) => p.slotId == active.slotId)) {
    result.insert(0, active);
  }
  return result;
}

/// The profile the slot is printing with, if the printer named one.
///
/// `cali_idx` 0 is the printer's default, not a stored profile, so only a
/// positive index identifies something to preselect.
KProfile? _active(List<KProfile> profiles, int? caliIdx, int? extruderId) {
  if (caliIdx == null || caliIdx <= 0) return null;
  for (final p in profiles) {
    if (p.slotId != caliIdx) continue;
    if (extruderId != null && p.extruderId != extruderId) continue;
    return p;
  }
  return null;
}

/// Both sides agreeing on the filament id is the one hard match here: the
/// printer keeps one calibration table per id, so a profile the user named
/// after its colour still surfaces under the preset it was calibrated for.
bool _matchesFilamentId(KProfile profile, String? presetFilamentId) {
  if (presetFilamentId == null || presetFilamentId.isEmpty) return false;
  if (profile.filamentId.isEmpty) return false;
  return filamentIdFromSettingId(profile.filamentId) == presetFilamentId;
}

bool _matchesName(
  KProfile profile, {
  required String brand,
  required String material,
  required String fullName,
}) {
  final name = profile.name.toUpperCase();

  // A branded preset ("Azurefilm PLA Wood") only accepts profiles naming that
  // brand — otherwise every PLA profile on the printer would answer for it.
  if (brand.isNotEmpty) {
    return name.contains(brand) && name.contains(material);
  }

  if (name.contains(fullName) || name.contains(material)) return true;
  return (_materialAliases[material] ?? const [])
      .any((alias) => name.contains(alias));
}

/// Fold the duplicate rows a multi-nozzle printer reports for one calibration,
/// preferring the copy belonging to the nozzle this slot feeds.
List<KProfile> _dedupe(Iterable<KProfile> profiles, int? extruderId) {
  final byOption = <String, KProfile>{};
  for (final profile in profiles) {
    final existing = byOption[profile.optionId];
    final betterNozzle = existing != null &&
        extruderId != null &&
        profile.extruderId == extruderId &&
        existing.extruderId != extruderId;
    if (existing == null || betterNozzle) byOption[profile.optionId] = profile;
  }
  return byOption.values.toList();
}
