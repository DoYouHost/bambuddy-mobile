import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/archive_capabilities.dart';
import '../../core/models/embedded_settings.dart';
import '../../core/models/filament_requirement.dart';
import '../../core/models/slicer_preset.dart';
import '../../core/slicer/process_schema_catalog.dart';
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
/// mapping, used to limit the filament list to owned filaments, to auto-pick
/// per slot by material/colour, and to say what colour each slot actually
/// prints in (`sliceFilamentColours`). Empty for backends (Spoolman) without a
/// slicer mapping — the modal then falls back to printer-compatibility only.
///
/// Deduplicated by name **and** colour, not by name alone: one preset covers
/// every spool of that filament, so collapsing on the name kept an arbitrary
/// one of a shelf full of colours and threw the rest away. Both readers want
/// the colours — the auto-pick to find the closest to the plate, the request to
/// record what is really being printed — and neither can ask for a colour that
/// was dropped here.
final ownedFilamentsProvider = FutureProvider.autoDispose<List<OwnedFilament>>(
  (ref) async {
    final spools = await ref.watch(inventoryRepositoryProvider).fetchSpools();
    final out = <OwnedFilament>[];
    final seen = <(String, String?)>{};
    for (final s in spools) {
      final name = s.slicerFilamentName?.trim();
      if (name == null || name.isEmpty || !seen.add((name, s.rgba))) continue;
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

/// What the source 3MF was prepared with, keyed by `(isArchive, id)` like
/// [filamentRequirementsProvider]. Drives the "slice as designed" switch.
final embeddedSettingsProvider =
    FutureProvider.autoDispose.family<EmbeddedSettings, (bool, int)>(
  (ref, key) => ref.watch(slicerRepositoryProvider).embeddedSettings(
        id: key.$2,
        isArchive: key.$1,
      ),
);

/// A process preset reduced to what `/slicer/preset-values` takes. A record
/// rather than a [SlicerPreset] because it is a provider family key and has to
/// compare by value — `SlicerPreset` compares by identity, so the same preset
/// would refetch on every rebuild.
typedef ProcessPresetRef = (String source, String id);

/// The vendored OrcaSlicer option metadata, loaded on first use.
///
/// Null when the assets failed to load, which is a build error rather than a
/// server problem — callers keep the settings screen out of reach rather than
/// open an empty one. Not `autoDispose`: the catalog is cached per isolate
/// regardless, so disposing the provider would only drop the handle to it.
final processSchemaProvider = FutureProvider<ProcessSchemaCatalog?>(
  (ref) async {
    final catalog = ProcessSchemaCatalog.instance;
    await catalog.load();
    return catalog.isLoaded ? catalog : null;
  },
);

/// The picked process preset's effective values, with its `inherits:` chain
/// flattened by the server's slicer sidecar.
///
/// Null means the screen must not be offered at all — see
/// [SlicerRepository.presetValues]. A `resolved: false` value is not that: the
/// screen opens on schema defaults and says why.
///
/// `autoDispose` and keyed by preset, so changing the process preset in the
/// sheet re-reads the baseline the fields are edited against.
final presetValuesProvider =
    FutureProvider.autoDispose.family<PresetValues?, ProcessPresetRef>(
  (ref, preset) => ref.watch(slicerRepositoryProvider).presetValues(
        // Only source and id reach the wire.
        SlicerPreset(source: preset.$1, id: preset.$2, name: ''),
      ),
);

/// Whether the process-settings screen can be offered: the server accepts
/// `process_overrides` **and** the vendored metadata actually loaded.
///
/// Both halves have to hold, and they fail for unrelated reasons — an older
/// server, or a broken asset in our own build. One gate keeps the slice sheet
/// from having to know that.
final processSettingsAvailableProvider = FutureProvider.autoDispose<bool>(
  (ref) async {
    if (!await ref.watch(processOverridesProvider.future)) return false;
    return await ref.watch(processSchemaProvider.future) != null;
  },
);
