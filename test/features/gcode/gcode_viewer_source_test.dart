import 'dart:io';

import 'package:bambuddy_mobile/core/api/loopback_proxy.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/features/gcode/gcode_viewer_screen.dart';
import 'package:flutter_test/flutter_test.dart';

// Where the G-code preview loads from (#62, #65): the server itself, or, for a
// server the WebView cannot reach on its own, the app's loopback bridge.

const _profile = ServerProfile(
  baseUrl: 'https://printers.example.com',
  authMode: AuthMode.apiKey,
);
const _path = '/api/v1/archives/7/gcode?plate=2';

void main() {
  test(
    'is the server itself, and the headers the page\'s own, without a lease',
    () {
      final source = viewerSource(
        profile: _profile,
        path: _path,
        headers: {'X-API-Key': 'bb_key'},
      );
      expect(source.baseUrl, 'https://printers.example.com');
      expect(source.gcodeUrl, _path);
      expect(source.headers, {'X-API-Key': 'bb_key'});
    },
  );

  group('through the bridge', () {
    late LoopbackLease lease;
    late HttpServer upstream;
    late HttpOverrides? mocked;
    final heard = <Map<String, String>>[];

    setUp(() async {
      mocked = HttpOverrides.current;
      HttpOverrides.global = null;
      heard.clear();
      upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      upstream.listen((request) async {
        heard.add({
          'path': request.uri.toString(),
          if (request.headers.value('x-api-key') != null)
            'x-api-key': request.headers.value('x-api-key')!,
        });
        request.response.write('G1 X1');
        await request.response.close();
      });
      lease = await LoopbackProxy.lease();
    });

    tearDown(() async {
      await lease.release();
      await upstream.close(force: true);
      HttpOverrides.global = mocked;
    });

    test('the page is the bridge, with no headers of its own', () {
      final source = viewerSource(
        profile: _profile,
        path: _path,
        headers: {'X-API-Key': 'bb_key'},
        lease: lease,
      );
      expect(source.baseUrl, lease.origin);
      expect(source.headers, isEmpty, reason: 'they stay in the bridge');
      expect(source.gcodeUrl, matches(RegExp(r'^/[0-9a-f]{32}$')));
    });

    test('what it fetches is the server\'s path, with the headers', () async {
      // The profile points at the upstream here, over plain http, which the
      // bridge fetches the same way.
      final profile = ServerProfile(
        baseUrl: 'http://127.0.0.1:${upstream.port}',
        authMode: AuthMode.apiKey,
      );
      final source = viewerSource(
        profile: profile,
        path: _path,
        headers: {'X-API-Key': 'bb_key'},
        lease: lease,
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(
        Uri.parse('${source.baseUrl}${source.gcodeUrl}'),
      );
      final response = await request.close();
      await response.drain<void>();

      expect(heard.single, {'path': _path, 'x-api-key': 'bb_key'});
    });
  });
}
