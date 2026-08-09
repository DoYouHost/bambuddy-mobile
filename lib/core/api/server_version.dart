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

  /// First version whose queue and settings schemas carry the tri-state
  /// calibration options instead of booleans.
  static const triStateCalibration = ServerVersion(
    raw: '1.2.5',
    major: 1,
    minor: 2,
    patch: 5,
    micro: 0,
    isPrerelease: false,
    prereleaseNum: 0,
  );

  /// Numeric base only, so a `1.2.5b1` prerelease counts as supporting it: the
  /// change landed during that cycle, and treating a beta as the older shape
  /// would send a boolean where the user asked for `auto`.
  bool get supportsTriStateCalibration =>
      _compareBase(triStateCalibration) >= 0;

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
