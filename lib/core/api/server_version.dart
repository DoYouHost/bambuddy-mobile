/// A server capability the app has to gate, because an older bambuddy either
/// refuses it or — worse — accepts the request and silently ignores it.
///
/// Paired with the release that introduced it in [ServerVersion.introducedIn].
/// Why each row exists, what an older server does without it and what being
/// early costs are in `docs/server-gates.md` — read that before adding a gate.
enum ServerFeature {
  /// `bed_levelling` / `flow_cali` / `nozzle_offset_cali` as `off`/`on`/`auto`
  /// instead of booleans; `auto` is a 422 below it.
  triStateCalibration,

  /// The chamber accepts targets up to 65 °C instead of 60.
  chamberTemp65,

  /// `POST /library/variant-groups` and `variants[]` on queue create.
  crossModelVariants,

  /// `auto_orient` / `auto_arrange` on `SliceRequest`, dropped silently below.
  sliceLayoutOptions,

  /// `process_overrides` on `SliceRequest` + `GET /slicer/preset-values`.
  processOverrides,

  /// `GET /printer-sensor-history/{id}` — the temperature tiles' chart.
  printerSensorHistory,

  /// `GET /users/slim`. **`StatsRepository` probes for this and must keep
  /// doing so** — see `docs/server-gates.md`.
  usersSlimListing,

  /// `cost` / `energy_kwh` / `energy_cost` on a print-log entry, plus
  /// `sort_by` / `sort_dir`; both halves are silent below it.
  printLogCostEnergy,

  /// `starting_position` on the two label routes, taken and ignored below it.
  labelStartingPosition,

  /// `POST /printers/{id}/files/download-job` and the two routes with it.
  printerFilesDownloadJob,

  /// `GET/POST/DELETE /scheduled-dryings`.
  scheduledDryings,

  /// `GET /archives/{id}/printer-media` and the media-download token pair.
  archivePrinterMedia,

  /// `GET /location-ha-sensors/` and the per-location readings behind it.
  locationHaSensors,

  /// `GET/PUT /inventory/spools/{id}/filament-presets` and the Spoolman twin.
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

  /// Which release introduced each capability. Values are the **numeric base
  /// only**, because that is all [supports] compares: a feature ships during
  /// its release's beta cycle, so `1.2.6b1` counts as 1.2.6.
  ///
  /// Thresholds, not observations — the server revealing a capability outranks
  /// this table. Each row's server issue, and what being early costs, are in
  /// `docs/server-gates.md`.
  static const introducedIn = <ServerFeature, (int, int, int, int)>{
    ServerFeature.triStateCalibration: (1, 2, 5, 0),
    ServerFeature.chamberTemp65: (1, 2, 6, 0),
    ServerFeature.crossModelVariants: (1, 2, 6, 0),
    ServerFeature.sliceLayoutOptions: (1, 2, 6, 0),
    ServerFeature.processOverrides: (1, 2, 6, 0),
    ServerFeature.usersSlimListing: (1, 2, 6, 0),
    ServerFeature.printLogCostEnergy: (1, 2, 6, 0),
    // Not a typo: the route shipped in v0.2.4.8, before the scheme changed to
    // 1.2.5, and every 1.x outranks that. `(1, 2, 4, 8)` would hide the chart
    // on the 0.2.4.x servers that serve it.
    ServerFeature.printerSensorHistory: (0, 2, 4, 8),
    ServerFeature.labelStartingPosition: (1, 2, 6, 0),
    ServerFeature.printerFilesDownloadJob: (1, 2, 6, 0),
    ServerFeature.scheduledDryings: (1, 2, 6, 0),
    ServerFeature.archivePrinterMedia: (1, 2, 6, 0),
    ServerFeature.locationHaSensors: (1, 2, 6, 0),
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

  /// Highest chamber target the server will accept, in °C — the one gate no
  /// observation can settle, since the only probe would be a real command
  /// heating somebody's chamber. See `docs/server-gates.md`.
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
