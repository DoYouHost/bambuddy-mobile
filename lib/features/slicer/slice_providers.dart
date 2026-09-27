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
final slicerEnabledProvider = serverGate<bool>(
  (settings) => settings.settingBool('use_slicer_api'),
);

/// Preset options for the slice modal. Kept alive while a sheet is open; the
/// modal can force a [refresh] to bypass the server's cloud cache.
final slicerPresetsProvider = FutureProvider.autoDispose<UnifiedPresets>(
  (ref) => ref.watch(slicerRepositoryProvider).presets(),
);

/// Slice capabilities for a single archive — gates the archive slice button
/// (hidden for plain gcode.3mf prints that can't be re-sliced).
final archiveCapabilitiesProvider = FutureProvider.autoDispose
    .family<ArchiveCapabilities, int>(
      (ref, archiveId) =>
          ref.watch(slicerRepositoryProvider).archiveCapabilities(archiveId),
    );

/// Printer model codes the user actually owns (e.g. {"X2D"}), for narrowing the
/// preset lists. Upper-cased because it is only ever compared against preset
/// names, never sent — unlike the spool form's `printerModelsProvider`, which
/// reads the same fleet and must keep the server's spelling.
final ownedPrinterCodesProvider = FutureProvider.autoDispose<Set<String>>((
  ref,
) async {
  final printers = await ref.watch(printersRepositoryProvider).fetchPrinters();
  return {
    for (final p in printers)
      if (p.model != null && p.model!.trim().isNotEmpty)
        p.model!.trim().toUpperCase(),
  };
});

/// Filaments the user owns that carry a slicer-preset mapping: the filament
/// list, the per-slot auto-pick, and what colour each slot really prints in
/// (`sliceFilamentColours`). Empty on a backend without the mapping (Spoolman),
/// where the modal falls back to printer compatibility alone.
///
/// Deduplicated by name **and** colour, because one preset covers every spool
/// of that filament and neither reader can ask for a colour dropped here.
final ownedFilamentsProvider = FutureProvider.autoDispose<List<OwnedFilament>>((
  ref,
) async {
  final spools = await ref.watch(inventoryRepositoryProvider).fetchSpools();
  final out = <OwnedFilament>[];
  final seen = <(String, String?)>{};
  for (final s in spools) {
    final name = s.slicerFilamentName?.trim();
    if (name == null || name.isEmpty || !seen.add((name, s.rgba))) continue;
    out.add((name: name, material: s.material, color: s.rgba));
  }
  return out;
});

/// A 3MF the app asks about, and which plate of it the answer should describe:
/// `isArchive` picks the route (`/archives/…` vs `/library/files/…`), `id` the
/// file, `plate` the plate inside it.
///
/// A record because it is a provider family key and has to compare by value —
/// the plate included, since plate 2's answer is a different answer.
typedef PlateSource = ({bool isArchive, int id, int plate});

/// Filament slots a model needs, keyed by [PlateSource] — the per-colour pickers
/// in the slice modal and the queue mapping sheet. Each plate of a multi-plate
/// file consumes its own slots, so the wrong key offers the wrong pickers (see
/// `SlicerRepository.filamentRequirements`).
final filamentRequirementsProvider = FutureProvider.autoDispose
    .family<List<FilamentRequirement>, PlateSource>(
      (ref, key) => ref
          .watch(slicerRepositoryProvider)
          .filamentRequirements(
            id: key.id,
            isArchive: key.isArchive,
            plateId: key.plate,
          ),
    );

/// The plates of one 3MF, keyed by `(isArchive, id)` — no plate in the key,
/// since this is the read that says which plates there are.
///
/// Best-effort in the repository: no route, not a 3MF and no permission all
/// answer [PlateList.none], which callers read as "no plate to choose".
final plateListProvider = FutureProvider.autoDispose
    .family<PlateList, (bool, int)>((ref, key) {
      final (isArchive, id) = key;
      return isArchive
          ? ref.watch(archiveRepositoryProvider).plates(id)
          : ref.watch(libraryRepositoryProvider).plates(id);
    });

/// What the source 3MF was prepared with — the "slice as designed" switch.
///
/// A view on [plateListProvider] rather than a request of its own: both answers
/// come out of the same `…/plates` payload, and reading it twice cost two round
/// trips and two zip parses for one question.
final embeddedSettingsProvider = FutureProvider.autoDispose
    .family<EmbeddedSettings, (bool, int)>(
      (ref, key) async =>
          (await ref.watch(plateListProvider(key).future)).embedded,
    );

/// A process preset reduced to what `/slicer/preset-values` takes. A record
/// rather than a [SlicerPreset] because it is a provider family key and has to
/// compare by value — `SlicerPreset` compares by identity, so the same preset
/// would refetch on every rebuild.
typedef ProcessPresetRef = (String source, String id);

/// The vendored OrcaSlicer option metadata, loaded on first use. Null when the
/// assets failed to load — a build error, not a server one, so callers keep the
/// settings screen out of reach rather than open an empty one. Not
/// `autoDispose`: the catalog is cached per isolate either way.
final processSchemaProvider = FutureProvider<ProcessSchemaCatalog?>((
  ref,
) async {
  final catalog = ProcessSchemaCatalog.instance;
  await catalog.load();
  return catalog.isLoaded ? catalog : null;
});

/// The picked process preset's effective values, with its `inherits:` chain
/// flattened by the server's slicer sidecar.
///
/// Null means the screen must not be offered at all — see
/// [SlicerRepository.presetValues]; a `resolved: false` is not that. Keyed by
/// preset, so changing it re-reads the baseline the fields are edited against.
final presetValuesProvider = FutureProvider.autoDispose
    .family<PresetValues?, ProcessPresetRef>(
      (ref, preset) => ref
          .watch(slicerRepositoryProvider)
          .presetValues(
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
final processSettingsAvailableProvider = Provider<AsyncValue<bool>>((ref) {
  final server = ref.watch(processOverridesProvider);
  // A server that said no — or could not be asked — costs no 164 KB decode.
  if (server.hasError || server.valueOrNull == false) return server;
  final schema = ref.watch(processSchemaProvider);
  return server.and(schema.whenData((catalog) => catalog != null));
});
