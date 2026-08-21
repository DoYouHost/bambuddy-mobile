
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
    // Heater history (server commit 090c180e). The threshold is written in the
    // *old* numbering because that is where the route shipped — v0.2.4.8, two
    // releases before the scheme changed to 1.2.5. Every 1.x version outranks
    // it, so this one row covers both schemes; writing it as (1, 2, 4, 8) would
    // hide the chart on exactly the 0.2.4.x servers that have it.
    ServerFeature.printerSensorHistory: (0, 2, 4, 8),
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

  bool get supportsTriStateCalibration =>
      supports(ServerFeature.triStateCalibration);

  /// Highest chamber target the server will accept, in °C.
  ///
  /// The one gate that is a value rather than a yes/no, and the one that cannot
  /// be settled by observation: no response reveals the ceiling, so the only
  /// probe would be sending a target we expect to be refused — and that is a
  /// real command that would heat somebody's chamber to ask a question. The
  /// bound is a `Query(le=…)`, so an older server answers **422** for 61-65
  /// rather than clamping. 60 whenever we don't know.
  int get chamberMaxTargetC => supports(ServerFeature.chamberTemp65) ? 65 : 60;

  bool get supportsCrossModelVariants =>
      supports(ServerFeature.crossModelVariants);

  bool get supportsSliceLayoutOptions =>
      supports(ServerFeature.sliceLayoutOptions);

  bool get supportsProcessOverrides => supports(ServerFeature.processOverrides);

  List<int> get _base => [major, minor, patch, micro];

  /// Prerelease status deliberately ignored — see [supportsTriStateCalibration].
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
