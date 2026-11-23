import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'edge_access.dart';

/// A request carrying a Cloudflare Access credential. Two jobs `dart:io` does
/// not do for it.
///
/// **The credential goes on late.** Dio, and anything else that builds a
/// request, sets its own headers after `openUrl` returns, and `set` replaces: a
/// 2FA call sends its own `Cookie`, which would have dropped `CF_Authorization`.
/// So the headers are added at the last moment they can be, just before the
/// first byte is handed to the inner request (the first write, or `close`), and
/// a cookie is merged into one the caller set.
///
/// **A redirect never takes it to another origin.** `dart:io` copies every
/// header of a request to the target of a redirect and strips only the few it
/// knows to be secret (`authorization`, `cookie`, ...), so
/// `CF-Access-Client-Secret` would follow a redirect to any host. The inner
/// request never follows. A redirect to the same origin (scheme, host and port)
/// is followed through `HttpClientResponse.redirect`, as `dart:io` does, with
/// its method rules, loop check and limit. A redirect to another origin is not
/// followed: the caller gets the 3xx, as for a request that asked not to
/// follow, and the credential stays behind.
class EdgeRequest implements HttpClientRequest {
  EdgeRequest(this._inner, this._access) {
    // Now, not in `close`: once a body has been written the inner request
    // refuses to change this ("Request already sent").
    _inner.followRedirects = false;
    // Whoever never reads `done` must not see the error `close` reports.
    _done.future.ignore();
  }

  final HttpClientRequest _inner;
  final EdgeAccess _access;

  /// Completes with the response the caller gets, or with why there is none.
  /// `close` returns it, as `dart:io` returns its own `done`.
  final _done = Completer<HttpClientResponse>();

  bool _sent = false;
  bool _aborted = false;

  // What the caller asked for; the inner request is always told not to follow.
  bool _followRedirects = true;
  int _maxRedirects = 5;

  @override
  bool get followRedirects => _followRedirects;
  @override
  set followRedirects(bool value) => _followRedirects = value;

  @override
  int get maxRedirects => _maxRedirects;
  @override
  set maxRedirects(int value) => _maxRedirects = value;

  /// Called before anything reaches the inner request, and again at `close`,
  /// so it can run any number of times: an empty write commits no headers, and
  /// whatever the caller sets after one must not displace the credential. Once
  /// the headers are committed they cannot change, so a header that already
  /// has the right value is left alone rather than set again.
  void _stamp() {
    for (final header in _access.headers.entries) {
      final isCookie = header.key.toLowerCase() == HttpHeaders.cookieHeader;
      final String wanted;
      if (isCookie) {
        // The jar is folded in here: `dart:io` would append it to the header
        // with ', ', which no server reads as a list of cookies.
        final theirs = [
          ...?_inner.headers[HttpHeaders.cookieHeader]?.expand(
            (line) => line.split(';').map((pair) => pair.trim()),
          ),
          for (final cookie in _inner.cookies) '${cookie.name}=${cookie.value}',
        ];
        final ours = header.value;
        final name = ours.substring(0, ours.indexOf('='));
        wanted = [
          ...theirs.where((pair) => !pair.startsWith('$name=')),
          ours,
        ].where((pair) => pair.isNotEmpty).join('; ');
        if (_inner.cookies.isNotEmpty) _inner.cookies.clear();
      } else {
        wanted = header.value;
      }
      // One value, as `set` leaves it: several lines would go out folded with
      // ', ', and a header already right is not set again (see above).
      final current = _inner.headers[header.key];
      if (current == null || current.length != 1 || current.first != wanted) {
        _inner.headers.set(header.key, wanted);
      }
    }
  }

  @override
  Future<HttpClientResponse> close() {
    if (_sent) return _done.future;
    _stamp();
    // Throws here, as `dart:io` does, while a stream is still being added; the
    // call is then not counted, so closing again afterwards works.
    final first = _inner.close();
    _sent = true;
    unawaited(_follow(first));
    return _done.future;
  }

  Future<void> _follow(Future<HttpClientResponse> first) async {
    try {
      var response = await first;
      while (_followRedirects && response.isRedirect) {
        if (_aborted) break;
        if (await _anotherOrigin(response)) break;
        if (response.redirects.length >= _maxRedirects) {
          await response.drain<void>();
          throw RedirectException(
            'Redirect limit exceeded',
            response.redirects,
          );
        }
        await response.drain<void>();
        // The caller may have given up while the body was draining; the inner
        // request is done by now, so its own abort cannot stop the next hop.
        if (_aborted) throw _abortError();
        response = await response.redirect();
      }
      if (_aborted) {
        // A hop that was in flight when the caller gave up: nobody will read it.
        unawaited(response.drain<void>().catchError((_) {}));
        throw _abortError();
      }
      if (!_done.isCompleted) _done.complete(response);
    } on Object catch (error, stack) {
      if (!_done.isCompleted) _done.completeError(error, stack);
    }
  }

  /// Whether [response] redirects somewhere this credential must not go. A
  /// response with no usable `Location` is not: `redirect` raises the error
  /// `dart:io` gives for it. The response is drained before the error leaves,
  /// as `dart:io` drains before it reads the header.
  Future<bool> _anotherOrigin(HttpClientResponse response) async {
    try {
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null) return false;
      final target = _inner.uri.resolve(location);
      return !(target.isScheme(_inner.uri.scheme) &&
          target.host == _inner.uri.host &&
          target.port == _inner.uri.port);
    } on Object {
      unawaited(response.drain<void>().catchError((_) {}));
      rethrow;
    }
  }

  HttpException _abortError() =>
      const HttpException('Request has been aborted');

  @override
  Future<HttpClientResponse> get done => _done.future;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    _aborted = true;
    if (!_done.isCompleted) {
      _done.completeError(
        exception ?? _abortError(),
        stackTrace ?? StackTrace.current,
      );
    }
    _inner.abort(exception, stackTrace);
  }

  @override
  bool get bufferOutput => _inner.bufferOutput;
  @override
  set bufferOutput(bool value) => _inner.bufferOutput = value;

  @override
  int get contentLength => _inner.contentLength;
  @override
  set contentLength(int value) => _inner.contentLength = value;

  @override
  Encoding get encoding => _inner.encoding;
  @override
  set encoding(Encoding value) => _inner.encoding = value;

  @override
  bool get persistentConnection => _inner.persistentConnection;
  @override
  set persistentConnection(bool value) => _inner.persistentConnection = value;

  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;

  @override
  List<Cookie> get cookies => _inner.cookies;

  @override
  HttpHeaders get headers => _inner.headers;

  @override
  String get method => _inner.method;

  @override
  Uri get uri => _inner.uri;

  @override
  void add(List<int> data) {
    _stamp();
    _inner.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    _stamp();
    return _inner.addStream(stream);
  }

  @override
  Future<void> flush() {
    _stamp();
    return _inner.flush();
  }

  @override
  void write(Object? object) {
    _stamp();
    _inner.write(object);
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    _stamp();
    _inner.writeAll(objects, separator);
  }

  @override
  void writeCharCode(int charCode) {
    _stamp();
    _inner.writeCharCode(charCode);
  }

  @override
  void writeln([Object? object = '']) {
    _stamp();
    _inner.writeln(object);
  }
}
