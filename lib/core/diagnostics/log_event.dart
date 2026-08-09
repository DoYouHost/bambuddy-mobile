import 'dart:convert';
import 'dart:math';

/// Subsystem a record came from, not an isolate — which isolate wrote it is the
/// stream's business. Notifications get their own [notif] even though only the
/// background service produces them: "the app buried me in notifications"
/// should be one look at one lane's count.
///
/// The names are wire values, and declaration order is the order the review
/// screen lists them in.
enum LogSource { http, ws, ui, notif, fgs, err, app }

/// Severity. [LogLevel.info] is the default and is omitted from the encoded
/// record; most lines are info, so spelling it out would pad the upload.
enum LogLevel { debug, info, warn, error }

/// Which isolate produced the stream; `docs/diagnostics-log.md` describes what
/// each one is and how the export merges them.
enum LogStream { ui, fgs, action }

/// Shape of the server host. A bare IP means a direct LAN setup, a name means
/// DNS or a reverse proxy in front — a distinction that explains a good share
/// of TLS reports and says nothing about who the user is.
enum HostKind { ip, name }

/// What we keep from the server URL: enough to reason about the setup, nothing
/// that identifies the user's network. The address itself never enters a log.
class ServerFingerprint {
  const ServerFingerprint({
    required this.scheme,
    required this.hostKind,
    this.port,
  });

  /// Returns null for anything unparseable — a fingerprint is a nice-to-have,
  /// never a reason to fail the recording.
  static ServerFingerprint? tryParse(String? url) {
    if (url == null || url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    return ServerFingerprint(
      scheme: uri.scheme,
      hostKind: _looksLikeIp(uri.host) ? HostKind.ip : HostKind.name,
      // Effective port, so 443 vs 8080 tells us whether a proxy is in play.
      port: uri.hasPort ? uri.port : _defaultPorts[uri.scheme],
    );
  }

  static const _defaultPorts = {'http': 80, 'https': 443, 'ws': 80, 'wss': 443};

  static final _ipish = RegExp(r'^[0-9.]+$|:');

  /// Digits-and-dots or anything with a colon (IPv6 literal). Deliberately
  /// loose — a wrong guess here only mislabels a hint, it can't leak.
  static bool _looksLikeIp(String host) => _ipish.hasMatch(host);

  final String scheme;
  final HostKind hostKind;
  final int? port;

  Map<String, Object?> toJson() => {
        'scheme': scheme,
        'host_kind': hostKind.name,
        if (port != null) 'port': port,
      };
}

/// First line of every log file: everything that is true for the whole session.
class LogHeader {
  const LogHeader({
    required this.ts,
    required this.session,
    required this.app,
    required this.flavor,
    this.stream = LogStream.ui,
    this.os,
    this.device,
    this.locale,
    this.server,
    this.serverUrl,
    this.auth,
  });

  /// Bumped when the record shape changes in a way a parser must know about.
  static const formatVersion = 1;

  /// Reads a header line back, or null when the line is not the header of
  /// [session].
  ///
  /// The checks are the point. A header write may fail silently while the
  /// writes after it succeed, so a stream's first line is not guaranteed to be
  /// a header — and accepting a *record* as one yields a header with no `ts`,
  /// which makes the merge drop the whole background stream from every report.
  static LogHeader? tryParse(String line, {required String session}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on Object {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    final fields = decoded;
    if (fields.containsKey('t')) return null;
    if (fields['session'] != session) return null;
    final ts = DateTime.tryParse('${fields['ts']}');
    final app = fields['app'];
    final flavor = fields['flavor'];
    if (ts == null || app is! String || flavor is! String) return null;
    return LogHeader(
      ts: ts,
      session: session,
      app: app,
      flavor: flavor,
      stream: LogStream.values.firstWhere(
        (s) => s.name == fields['stream'],
        orElse: () => LogStream.ui,
      ),
      os: fields['os'] as String?,
      device: fields['device'] as String?,
      locale: fields['locale'] as String?,
      server: fields['server'] as String?,
      serverUrl: switch (fields['scheme']) {
        final String scheme => ServerFingerprint(
            scheme: scheme,
            hostKind: fields['host_kind'] == HostKind.ip.name
                ? HostKind.ip
                : HostKind.name,
            port: fields['port'] as int?,
          ),
        _ => null,
      },
      auth: fields['auth'] as String?,
    );
  }

  /// The same session, tagged as a different stream — what a background isolate
  /// writes at the top of its own file.
  LogHeader copyWith({LogStream? stream}) => LogHeader(
        ts: ts,
        session: session,
        app: app,
        flavor: flavor,
        stream: stream ?? this.stream,
        os: os,
        device: device,
        locale: locale,
        server: server,
        serverUrl: serverUrl,
        auth: auth,
      );

  /// Session identifier shared by every stream file of one recording.
  /// 128 random bits as hex — no uuid dependency for what is just a join key.
  static String newSessionId() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
  }

  /// Wall-clock start of this stream; every record's `t` is an offset from it.
  final DateTime ts;
  final String session;

  /// Full app version, e.g. `0.11.2+1102`.
  final String app;

  /// `mobile` or `wear`.
  final String flavor;
  final LogStream stream;

  /// OS build string, e.g. what `Platform.operatingSystemVersion` reports.
  final String? os;

  /// Device model. Empty until the app takes a `device_info_plus` dependency.
  final String? device;
  final String? locale;

  /// bambuddy version — never the server URL, which is the user's private host.
  final String? server;

  /// Scheme / host shape / port of the server URL. http-vs-https alone explains
  /// a whole class of reports, so it is a header field rather than something to
  /// dig out of redacted strings.
  final ServerFingerprint? serverUrl;

  /// `apiKey`, `jwt` or `none` — `AuthMode.name` verbatim, camel case included.
  /// Whatever reads this back has to match that spelling exactly.
  final String? auth;

  Map<String, Object?> toJson() => {
        'v': formatVersion,
        'ts': ts.toUtc().toIso8601String(),
        'session': session,
        'stream': stream.name,
        'app': app,
        'flavor': flavor,
        if (os != null) 'os': os,
        if (device != null) 'device': device,
        if (locale != null) 'locale': locale,
        if (server != null) 'server': server,
        if (serverUrl != null) ...serverUrl!.toJson(),
        if (auth != null) 'auth': auth,
      };

  String toJsonLine() => jsonEncode(toJson());
}

/// One event line. Extra [fields] are spread flat into the record so the
/// summariser can read `status` or `code` without unwrapping a payload object.
class LogEvent {
  LogEvent({
    required this.t,
    required this.src,
    required this.evt,
    this.lvl = LogLevel.info,
    Map<String, Object?> fields = const {},
  }) : fields = _usableFields(fields);

  /// Keys the record owns; a caller-supplied one is dropped rather than nested.
  /// `iso` is here although no record sets it — `mergeSessions` stamps it on the
  /// way out, and a probe reusing the name would make a record claim to come
  /// from an isolate it did not.
  static const reservedKeys = {'t', 'src', 'lvl', 'evt', 'iso'};

  /// Milliseconds since the header's `ts`.
  final int t;
  final LogSource src;
  final String evt;
  final LogLevel lvl;
  final Map<String, Object?> fields;

  static Map<String, Object?> _usableFields(Map<String, Object?> fields) {
    if (fields.isEmpty) return const {};
    return {
      for (final e in fields.entries)
        // Nulls are dropped so call sites can pass optional values
        // unconditionally without padding every line.
        if (e.value != null && !reservedKeys.contains(e.key)) e.key: e.value,
    };
  }

  Map<String, Object?> toJson() => {
        't': t,
        'src': src.name,
        if (lvl != LogLevel.info) 'lvl': lvl.name,
        'evt': evt,
        ...fields,
      };

  String toJsonLine() => jsonEncode(toJson());
}
