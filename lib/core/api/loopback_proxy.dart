import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Whether a request to [url] has to be fetched by the app for a native stack
/// to get it: the server is https and this isolate holds a CA or a client
/// certificate (#62, #65) that only `dart:io` knows about.
///
/// ExoPlayer (`video_player`) and a WebView run on Android's own network stack,
/// which trusts the system roots and presents no client certificate, whatever the
/// user imported. Without this a private CA or mutual TLS server cannot play its
/// timelapses or open the G-code preview.
bool needsLoopbackBridge(Uri url, {required bool presentsTlsIdentity}) =>
    presentsTlsIdentity && url.isScheme('https');

/// A web server on this device's loopback that fetches a few URLs for a native
/// stack, through `dart:io`: the app's own trust, client certificate and
/// Cloudflare Access credential apply to what it fetches (#62, #65, #72).
///
/// Anything on the phone can connect to a loopback port, and this one carries
/// the app's credentials, so it is narrow on purpose:
///
/// * it lives only while somebody holds a [LoopbackLease], and a port is opened
///   afresh for the next one;
/// * it serves the URLs it was handed and nothing else, each under its own
///   128-bit random path, and a request for any other path, or for a `Host` that
///   is not the loopback address it listens on (DNS rebinding), is a 404;
/// * GET and HEAD only, and a request is answered from exactly one upstream URL
///   with the headers it was registered with, never with what the caller sent
///   but `Range`.
class LoopbackProxy {
  LoopbackProxy._(this._server);

  final HttpServer _server;
  final _routes = <String, _Route>{};
  final _random = Random.secure();

  /// Not decompressing: the caller does, as it would from the server, and what
  /// is sent on is the bytes `Content-Length` counts.
  final _client = HttpClient()..autoUncompress = false;
  var _closed = false;

  /// What the next lease is handed. Shared so that two screens at once use one
  /// listener; closed when the last lease is released.
  static LoopbackProxy? _shared;
  static var _leases = 0;
  static Future<LoopbackProxy>? _starting;

  /// A lease on the shared proxy, started if it is not running. Call
  /// [LoopbackLease.release] when the thing that was exposed is gone.
  static Future<LoopbackLease> lease() async {
    _leases++;
    try {
      final proxy = await (_starting ??= _start());
      return LoopbackLease._(proxy);
    } catch (_) {
      _leases--;
      _starting = null;
      rethrow;
    }
  }

  static Future<LoopbackProxy> _start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = LoopbackProxy._(server);
    _shared = proxy;
    server.listen(proxy._serve);
    return proxy;
  }

  static Future<void> _release() async {
    if (--_leases > 0) return;
    final proxy = _shared;
    _shared = null;
    _starting = null;
    await proxy?._close();
  }

  /// The origin it listens on, for a page that has to be same-origin with it.
  String get origin => 'http://127.0.0.1:${_server.port}';

  Uri _expose(Uri upstream, Map<String, String> headers, List<String> owned) {
    final token = _token();
    _routes[token] = _Route(upstream, headers);
    owned.add(token);
    return Uri.parse('$origin/$token');
  }

  String _token() {
    final bytes = Uint8List.fromList([
      for (var i = 0; i < 16; i++) _random.nextInt(256),
    ]);
    return [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
  }

  Future<void> _close() async {
    _closed = true;
    _routes.clear();
    _client.close(force: true);
    await _server.close(force: true);
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      final route = _routeFor(request);
      if (route == null) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
        return;
      }
      await _forward(request, route);
    } on Object {
      // The caller went away, or the upstream did: nothing left to say.
    } finally {
      try {
        await response.close();
      } on Object {
        // Already gone.
      }
    }
  }

  _Route? _routeFor(HttpRequest request) {
    if (_closed) return null;
    final host = request.headers.host;
    final port = request.headers.port;
    if (host != '127.0.0.1' || port != _server.port) return null;
    final segments = request.uri.pathSegments;
    if (segments.length != 1) return null;
    return _routes[segments.single];
  }

  /// Headers worth handing back: what a media player or `fetch` reads to size,
  /// seek and cache. The rest of the upstream's are its own business.
  static const _passed = [
    HttpHeaders.contentTypeHeader,
    HttpHeaders.contentEncodingHeader,
    HttpHeaders.contentLengthHeader,
    HttpHeaders.contentRangeHeader,
    HttpHeaders.acceptRangesHeader,
    HttpHeaders.etagHeader,
    HttpHeaders.lastModifiedHeader,
  ];

  /// The values of a header the caller sent, as one: a header sent on several
  /// lines parses to several values, and `HttpHeaders.value` throws on that.
  static String? _joined(HttpHeaders headers, String name) =>
      headers[name]?.join(', ');

  Future<void> _forward(HttpRequest request, _Route route) async {
    final HttpClientResponse answer;
    try {
      final upstream = await _client.openUrl(request.method, route.url);
      // A redirect is handed back as it is, with no `Location` the caller could
      // follow, rather than followed here with the headers of this route.
      upstream.followRedirects = false;
      route.headers.forEach(upstream.headers.set);
      final range = _joined(request.headers, HttpHeaders.rangeHeader);
      if (range != null) upstream.headers.set(HttpHeaders.rangeHeader, range);
      // What the caller can take, not what `dart:io` would ask for on its own: a
      // media player asks for the bytes as they are, a page for gzip, and is told
      // which it got by the `Content-Encoding` that is passed back.
      upstream.headers.set(
        HttpHeaders.acceptEncodingHeader,
        _joined(request.headers, HttpHeaders.acceptEncodingHeader) ??
            'identity',
      );
      answer = await upstream.close();
    } on Object {
      // Nothing came back at all: the caller is told so, not handed an empty 200.
      request.response.statusCode = HttpStatus.badGateway;
      return;
    }

    final response = request.response;
    response.statusCode = answer.statusCode;
    for (final name in _passed) {
      final value = answer.headers[name]?.first;
      if (value != null) response.headers.set(name, value);
    }
    if (request.method == 'HEAD') {
      await answer.drain<void>();
      return;
    }
    // The body follows the caller's pace, and ends with it: a player that seeks
    // away, or a screen that is left, closes its socket, and that ends the read
    // and with it the upstream connection (measured against a raw socket, which
    // sees the close; an `HttpServer` swallows what it writes to a closed peer
    // and cannot tell).
    await response.addStream(answer);
  }
}

class _Route {
  const _Route(this.url, this.headers);

  final Uri url;
  final Map<String, String> headers;
}

/// A hold on the shared [LoopbackProxy]. Released once, by whoever exposed
/// something through it.
class LoopbackLease {
  LoopbackLease._(this._proxy);

  final LoopbackProxy _proxy;
  final _owned = <String>[];
  var _released = false;

  /// The origin the proxy listens on.
  String get origin => _proxy.origin;

  /// The loopback URL that serves [upstream], fetched with [headers].
  Uri expose(Uri upstream, {Map<String, String> headers = const {}}) {
    if (_released) throw StateError('The lease has been released');
    return _proxy._expose(upstream, headers, _owned);
  }

  /// Takes this lease's URLs down with it, even while another lease keeps the
  /// listener up: a URL carries the credentials of whoever exposed it.
  Future<void> release() async {
    if (_released) return;
    _released = true;
    _owned.forEach(_proxy._routes.remove);
    await LoopbackProxy._release();
  }
}
