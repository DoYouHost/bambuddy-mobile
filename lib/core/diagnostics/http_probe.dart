import 'dart:convert';

import 'package:dio/dio.dart';

import 'diagnostic_recorder.dart';
import 'log_event.dart';

/// Records every call the app makes to bambuddy: method, path, status and how
/// long it took, plus what failed when it failed.
///
/// This is the layer where "the app is broken" usually turns out to mean the
/// server answered 502, or the connection never got past the TLS handshake — and
/// neither is visible from the UI, which shows the same empty card either way.
///
/// Installed by [createBareDio], so it covers the authenticated client, the
/// login and auth-probe calls that run before there is a client, and the
/// background isolate's own client. Nothing here is built unless a recording
/// runs, so an idle app pays for one clock reading per request and nothing else.
///
/// What deliberately never enters a record: headers (the API key lives there),
/// the query string (the camera and thumbnail tokens live there), and the host
/// (the user's private network — the session header carries scheme, port and
/// whether it was a name or an IP).
///
/// ## What a successful answer contributes
///
/// Its record count ([_countOf]) plus **one** record in full, for the endpoints
/// that carry the app's content ([_sampledPaths]). A status code cannot separate
/// "the screen is empty" from "the screen shows the wrong thing": a 200 with
/// twenty records the app then hides looks exactly like a 200 with nothing in
/// it. One record settles both, and names the field when the server changed a
/// type.
///
/// The rest of the list stays a number, and an unchanged sample degrades to
/// `same` — a poll answering with the same first record twice a minute for half
/// an hour would otherwise *be* the log.
class HttpProbe extends Interceptor {
  /// Where the clock reading for `ms` is parked. `extra` survives redirects and
  /// the auth retry, which re-sends the very same [RequestOptions].
  static const _startedAtKey = 'diagnosticsStartedAt';

  /// Error bodies are clipped hard: bambuddy answers with a short `detail`, and
  /// anything longer is a proxy's HTML error page, which says which proxy in its
  /// first few tags.
  static const _maxBodyChars = 300;

  /// Ceiling on one sampled record while it stays a map.
  ///
  /// Six kilobytes because that is what the records worth reading actually
  /// measure: a printer status is 4.6 kB and a maintenance overview 3.2 kB on a
  /// live server, and the first cut of this (1.9 kB, taken from a 1.4 kB queue
  /// item) turned both into escaped, truncated text — losing the AMS tail and
  /// most of the maintenance list, which is the half anybody would have opened
  /// the log for. Repeats do not multiply it: an unchanged record degrades to
  /// `same`.
  static const _maxSampleChars = 6 * 1024;

  /// Ceiling on the degraded form. Past [_maxSampleChars] a record goes in as
  /// clipped text — a library entry carrying an inline thumbnail must not put an
  /// image in the log — and this stays under `LogRedactor.maxStringLength` so
  /// such a clip is marked once rather than twice.
  static const _maxClippedChars = 1900;

  /// Endpoints whose answers are the app's content, and therefore the answer to
  /// "it shows nothing" and "it shows the wrong thing".
  ///
  /// An allowlist, not a denylist: `auth`, `cloud`, `makerworld` and `settings`
  /// answer with tokens and credentials, `users` answers with people, and
  /// `filament-catalog` is a static table nobody reports bugs about. Forgetting
  /// an endpoint here costs a diagnosis; forgetting one in a denylist costs a
  /// secret.
  static final _sampledPaths = RegExp(
    r'/api/v1/(queue|archives|printers|inventory|spoolman'
    r'|smart-plugs|maintenance|projects|library)(/|$)',
  );

  /// Checked before [_sampledPaths] and wins over it. A prefix on the allowlist
  /// is not a promise that everything under it is content:
  /// `/printers/camera/stream-token` mints a camera token and sat inside
  /// `printers`, so a live recording logged `{"token":"[REDACTED]"}` — the
  /// redactor caught the value, which is exactly the safety net the allowlist
  /// exists so as not to lean on. Nothing that mints a credential is worth one
  /// record of anybody's time.
  static final _neverSampled = RegExp(r'(token|api-keys)(/|$)');

  /// The last record sampled per request, so a poll that keeps answering the
  /// same thing says `same` instead of repeating itself.
  ///
  /// Keyed by method, path and the query's hash: `/queue/?status=pending` and
  /// `?status=printing` are one path with two different answers, and they have to
  /// dedupe against themselves rather than against each other. The hash lives
  /// here and only here — the query string itself never reaches a record.
  static final Map<String, String> _lastSample = {};

  /// Called when a recording opens. Fingerprints left by the previous session
  /// would silence the first answer of this one.
  static void openSession() => _lastSample.clear();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Stamped whether or not a recording runs. Starting one mid-flight is the
    // normal case — the user reproduces the bug while the dashboard polls — and
    // a response whose request was never stamped would have to log itself
    // without a duration.
    options.extra[_startedAtKey] = DateTime.now().millisecondsSinceEpoch;
    // Only calls that change something on the server. A GET that never comes
    // back stands out as a response missing from the polling around it, but
    // "did my save even leave the phone" has no other witness — and that is the
    // request whose answer goes missing when the app dies mid-call.
    if (!_isRead(options.method)) {
      DiagnosticRecorder.active?.add(
        LogSource.http,
        'request',
        lvl: LogLevel.debug,
        fields: {'method': options.method, 'path': _pathOf(options)},
      );
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    // A local null check rather than `?.`: the sample below has to be built
    // (and the fingerprint kept) only while something is recording.
    final store = DiagnosticRecorder.active;
    if (store != null) {
      final status = response.statusCode;
      store.add(
        LogSource.http,
        'response',
        // A 4xx normally arrives as a DioException; it only reaches here when
        // the call opted out of status validation, and it is still not good news.
        lvl: status != null && status >= 400 ? LogLevel.warn : LogLevel.info,
        fields: {
          'method': response.requestOptions.method,
          'path': _pathOf(response.requestOptions),
          'status': status,
          'ms': _elapsedMs(response.requestOptions),
          // How many records a list endpoint answered with. "The queue is empty"
          // and "the queue came back full and the app dropped all of it" are the
          // same 200 without this, and they have nothing in common as bugs.
          'n': _countOf(response.data),
          // A GET that answered 200 with nothing in it. dio hands back a null
          // body for an empty response that claims to be JSON, and the data
          // layer reads that as an empty list — the one way a truncated or
          // dropped answer reaches a screen as "there is nothing here" instead
          // of as an error. Reads only: a 200 with no body is the normal answer
          // to a save.
          'empty':
              _isRead(response.requestOptions.method) && response.data == null
                  ? true
                  : null,
          ..._sampleOf(response),
        },
      );
    }
    handler.next(response);
  }

  /// One record of the answer, or `same` when it matches the last one sampled
  /// for this request. Empty for anything outside [_sampledPaths].
  ///
  /// Records go in as a map, not as text: [LogRedactor] checks field names at
  /// every depth of a nested map and runs its shape passes on every string
  /// inside it, so a token that turns up in a body it has no business being in
  /// is caught either way.
  static Map<String, Object?> _sampleOf(Response<dynamic> response) {
    final options = response.requestOptions;
    final path = _pathOf(options);
    if (_neverSampled.hasMatch(path)) return const {};
    if (!_sampledPaths.hasMatch(path)) return const {};
    final record = _firstRecord(response.data);
    if (record == null) return const {};

    final encoded = _encoded(record);
    final key = '${options.method} $path?${options.uri.query.hashCode}';
    final stable = _timestamps.hasMatch(encoded)
        ? encoded.replaceAll(_timestamps, '"<ts>"')
        : encoded;
    // The count belongs in the comparison too: a queue that grew from one item
    // to two answers with the same first record, and reporting that as `same`
    // beside `n:2` reads as "nothing happened" at the moment something did.
    final fingerprint = '${_countOf(response.data)}:$stable';
    if (_lastSample[key] == fingerprint) return const {'same': true};
    _lastSample[key] = fingerprint;
    return {
      'first': encoded.length > _maxSampleChars
          ? '${encoded.substring(0, _maxClippedChars)}…'
          : record,
    };
  }

  /// Timestamps, as they look inside an encoded record. Compared out of the
  /// fingerprint, never out of what gets logged.
  ///
  /// A server that stamps every answer defeats a fingerprint taken over the
  /// whole record: a smart plug carries `last_checked` and `updated_at`, both
  /// rewritten on each poll, so its 1.5 kB record went into a live log five times
  /// in under a minute and never once as `same` — half a megabyte across a
  /// half-hour recording, from one endpoint whose state had not changed. Matched
  /// by the shape of an ISO-8601 value rather than by field name, so a server
  /// that adds another such field needs no change here.
  static final _timestamps = RegExp(
    r'"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?"',
  );

  /// The record a body is sampled by: a list's first entry, or the object
  /// itself. Anything else — an empty list, a list of scalars, a downloaded
  /// image, a bare string — has no record to show.
  static Map<String, dynamic>? _firstRecord(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is List && data is! List<int>) {
      final first = data.isEmpty ? null : data.first;
      return first is Map<String, dynamic> ? first : null;
    }
    return null;
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final status = err.response?.statusCode;
    // The class of what actually broke: `HandshakeException` versus
    // `SocketException` separates "TLS refused" from "nothing listening there",
    // which dio lumps together as `connectionError`.
    final cause = err.error?.runtimeType.toString();
    DiagnosticRecorder.active?.add(
      LogSource.http,
      'error',
      lvl: _levelOf(err),
      fields: {
        'method': err.requestOptions.method,
        'path': _pathOf(err.requestOptions),
        'type': err.type.name,
        'status': status,
        'ms': _elapsedMs(err.requestOptions),
        'cause': cause,
        // dio's message only restates the status when there is a response, so
        // it earns its place exactly when there is none.
        'msg': status == null ? _reasonOf(err, cause) : null,
        'body': status == null ? null : _bodyPreview(err.response?.data),
      },
    );
    handler.next(err);
  }

  /// What failed, in as few characters as the truth allows.
  ///
  /// The underlying exception before dio's wrapper: `SocketException` carries
  /// the OS error and errno, which dio drops when it reformats the message. The
  /// class name is stripped off the front because it is already the `cause`, and
  /// dio's closing sentence goes because repeating "cannot be solved by the
  /// library" seventy-eight characters at a time was, in an offline session, the
  /// single largest thing in the log.
  static String? _reasonOf(DioException err, String? cause) {
    final text = (err.error?.toString() ?? err.message)?.trim();
    if (text == null || text.isEmpty) return null;
    final withoutClass = cause != null && text.startsWith('$cause: ')
        ? text.substring(cause.length + 2)
        : text;
    return withoutClass.replaceFirst(_dioBoilerplate, '').trimRight();
  }

  /// dio appends this to every message it builds itself.
  static final _dioBoilerplate = RegExp(
    r'\s*This indicates an error which most likely cannot be solved by the '
    r'library\.?$',
  );

  /// Element count for a JSON array body, null for anything else — an object
  /// body's shape is the endpoint's business, and counting its keys would say
  /// nothing.
  ///
  /// A downloaded image is a `List<int>` and is excluded: its length is a byte
  /// count, and reported as `n` it would read as "the server sent 34 000
  /// records".
  static int? _countOf(Object? data) =>
      data is List && data is! List<int> ? data.length : null;

  static bool _isRead(String method) {
    final upper = method.toUpperCase();
    return upper == 'GET' || upper == 'HEAD';
  }

  /// Path only. `uri` resolves the relative path against the base URL, and
  /// taking `.path` off it drops both the host and the query string.
  static String _pathOf(RequestOptions options) => options.uri.path;

  static int? _elapsedMs(RequestOptions options) {
    final startedAt = options.extra[_startedAtKey];
    if (startedAt is! int) return null;
    final ms = DateTime.now().millisecondsSinceEpoch - startedAt;
    // A clock moved backwards mid-request must not produce a negative duration
    // that reads as a response arriving before it was asked for.
    return ms < 0 ? 0 : ms;
  }

  static LogLevel _levelOf(DioException err) {
    // A cancelled request is usually the app's own doing (a screen closed while
    // loading) and says nothing about a failure.
    if (err.type == DioExceptionType.cancel) return LogLevel.info;
    // No response at all is ours to explain; a status means the server did
    // answer, and the summariser groups those by status anyway.
    return err.response == null ? LogLevel.error : LogLevel.warn;
  }

  static String? _bodyPreview(Object? data) {
    if (data == null) return null;
    // Bytes, i.e. a download that failed. Encoding those would spell out an
    // array of numbers; the size is the only useful thing in them.
    if (data is List<int>) return '<${data.length} bytes>';
    final text = data is String ? data : _encoded(data);
    if (text.isEmpty) return null;
    return text.length > _maxBodyChars
        ? '${text.substring(0, _maxBodyChars)}…'
        : text;
  }

  static String _encoded(Object data) {
    try {
      return jsonEncode(data);
    } on Object {
      // A streamed or otherwise unencodable body: its type is all we can say
      // about it, and a failing body must not fail the request it describes.
      return '<${data.runtimeType}>';
    }
  }
}
