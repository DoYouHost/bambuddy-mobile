import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'demo_backend.dart';

/// Dio [HttpClientAdapter] for demo mode: routes every request into
/// [DemoBackend] instead of the network. Installed by `ApiClient` when the
/// active profile is the demo profile, so every consumer of the authenticated
/// Dio (repositories, background isolate, wear REST transport) is covered
/// without further changes.
class DemoHttpClientAdapter implements HttpClientAdapter {
  DemoHttpClientAdapter({this.latency = const Duration(milliseconds: 120)});

  /// Simulated network latency so the UI's loading states stay visible.
  final Duration latency;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    await Future<void>.delayed(latency);
    final result = DemoBackend.instance.handle(
      options.method.toUpperCase(),
      options.uri,
      _decodedBody(options.data),
    );
    return ResponseBody.fromString(
      jsonEncode(result.body),
      result.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  /// Request payloads arrive as the original Dio `data` (map/list/string).
  /// FormData (uploads) is not routable — the backend answers those with 501.
  Object? _decodedBody(Object? data) {
    if (data is String && data.isNotEmpty) {
      try {
        return jsonDecode(data);
      } on FormatException {
        return null;
      }
    }
    if (data is FormData) return null;
    return data;
  }

  @override
  void close({bool force = false}) {}
}
