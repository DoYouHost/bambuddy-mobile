/// The only form of a request path that may enter a record.
///
/// Taking `uri.path` drops the host and the query string, which is where the
/// tokens live. What is left can still be the user's: `/projects/{id}/
/// attachments/{filename}` puts a name they chose into a segment, and a
/// filename is their own text exactly like a model or a spool name
/// (`docs/diagnostics-log.md`). No redactor can catch it — it is a path, not a
/// field, and no shape rule separates `faktura-jan-kowalski.pdf` from a route.
///
/// So the rule is inverted, as it is for a sampled body: a segment survives only
/// if it looks like something the server or we named. A denylist of the routes
/// that interpolate a name would have to be remembered by whoever adds the next
/// one; this covers that route before it is written.
///
/// Measured against every route in `Endpoints`: none is masked. A dot is what
/// usually gives a filename away, and no route segment has one.
///
/// Applied again at the point a record is written, not only where the path is
/// captured: `AppApiException.path` is an ordinary field that any caller can
/// set, so a promise resting on every construction site going through
/// `mapDioException` is not one. Reducing an already-reduced path is a no-op.
String loggablePath(String path) {
  if (!path.contains('/')) return _segment(path);
  return path.split('/').map(_segment).join('/');
}

/// A numeric id, or a route word: lowercase, hyphenated, no dot. `2fa` is why
/// a leading digit is allowed.
final _named = RegExp(r'^(?:\d+|[a-z0-9][a-z0-9-]*)$');

String _segment(String segment) =>
    segment.isEmpty || _named.hasMatch(segment) ? segment : '<seg>';
