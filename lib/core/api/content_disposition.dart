/// The file name a `Content-Disposition` header proposes, or null when it has
/// none worth using. The server sends both forms
/// (`attachment; filename="a.csv"; filename*=UTF-8''a.csv`, `build_content_disposition`):
/// the RFC 5987 one carries what the plain one had to strip to ASCII, so it
/// wins, unless it gives nothing usable and the plain one does.
///
/// The name comes off the wire and ends up as a file picker's suggestion, so
/// each form is cleaned on its own: only the last path segment survives, with
/// either separator, and control characters are dropped.
String? contentDispositionFilename(String? header) {
  if (header == null) return null;
  String? extended;
  String? plain;
  for (final (key, value) in _parameters(header)) {
    if (key == 'filename*') {
      extended ??= _usable(_extendedValue(value));
    } else if (key == 'filename') {
      plain ??= _usable(value);
    }
  }
  return extended ?? plain;
}

/// The `key=value` parameters after the disposition type, split on the `;` that
/// sit outside a quoted string, with the quotes taken off and `\"` and `\\`
/// unescaped. A quote opens a string only right after the `=` of its parameter,
/// so a stray one inside a token hides nothing, and a parameter whose string is
/// never closed is dropped whole rather than read to the end of the header.
Iterable<(String, String)> _parameters(String header) sync* {
  final parts = <String>[];
  final current = StringBuffer();
  var quoted = false;
  // The last character written that was not a space.
  var previous = '';
  for (var i = 0; i < header.length; i++) {
    final c = header[i];
    if (quoted && c == r'\' && i + 1 < header.length) {
      current
        ..write(c)
        ..write(header[++i]);
      previous = header[i];
      continue;
    }
    if (c == '"' && (quoted || previous == '=')) {
      quoted = !quoted;
    } else if (c == ';' && !quoted) {
      parts.add(current.toString());
      current.clear();
      previous = '';
      continue;
    }
    current.write(c);
    if (c != ' ' && c != '\t') previous = c;
  }
  if (!quoted) parts.add(current.toString());
  for (final part in parts.skip(1)) {
    final eq = part.indexOf('=');
    if (eq < 0) continue;
    yield (
      part.substring(0, eq).trim().toLowerCase(),
      _unquote(part.substring(eq + 1).trim()),
    );
  }
}

String _unquote(String value) {
  if (value.length < 2 || !value.startsWith('"') || !value.endsWith('"')) {
    return value;
  }
  // Only `\"` and `\\` are escapes here; any other backslash stays and is a path
  // separator to [_usable], as in the Windows paths some servers send.
  return value
      .substring(1, value.length - 1)
      .replaceAllMapped(RegExp(r'\\(["\\])'), (m) => m[1]!);
}

/// `charset'language'percent-encoded`; only UTF-8 is read, and a broken escape
/// reads as nothing.
String? _extendedValue(String value) {
  final quote = value.indexOf("'");
  final second = quote < 0 ? -1 : value.indexOf("'", quote + 1);
  if (second < 0 || value.substring(0, quote).toLowerCase() != 'utf-8') {
    return null;
  }
  try {
    return Uri.decodeComponent(value.substring(second + 1));
  } on ArgumentError {
    return null;
  }
}

final _controls = RegExp(r'[\x00-\x1F\x7F]');

/// [raw] as a file name, or null when nothing is left of it.
String? _usable(String? raw) {
  if (raw == null) return null;
  final name = raw
      .replaceAll(_controls, '')
      .split(RegExp(r'[/\\]'))
      .last
      .trim();
  return name.isEmpty || name == '.' || name == '..' ? null : name;
}
