import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/archive_capabilities.dart';
import '../../core/models/slicer_preset.dart';
import '../../providers.dart';

/// Whether server-side slicing is enabled (`use_slicer_api`). Gates every slice
/// button in the app. Cached for the session — the setting rarely changes.
final slicerEnabledProvider = FutureProvider<bool>(
  (ref) => ref.watch(slicerRepositoryProvider).isEnabled(),
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

/// Slicer-filament-preset names the user owns (from inventory spools), used to
/// limit the filament list to owned filaments. Empty for backends (Spoolman)
/// that don't expose a slicer mapping — the modal then falls back to
/// printer-compatibility only.
final ownedFilamentNamesProvider = FutureProvider.autoDispose<Set<String>>(
  (ref) async {
    final spools = await ref.watch(inventoryRepositoryProvider).fetchSpools();
    return {
      for (final s in spools)
        if (s.slicerFilamentName != null &&
            s.slicerFilamentName!.trim().isNotEmpty)
          s.slicerFilamentName!.trim(),
    };
  },
);
