import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/archive_capabilities.dart';
import '../../core/settings/server_settings.dart';
import '../../core/models/embedded_settings.dart';
import '../../core/models/filament_requirement.dart';
import '../../core/models/plate_list.dart';
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
      (await ref.watch(serverSettingsProvider.future))
          .settingBool('use_slicer_api'),
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
///
/// Upper-cased because it is only ever compared against preset names, never
/// sent — the spool form's `printerModelsProvider` reads the same fleet and
/// must keep the server's own spelling, and says there why.
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

/// A 3MF the app asks about, and which plate of it the answer should describe:
/// `isArchive` picks the route (`/archives/…` vs `/library/files/…`), `id` the
/// file, `plate` the plate inside it.
///
/// A record rather than three loose arguments because it is a provider family
/// key and has to compare by value — and because the plate belongs to the key:
/// the answer for plate 2 is a different answer, not a variation on plate 1's.
typedef PlateSource = ({bool isArchive, int id, int plate});

/// Filament slots a model needs, keyed by [PlateSource]. Drives the per-colour
/// pickers in the slice modal and the queue mapping sheet for multicolor prints.
///
/// The plate is part of the key on purpose: on a multi-plate file each plate
/// consumes its own set of slots, so asking for the wrong one offers the wrong
/// pickers (see `SlicerRepository.filamentRequirements`).
final filamentRequirementsProvider = FutureProvider.autoDispose
    .family<List<FilamentRequirement>, PlateSource>(
  (ref, key) => ref.watch(slicerRepositoryProvider).filamentRequirements(
        id: key.id,
        isArchive: key.isArchive,
        plateId: key.plate,
      ),
);

/// The plates of one 3MF, keyed by `(isArchive, id)` — no plate in the key,
/// since this is the read that says which plates there are.
///
/// Best-effort in the repository: a server without the route, a file that is not
/// a 3MF and a missing permission all answer [PlateList.none], which callers
/// read as "no plate to choose" and render exactly as they did before plates
/// existed.
final plateListProvider =
    FutureProvider.autoDispose.family<PlateList, (bool, int)>(
  (ref, key) {
    final (isArchive, id) = key;
    return isArchive
        ? ref.watch(archiveRepositoryProvider).plates(id)
        : ref.watch(libraryRepositoryProvider).plates(id);
  },
);

/// What the source 3MF was prepared with — the "slice as designed" switch.
///
/// A view on [plateListProvider] rather than a request of its own: both answers
/// come out of the same `…/plates` payload, and reading it twice meant two
/// round trips and two zip parses for one question. Riverpod caches the
/// underlying read, so a screen watching both gets one.
final embeddedSettingsProvider =
    FutureProvider.autoDispose.family<EmbeddedSettings, (bool, int)>(
  (ref, key) async => (await ref.watch(plateListProvider(key).future)).embedded,
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
