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
/// background isolate's own client. It writes through
/// `DiagnosticRecorder.active`, which is null unless a recording runs; the
/// arguments of a `?.` call are not evaluated on null, so an idle app pays for
/// one clock reading per request and nothing else.
///
/// What deliberately never enters a record: headers (the API key lives there),
/// the query string (the camera and thumbnail tokens live there), the host (the
/// user's private network — the session header carries scheme, port and whether
/// it was a name or an IP), and successful response bodies.
class HttpProbe extends Interceptor {
  /// Where the clock reading for `ms` is parked. `extra` survives redirects and
  /// the auth retry, which re-sends the very same [RequestOptions].
  static const _startedAtKey = 'diagnosticsStartedAt';

  /// Error bodies are clipped hard: bambuddy answers with a short `detail`, and
  /// anything longer is a proxy's HTML error page, which says which proxy in its
  /// first few tags.
  static const _maxBodyChars = 300;

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
    final status = response.statusCode;
    DiagnosticRecorder.active?.add(
      LogSource.http,
      'response',
      // A 4xx normally arrives as a DioException; it only reaches here when the
      // call opted out of status validation, and it is still not good news.
      lvl: status != null && status >= 400 ? LogLevel.warn : LogLevel.info,
      fields: {
        'method': response.requestOptions.method,
        'path': _pathOf(response.requestOptions),
        'status': status,
        'ms': _elapsedMs(response.requestOptions),
      },
    );
    handler.next(response);
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
