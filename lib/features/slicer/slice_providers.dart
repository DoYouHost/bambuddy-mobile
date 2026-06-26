import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/archive_capabilities.dart';
import '../../core/models/filament_requirement.dart';
import '../../core/models/slicer_preset.dart';
import '../../providers.dart';

/// A filament the user owns, reduced to what the slice modal needs: the slicer
/// preset name it maps to, its material, and its colour (for per-slot auto-pick
/// in multicolor prints).
typedef OwnedFilament = ({String name, String material, String? color});

/// Whether server-side slicing is enabled (`use_slicer_api`). Gates every slice
/// button in the app. Cached for the session — the setting rarely changes.
final slicerEnabledProvider = FutureProvider<bool>(
  (ref) async =>
      (await ref.watch(serverSettingsProvider.future))['use_slicer_api'] == true,
);

/// Preset options for the slice modal. Kept alive while a sheet is open; the
/// modal can force a [refresh] to bypass the server's cloud cache.
final slicerPresetsProvider = FutureProvider.autoDispose<UnifiedPresets>(
  (ref) => ref.watch(slicerRepositoryProvider).presets(),
);

/// Slice capabilities for a single archive — gates the archive slice button
/// (hidden for plain gcode.3mf prints that can't be re-sliced).
final archiveCapabilitiesProvider =
    FutureProvider.autoDispose.family<ArchiveCapabilities, int>(
  (ref, archiveId) =>
      ref.watch(slicerRepositoryProvider).archiveCapabilities(archiveId),
);

/// Printer model codes the user actually owns (e.g. {"X2D"}), used to narrow
/// the printer/process/filament lists to fitting presets.
final ownedPrinterCodesProvider = FutureProvider.autoDispose<Set<String>>(
  (ref) async {
    final printers = await ref.watch(printersRepositoryProvider).fetchPrinters();
    return {
      for (final p in printers)
        if (p.model != null && p.model!.trim().isNotEmpty)
          p.model!.trim().toUpperCase(),
    };
  },
);

/// Filaments the user owns (from inventory spools) that carry a slicer-preset
/// mapping, used to limit the filament list to owned filaments and to auto-pick
/// per slot by material/colour. Empty for backends (Spoolman) without a slicer
/// mapping — the modal then falls back to printer-compatibility only.
final ownedFilamentsProvider = FutureProvider.autoDispose<List<OwnedFilament>>(
  (ref) async {
    final spools = await ref.watch(inventoryRepositoryProvider).fetchSpools();
    final out = <OwnedFilament>[];
    final seen = <String>{};
    for (final s in spools) {
      final name = s.slicerFilamentName?.trim();
      if (name == null || name.isEmpty || !seen.add(name)) continue;
      out.add((name: name, material: s.material, color: s.rgba));
    }
    return out;
  },
);

/// Filament slots a model needs, keyed by `(isArchive, id)`. Drives the
/// per-colour pickers in the slice modal for multicolor prints.
final filamentRequirementsProvider = FutureProvider.autoDispose
    .family<List<FilamentRequirement>, (bool, int)>(
  (ref, key) => ref.watch(slicerRepositoryProvider).filamentRequirements(
        id: key.$2,
        isArchive: key.$1,
      ),
);
