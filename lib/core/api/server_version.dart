/// A server capability the app has to gate, because an older bambuddy either
/// refuses it or — worse — accepts the request and silently ignores it.
///
/// Paired with the release that introduced it in [ServerVersion.introducedIn].
enum ServerFeature {
  /// Queue and settings store `bed_levelling` / `flow_cali` /
  /// `nozzle_offset_cali` as `off`/`on`/`auto` instead of booleans. Sending
  /// `auto` to a server that stores booleans is a 422.
  triStateCalibration,

  /// The chamber accepts targets up to 65 °C instead of 60.
  chamberTemp65,

  /// `POST /library/variant-groups` and the `variants[]` field on queue create:
  /// several sliced files, one job, whichever printer frees up first.
  crossModelVariants,

  /// `auto_orient` / `auto_arrange` on `SliceRequest`.
  ///
  /// `SliceRequest` does not forbid unknown fields, so an older server drops
  /// these **without a word**. That is why the controls must be hidden rather
  /// than merely left unsent: a switch that appears to work and changes nothing
  /// is worse than no switch.
  sliceLayoutOptions,

  /// `process_overrides` on `SliceRequest`, plus the `GET
  /// /slicer/preset-values` that seeds the panel. Same silent-drop hazard as
  /// [sliceLayoutOptions]; the endpoint 404s on older servers, which
  /// `SlicerRepository` uses as the outranking observation.
  processOverrides,

  /// `GET /printer-sensor-history/{id}` — recorded nozzle / bed / chamber
  /// readings behind the temperature tiles' chart shortcut.
  ///
  /// The route 404s before it, and reading it also needs
  /// `printer_sensor_history:read`, so `HeaterHistoryRepository` treats both
  /// answers as outranking this row — the version cannot see the permission.
  printerSensorHistory,

  /// `GET /users/slim` — id + username only, so `created_by_id` can be shown as
  /// a name (server #1894).
  ///
  /// Listed for completeness of this table, but **`StatsRepository` decides by
  /// probing and that must not be replaced with this**. Two reasons, both
  /// load-bearing:
  ///
  /// - The route existing is not the same as *this session* being allowed to
  ///   read it. A 1.2.6 server still answers 403 to a caller holding neither
  ///   `users:read_slim` nor `users:read`, and the probe's answer covers both
  ///   questions where a version can only answer the first.
  /// - Using this to skip the attempt would resurrect the numbering trap: a
  ///   server whose reported version parses below 1.2.6 while actually serving
  ///   the route would be pinned to the full listing forever — which an API key
  ///   is refused outright, removing exactly the picker #1894 added.
  ///
  /// See `docs/plans/13-users-slim-and-api-key-identity.md`.
  usersSlimListing,

  /// `cost` / `energy_kwh` / `energy_cost` on a print-log entry, and the
  /// `sort_by` / `sort_dir` query params that go with them (server #2636).
  ///
  /// Both halves are silent below it, in the two different ways that make a
  /// version gate necessary rather than optional:
  ///
  /// - The three fields were written to the table all along but never named by
  ///   the serialiser, so they arrive absent — which parses as `null`, exactly
  ///   like a run made without a smart plug. Showing the columns anyway would
  ///   put "no energy recorded" against every row of a server that records it.
  /// - `sort_by` on an older server is an unknown query param, and FastAPI
  ///   drops those without a word: the list comes back `created_at desc`
  ///   whatever was asked for. Same silent-drop class as [sliceLayoutOptions].
  printLogCostEnergy,

  /// `starting_position` on `POST /inventory/labels` / `POST /spoolman/labels`
  /// — resume a part-used Avery sheet instead of always printing from slot 1.
  ///
  /// Gated for the same reason as [sliceLayoutOptions]: `LabelRequest` forbids
  /// no extra fields, so an older server takes the number, says nothing, and
  /// prints from position 1 anyway. Nothing in the reply distinguishes the two
  /// — both are a valid PDF — so there is no observation to prefer over this
  /// row, and a control that quietly wastes a sheet of labels is worse than one
  /// that is not offered.
  labelStartingPosition,

  /// `POST /printers/{id}/files/download-job` and the two routes that go with
  /// it — a printer-file download prepared in the background instead of behind
  /// a held request (server #2850).
  ///
  /// A route family, so an older server answers **404** and
  /// `PrinterFilesRepository` prefers that observation to this row. Being
  /// early costs nothing either way: the legacy `download-zip` is still there
  /// on every server, including the newest, and is what the app falls back to.
  printerFilesDownloadJob,

  /// `GET/POST/DELETE /scheduled-dryings` — a manual AMS drying run the
  /// scheduler starts later (server #2638).
  ///
  /// A whole route family rather than a field, so an older server answers
  /// **404** and `ScheduledDryingRepository` prefers that observation to this
  /// row. The gate exists for the moment before the first listing comes back:
  /// the drying sheet has to decide whether to offer "Later" at all, and an
  /// offer that ends in a 404 costs the user a filled-in form.
  scheduledDryings,

  /// `GET /archives/{id}/printer-media` and the media-download token pair —
  /// the recordings a finished print can still be given, off the printer's own
  /// storage (server #2853).
  ///
  /// A route family again, so an older server answers **404** and
  /// `ArchiveRepository` prefers that observation to this row. Being early
  /// would cost a sheet that opens onto nothing, so the archive sheet hides
  /// the entry until this says yes.
  archivePrinterMedia,

  /// `GET /location-ha-sensors/` and the per-location readings behind it — the
  /// thermometer or hygrometer a storage location can be given, read through
  /// the server's Home Assistant connection (server #2827).
  ///
  /// A route family once more, so an older server answers **404** and
  /// `LocationSensorsRepository` prefers that observation to this row. The
  /// gate only spares that one 404 on a server known to be older: nothing is
  /// offered until the listing comes back non-empty, so being early here costs
  /// a request and never a control.
  locationHaSensors,

  /// `GET/PUT /inventory/spools/{id}/filament-presets` and the Spoolman twin —
  /// the slicer preset a spool uses on one printer *model*, instead of the one
  /// value it carries for the whole fleet (server commit a7b56333).
  ///
  /// A route pair, so an older server answers **404** and
  /// `InventoryRepository` prefers that observation to this row. Being early
  /// costs a section that offers to write somewhere the write would 404, so
  /// the spool form hides it until this says yes.
  spoolModelPresets,
}

/// A bambuddy server version, comparable across both numbering schemes the
/// project has used (`0.2.4.9`, `1.2.5.1`) plus daily builds like
/// `1.2.6b1-daily.20260729`.
///
/// Parsing and ordering mirror `updates.py::parse_version` / `is_newer_version`
/// so that "newer" means here what it means there — including the rule that a
/// release outranks any prerelease of the same base.
class ServerVersion implements Comparable<ServerVersion> {
  const ServerVersion({
    required this.raw,
    required this.major,
    required this.minor,
    required this.patch,
    required this.micro,
    required this.isPrerelease,
    required this.prereleaseNum,
  });

  /// Verbatim, because a build the parser flattens still has to be
  /// reproducible from what the About screen and the log show.
  final String raw;

  final int major;
  final int minor;
  final int patch;

  /// Fourth component (`0.2.4.**9**`), `0` when the version has only three.
  final int micro;

  final bool isPrerelease;

  /// The `N` of `b1` / `rc2`; `0` for a release.
  final int prereleaseNum;

  static final _daily = RegExp(r'-daily\.\d+$');
  static final _leadingV = RegExp(r'^v+');
  static final _pattern = RegExp(
    r'^(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?(?:b|beta|alpha|rc)?(\d+)?',
  );
  static final _letter = RegExp('[a-zA-Z]');

  /// Never throws: this runs on a value a server handed us.
  static ServerVersion? tryParse(String? value) {
    if (value == null) return null;
    final raw = value.trim();
    if (raw.isEmpty) return null;

    // Same order the server strips in: `v` prefix, then the daily suffix.
    final cleaned = raw.replaceFirst(_leadingV, '').replaceFirst(_daily, '');
    final m = _pattern.firstMatch(cleaned);
    if (m == null) return null;

    return ServerVersion(
      raw: raw,
      major: int.parse(m.group(1)!),
      minor: int.parse(m.group(2)!),
      patch: int.parse(m.group(3)!),
      micro: int.tryParse(m.group(4) ?? '') ?? 0,
      // Matches the server: any letter left after the daily suffix is stripped
      // marks a prerelease, so `1.2.6b1` counts and a bare `1.2.6` does not.
      isPrerelease: _letter.hasMatch(cleaned),
      prereleaseNum: int.tryParse(m.group(5) ?? '') ?? 0,
    );
  }

  /// Which release introduced each capability — the whole version→capability
  /// map, in one place, so adding a gate is a row here rather than a new
  /// comparison somewhere in the app.
  ///
  /// Values are the **numeric base only** (`major, minor, patch, micro`),
  /// because that is all [supports] compares. Deliberately: a feature ships
  /// during its release's beta cycle, so `1.2.6b1` must count as 1.2.6 — the
  /// alternative takes `auto` away from a server that stores it, or hides the
  /// variant grouping from a server that has it.
  ///
  /// The values are *thresholds*, not observations. Where the server reveals a
  /// capability in its own payloads, that reading outranks this table — see
  /// `QueueRepository.supportsTriStateCalibration` and
  /// `LibraryRepository.supportsCrossModelVariants`. This is the fallback for
  /// before anything has been seen, and for the one case ([chamberMaxTargetC])
  /// where nothing can be seen at all.
  static const introducedIn = <ServerFeature, (int, int, int, int)>{
    // Queue and settings store the three calibrations as off/on/auto rather
    // than as booleans.
    ServerFeature.triStateCalibration: (1, 2, 5, 0),
    // MAX_CHAMBER_TEMP_C 60 → 65 (server commit b04664c6).
    ServerFeature.chamberTemp65: (1, 2, 6, 0),
    // Cross-model queue alternatives + library variant groups (server #671).
    ServerFeature.crossModelVariants: (1, 2, 6, 0),
    // auto_orient / auto_arrange on SliceRequest (server #2548).
    ServerFeature.sliceLayoutOptions: (1, 2, 6, 0),
    // process_overrides on SliceRequest + GET /slicer/preset-values.
    ServerFeature.processOverrides: (1, 2, 6, 0),
    // GET /users/slim (server #1894) — probed, not gated on this. See the enum.
    ServerFeature.usersSlimListing: (1, 2, 6, 0),
    // Print-log cost/energy fields + sortable columns (server #2636, commit
    // a08d3e62).
    ServerFeature.printLogCostEnergy: (1, 2, 6, 0),
    // Heater history (server commit 090c180e). The threshold is written in the
    // *old* numbering because that is where the route shipped — v0.2.4.8, two
    // releases before the scheme changed to 1.2.5. Every 1.x version outranks
    // it, so this one row covers both schemes; writing it as (1, 2, 4, 8) would
    // hide the chart on exactly the 0.2.4.x servers that have it.
    ServerFeature.printerSensorHistory: (0, 2, 4, 8),
    // starting_position on the two label routes (server #2879). Like the rows
    // above it this landed partway through the 1.2.6 beta cycle, which the
    // numeric base cannot split any finer — a 1.2.6b1 daily older than the
    // commit is told yes and prints from position 1. That is the same sheet it
    // prints today, so the cost of the gate being early is a wasted sheet
    // rather than a refused request.
    ServerFeature.labelStartingPosition: (1, 2, 6, 0),
    // Prepared printer-file downloads (server #2850). Landed inside the 1.2.6
    // beta cycle; like /scheduled-dryings the route answers 404 below it and
    // the repository records that instead of this row.
    ServerFeature.printerFilesDownloadJob: (1, 2, 6, 0),
    // /scheduled-dryings (server #2638, commit d37ce94f). Landed after the
    // 1.2.5.3 release, inside the 1.2.6 beta cycle — same caveat as the rows
    // above, except that here being early is free: the route answers 404 and
    // the repository records that in place of this row.
    ServerFeature.scheduledDryings: (1, 2, 6, 0),
    // Archive printer-media search + the media-download token (server #2853,
    // commit 55cc64c8). Landed in the same 1.2.6 beta cycle as the rows above,
    // with the same caveat: the routes answer 404 below it and the repository
    // records that in place of this row.
    ServerFeature.archivePrinterMedia: (1, 2, 6, 0),
    // Storage-location Home Assistant sensors (server #2827, commit 54af3146).
    // Same 1.2.6 beta cycle and same caveat as the rows above.
    ServerFeature.locationHaSensors: (1, 2, 6, 0),
    // Per-printer-model spool presets (server commit a7b56333), landed in the
    // same 1.2.6 beta cycle as the rows above and answering 404 below it, so
    // the observation the repository records outranks this row.
    ServerFeature.spoolModelPresets: (1, 2, 6, 0),
  };

  /// Whether this server is at or past the release that introduced [feature].
  bool supports(ServerFeature feature) {
    final since = introducedIn[feature];
    // An unmapped feature is a programming error, but answering "no" keeps the
    // app on the contract every server generation accepts.
    if (since == null) return false;
    final threshold = [since.$1, since.$2, since.$3, since.$4];
    final mine = _base;
    for (var i = 0; i < mine.length; i++) {
      final c = mine[i].compareTo(threshold[i]);
      if (c != 0) return c > 0;
    }
    return true;
  }

  /// Highest chamber target the server will accept, in °C.
  ///
  /// The one gate that is a value rather than a yes/no, and the one that cannot
  /// be settled by observation: no response reveals the ceiling, so the only
  /// probe would be sending a target we expect to be refused — and that is a
  /// real command that would heat somebody's chamber to ask a question. The
  /// bound is a `Query(le=…)`, so an older server answers **422** for 61-65
  /// rather than clamping. 60 whenever we don't know.
  int get chamberMaxTargetC => supports(ServerFeature.chamberTemp65) ? 65 : 60;

  List<int> get _base => [major, minor, patch, micro];

  /// Prerelease status deliberately ignored — see [introducedIn].
  int _compareBase(ServerVersion other) {
    final mine = _base;
    final theirs = other._base;
    for (var i = 0; i < mine.length; i++) {
      final c = mine[i].compareTo(theirs[i]);
      if (c != 0) return c;
    }
    return 0;
  }

  @override
  int compareTo(ServerVersion other) {
    final base = _compareBase(other);
    if (base != 0) return base;
    // Same base: a release outranks a prerelease, then the higher beta number.
    if (isPrerelease != other.isPrerelease) return isPrerelease ? -1 : 1;
    return prereleaseNum.compareTo(other.prereleaseNum);
  }

  bool operator >=(ServerVersion other) => compareTo(other) >= 0;
  bool operator <(ServerVersion other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is ServerVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch &&
      other.micro == micro &&
      other.isPrerelease == isPrerelease &&
      other.prereleaseNum == prereleaseNum;

  @override
  int get hashCode =>
      Object.hash(major, minor, patch, micro, isPrerelease, prereleaseNum);

  @override
  String toString() => raw;
}
