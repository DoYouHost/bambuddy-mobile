/// Strips secrets from records **at write time**. Redacting at export would
/// leave keys sitting in memory and in the FGS file until the user hits send —
/// a crash in between would ship them anyway.
///
/// Two layers: exact values the app knows it holds (API key, JWT, camera token,
/// server host) registered via [remember], and shape-based passes for whatever
/// slipped in through an error message we don't control. Both run on every
/// string, including strings nested in maps and lists.
class LogRedactor {
  LogRedactor({this.maxStringLength = 2000});

  /// Ceiling for a single string value. Stack traces are the only field that
  /// reaches it; ~2000 chars is roughly 25 frames, enough to place the failure
  /// while keeping one bad record from eating the whole ring buffer.
  final int maxStringLength;

  /// Exact values → replacement label, longest first at scrub time so
  /// "printer-01.lan" wins over "printer-01".
  final Map<String, String> _known = {};

  /// Below this length an exact match is more likely to be a coincidence
  /// inside an unrelated word than a real secret.
  static const _minKnownLength = 4;

  /// Fields whose value comes from the app's own vocabulary, never from user
  /// input: the control identifier, the filament material, and the notification
  /// event and skip reason (both closed enums). Scrubbing those costs more than
  /// it protects — the demo server is `http://demo`, so `demo` is registered as
  /// the host and turned `setup.demo` into `setup.[HOST]`; a server called
  /// `printer` would do the same to `printer.files` and every other id on the
  /// dashboard, one called `pla` to every material, and — the reason `event` is
  /// here — turn `printerError` into `[HOST]Error`, mangling the one field the
  /// notification lane exists to report.
  ///
  /// Each still has to look like what it claims to be: a value of the wrong
  /// shape is not one of ours and goes through the scrub, so a stray
  /// `logTag('archive.card.$name')` would still be caught. Enum names are
  /// letters only, which no file or spool name survives.
  static final ourKeys = {
    'id': RegExp(r'^\w+(\.\w+)*$'),
    'mat': RegExp(r'^[A-Z0-9]+(-[A-Z0-9]+)*$'),
    'event': RegExp(r'^[a-zA-Z]+$'),
    'reason': RegExp(r'^[a-zA-Z]+$'),
    // Which ceiling ended a recording, `time` or `size` — both long enough to be
    // eaten by a server that happens to be named one of them.
    'limit': RegExp(r'^[a-z]+$'),
  };

  /// Field names whose value is secret whatever its shape.
  ///
  /// A standalone `key` is in there because bambuddy's own API answers with one:
  /// `POST /api-keys` returns the full key under exactly that name
  /// (`schemas/api_key.py`). It is fenced by non-alphanumerics so it catches
  /// `key`, `full_key` and `api-key` while leaving `monkey` and `keyboard`
  /// alone — those would be false positives on a field that is nobody's secret.
  /// `username` is in there for the same reason emails are masked: a report from
  /// a server with more than one user would otherwise name the others in a public
  /// issue — `created_by_username` rides along in every queue and archive record
  /// the log samples — and "who queued it" has never been the diagnosis.
  static final _secretKey = RegExp(
    r'(token|api_?key|(?:^|[^a-z0-9])key(?:$|[^a-z0-9])|secret|password|passwd'
    r'|authorization|access_?code|serial|cookie|username)',
    caseSensitive: false,
  );

  /// Splits a URL into scheme / optional userinfo / host / optional port so the
  /// host can go while the rest stays. What the user actually picked — http vs
  /// https, 443 vs 8080 — is half the diagnosis; the address is theirs.
  static final _urlAuthority = RegExp(
    r'((?:https?|wss?|rtsps?)://)([^@/\s]+@)?([^:/\s?#]+)(:\d+)?',
    caseSensitive: false,
  );
  static final _jwt =
      RegExp(r'\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*');
  static final _queryToken = RegExp(
    r'([?&](?:token|access_token|api_?key|key)=)[^&\s]+',
    caseSensitive: false,
  );
  static final _email =
      RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b');

  /// A bambuddy API key by its shape. The one the app itself holds is registered
  /// via [remember] and would be caught anyway; this is for a key that turns up
  /// somewhere nobody expected — a body, a server error message, a field named
  /// something the name pass does not know about.
  static final _apiKey = RegExp(r'\bbb_[A-Za-z0-9_-]{8,}');

  /// Bambu serials, in the two shapes they actually arrive in.
  ///
  /// The `0[0-3]…` alternative is the older fleet (00M/01D/01S/01P/03W). The
  /// second is the shape a live X2D answered with, for both the printer
  /// (`20P0AA000000001`) and its AMS unit (`19C0AA000000002`) — fifteen
  /// characters, two digits, a letter, then alphanumerics, and neither matched
  /// the first pattern. Field names carry `serial` often enough for the name pass
  /// to catch most of these, but a serial nested in a status frame or quoted in a
  /// server message has only this. (The examples are anonymised: a real serial
  /// does not belong in a public repository any more than in a log.)
  /// Both alternatives insist on a letter in the third position, which every
  /// documented prefix has and which is what keeps digits-only strings out: an
  /// HMS `full_code` (`030001000001000A`) and a stray float
  /// (`33.01666666666665`) both matched before, and turning an HMS code into
  /// `[SERIAL]` blinds the log to the one field the HMS catalog exists to read.
  static final _serial = RegExp(
    r'\b(?:0[0-3][A-Z][A-Z0-9]{9,13}|\d{2}[A-Z][0-9A-Z]{12})\b',
    caseSensitive: false,
  );

  /// IPv4, skipping firmware-version shapes like `01.09.01.00` — the
  /// `[1-9]\d|\d` alternations reject leading-zero octets.
  static final _ipv4 = RegExp(
    r'\b(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]\d|\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]\d|\d)\b',
  );

  /// Registers a value the app holds and must never log. Safe to call with
  /// null or a short value — both are ignored.
  void remember(String? value, String label) {
    if (value == null || value.length < _minKnownLength) return;
    _known[value] = label;
  }

  /// Registers the server host so it is masked even where it appears without a
  /// scheme — "Failed host lookup: 'printer.lan'" is a socket error message,
  /// not a URL, so the authority pass would never see it.
  ///
  /// Only the host goes in: registering `host:port` too would swallow the port
  /// before the authority pass gets a chance to keep it.
  void rememberServerUrl(String? url) {
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return;
    remember(uri.host, '[HOST]');
  }

  void forget(String? value) {
    if (value != null) _known.remove(value);
  }

  void forgetAll() => _known.clear();

  Map<String, Object?> scrubFields(Map<String, Object?> fields) {
    if (fields.isEmpty) return const {};
    return {
      for (final e in fields.entries)
        e.key: _secretKey.hasMatch(e.key)
            ? '[REDACTED]'
            : _isOurs(e.key, e.value)
                ? e.value
                : scrub(e.value),
    };
  }

  static bool _isOurs(String key, Object? value) {
    final shape = ourKeys[key];
    return shape != null && value is String && shape.hasMatch(value);
  }

  /// Recursively scrubs strings inside maps and lists; other scalars pass
  /// through untouched (an int can't carry a key).
  ///
  /// [ourKeys] is honoured at every depth: the WebSocket probe reports an AMS
  /// slot's material as a nested `mat`, and a server called `pla` would turn
  /// every loaded slot into `[HOST]` — the same trap as `setup.demo`, one level
  /// down.
  Object? scrub(Object? value) {
    if (value is String) return scrubString(value);
    if (value is Map) {
      return {
        for (final e in value.entries)
          '${e.key}': _secretKey.hasMatch('${e.key}')
              ? '[REDACTED]'
              : _isOurs('${e.key}', e.value)
                  ? e.value
                  : scrub(e.value),
      };
    }
    if (value is List) return [for (final v in value) scrub(v)];
    return value;
  }

  String scrubString(String input) {
    if (input.isEmpty) return input;
    var out = input;

    // Longest first: a shorter known value may be a prefix of a longer one.
    final values = _known.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final value in values) {
      if (out.contains(value)) out = out.replaceAll(value, _known[value]!);
    }

    out = out
        .replaceAllMapped(
          _urlAuthority,
          (m) => '${m[1]}${m[2] == null ? '' : '[CREDENTIALS]@'}'
              '[HOST]${m[4] ?? ''}',
        )
        .replaceAll(_jwt, '[JWT]')
        .replaceAll(_apiKey, '[APIKEY]')
        .replaceAllMapped(_queryToken, (m) => '${m[1]}[REDACTED]')
        .replaceAll(_email, '[EMAIL]')
        .replaceAll(_serial, '[SERIAL]')
        .replaceAll(_ipv4, '[IP]');

    if (out.length > maxStringLength) {
      out = '${out.substring(0, maxStringLength)}…[clipped]';
    }
    return out;
  }
}
