import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bambuddy_mobile/core/api/api_client.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/custom_ca.dart';
import 'package:bambuddy_mobile/core/api/edge_access.dart';
import 'package:bambuddy_mobile/core/api/tls_overrides.dart';
import 'package:bambuddy_mobile/core/api/ws_client.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _token = ServiceToken(
  host: '127.0.0.1',
  clientId: 'abc.access',
  clientSecret: 's3cret',
);

final _session = BrowserSession(
  host: '127.0.0.1',
  cookie: 'eyJ.jwt.value',
  expiresAt: DateTime.utc(2027, 1, 2, 3, 4, 5),
);

void main() {
  group('model', () {
    test('a service token sends the two Cloudflare headers', () {
      expect(_token.headers, {
        'CF-Access-Client-Id': 'abc.access',
        'CF-Access-Client-Secret': 's3cret',
      });
    });

    test('a browser session sends the cookie by Cloudflare\'s name', () {
      expect(_session.headers, {'Cookie': 'CF_Authorization=eyJ.jwt.value'});
    });

    test('both kinds survive their own JSON', () {
      for (final access in <EdgeAccess>[_token, _session]) {
        expect(EdgeAccess.fromJson(access.toJson()), access);
      }
    });

    test('the host is compared without regard to case', () {
      final built = ServiceToken(
        host: 'Printers.Example.COM',
        clientId: 'a',
        clientSecret: 'b',
      );
      final read = EdgeAccess.fromJson(built.toJson())!;
      expect(built.host, 'printers.example.com');
      expect(read, built);
      bool applies(String url) => read.appliesTo(Uri.parse(url));
      expect(applies('https://PRINTERS.example.com/x'), isTrue);
      expect(applies('https://example.com/'), isFalse);
      expect(applies('https://printers.example.com.evil.net/'), isFalse);
    });

    test('only https carries it, whatever the host', () {
      bool applies(String url) => _token.appliesTo(Uri.parse(url));
      expect(applies('https://127.0.0.1:8443/'), isTrue);
      expect(applies('http://127.0.0.1/'), isFalse);
      expect(
        applies('wss://127.0.0.1/ws'),
        isFalse,
        reason: 'not a URL scheme',
      );
    });

    test('an unknown kind, or no host, reads as none', () {
      expect(EdgeAccess.fromJson({'kind': 'passkey', 'host': 'a'}), isNull);
      expect(EdgeAccess.fromJson({'kind': 'service_token'}), isNull);
      expect(
        EdgeAccess.fromJson({'kind': 'service_token', 'host': ''}),
        isNull,
      );
    });
  });

  group('store', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('writes, reads and removes', () async {
      final store = EdgeAccessStore();
      await store.write(_session);
      expect(await store.read(), _session);
      await store.write(null);
      expect(await store.read(), isNull);
    });

    test('an unreadable entry reads as none', () async {
      FlutterSecureStorage.setMockInitialValues({'edge_access': '{not json'});
      expect(await EdgeAccessStore().read(), isNull);
    });

    test('is not read while preferences say there is none', () async {
      FlutterSecureStorage.setMockInitialValues({
        'edge_access': jsonEncode(_token.toJson()),
      });
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsRepository(
        await SharedPreferences.getInstance(),
      );
      expect(await loadEdgeAccess(settings), isNull);
      await settings.saveHasEdgeAccess(true);
      expect(await loadEdgeAccess(settings), _token);
      await settings.saveHasEdgeAccess(false);
      expect(settings.loadHasEdgeAccess(), isFalse);
    });
  });

  group('on the wire', () {
    late HttpServer tls;
    late HttpServer plain;

    /// What each server heard, in order: scheme, method and the headers that
    /// matter, by name.
    final heard = <Map<String, String>>[];

    Map<String, String> last(String scheme) =>
        heard.lastWhere((h) => h['scheme'] == scheme);

    void record(HttpRequest request, String scheme) {
      heard.add({
        'scheme': scheme,
        'method': request.method,
        for (final name in [
          'cf-access-client-id',
          'cf-access-client-secret',
          'cookie',
        ])
          if (request.headers.value(name) != null)
            name: request.headers.value(name)!,
      });
    }

    /// '<scheme> <method> <path>' of every request, in order.
    final paths = <String>[];

    /// Path to the status and `Location` the server answers it with, for the
    /// redirect tests; `/n/<k>` always redirects to `/n/<k+1>`.
    final redirects = <String, (int, String? Function())>{};

    Future<void> answer(HttpRequest request, String scheme) async {
      record(request, scheme);
      paths.add('$scheme ${request.method} ${request.uri.path}');
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        (await WebSocketTransformer.upgrade(request)).close();
        return;
      }
      final response = request.response;
      final hop = redirects[request.uri.path];
      final chain = RegExp(r'^/n/(\d+)$').firstMatch(request.uri.path);
      if (hop != null) {
        response.statusCode = hop.$1;
        final location = hop.$2();
        if (location != null) response.headers.set('location', location);
      } else if (request.uri.path == '/slowbody') {
        response.statusCode = 302;
        response.headers.set('location', '/after');
        response.write('x');
        await response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 300));
        response.write('y');
      } else if (request.uri.path == '/slow') {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        response.statusCode = 302;
        response.headers.set('location', '/after');
      } else if (chain != null) {
        response.statusCode = 302;
        response.headers.set('location', '/n/${int.parse(chain[1]!) + 1}');
      } else if (request.uri.path == '/body') {
        response.write('chunk1');
        await response.flush();
        response.write('chunk2');
      }
      await response.close();
    }

    setUp(() async {
      // The test binding answers every HttpClient with a canned 400.
      final mocked = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = mocked);
      addTearDown(() => useTls(null, null));
      heard.clear();
      paths.clear();
      redirects.clear();
      final context = SecurityContext()
        ..useCertificateChainBytes(_fixture('server.pem'))
        ..usePrivateKeyBytes(_fixture('server.key'));
      tls = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      plain = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => tls.close(force: true));
      addTearDown(() => plain.close(force: true));
      tls.listen((r) => answer(r, 'https'));
      plain.listen((r) => answer(r, 'http'));
    });

    final ca = CustomCa.parse('ca.pem', _fixture('ca.pem'));

    /// Trusts the fixture CA and presents [access] for 127.0.0.1.
    void present(EdgeAccess access) => useTls(ca, null, access);

    Future<void> dioGet(String url) => Dio().get<void>(url);
    String httpsUrl([String host = '127.0.0.1']) =>
        'https://$host:${tls.port}/';

    test('Dio carries a service token to its host', () async {
      present(_token);
      await dioGet(httpsUrl());
      expect(last('https')['cf-access-client-id'], 'abc.access');
      expect(last('https')['cf-access-client-secret'], 's3cret');
    });

    test('Dio carries a browser cookie to its host', () async {
      present(_session);
      await dioGet(httpsUrl());
      expect(last('https')['cookie'], 'CF_Authorization=eyJ.jwt.value');
    });

    test('another host never sees it', () async {
      present(_token);
      await dioGet(httpsUrl('localhost'));
      expect(last('https').keys, ['scheme', 'method']);
    });

    test('plain http to the same host never carries it', () async {
      present(_token);
      await dioGet('http://127.0.0.1:${plain.port}/');
      expect(last('http').keys, ['scheme', 'method']);
    });

    test('the app\'s web socket handshake carries it over wss', () async {
      // `flutter test` has already made the SDK's static WebSocket client by
      // now, without any override, so this is also the case of a credential
      // added while the app runs: the client must be made per connection.
      present(_token);
      final client = WsClient(
        url: Uri.parse('wss://127.0.0.1:${tls.port}/ws'),
        authHeaders: () async => const {},
      );
      addTearDown(client.dispose);
      final connected = client.connectionStates.firstWhere(
        (s) => s == WsConnectionState.connected,
      );
      client.start();
      await connected.timeout(const Duration(seconds: 5));
      expect(last('https')['cf-access-client-id'], 'abc.access');
    });

    test('a ws:// handshake never carries it', () async {
      present(_token);
      final client = WsClient(
        url: Uri.parse('ws://127.0.0.1:${plain.port}/ws'),
        authHeaders: () async => const {},
      );
      addTearDown(client.dispose);
      final connected = client.connectionStates.firstWhere(
        (s) => s == WsConnectionState.connected,
      );
      client.start();
      await connected.timeout(const Duration(seconds: 5));
      expect(last('http').keys, ['scheme', 'method']);
    });

    test('every URL verb carries it, and keeps its name', () async {
      present(_token);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final url = Uri.parse(httpsUrl());
      final verbs = <String, Future<HttpClientRequest> Function()>{
        'GET': () => client.getUrl(url),
        'POST': () => client.postUrl(url),
        'PUT': () => client.putUrl(url),
        'DELETE': () => client.deleteUrl(url),
        'PATCH': () => client.patchUrl(url),
        'HEAD': () => client.headUrl(url),
        'OPTIONS': () => client.openUrl('OPTIONS', url),
      };
      for (final verb in verbs.entries) {
        await (await verb.value()).close();
        expect(last('https')['method'], verb.key, reason: verb.key);
        expect(
          last('https')['cf-access-client-id'],
          'abc.access',
          reason: verb.key,
        );
      }
    });

    test('the host-and-port verbs are plain http and carry nothing', () async {
      present(_token);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final verbs = <String, Future<HttpClientRequest> Function()>{
        'GET': () => client.get('127.0.0.1', plain.port, '/'),
        'POST': () => client.post('127.0.0.1', plain.port, '/'),
        'PUT': () => client.put('127.0.0.1', plain.port, '/'),
        'DELETE': () => client.delete('127.0.0.1', plain.port, '/'),
        'PATCH': () => client.patch('127.0.0.1', plain.port, '/'),
        'HEAD': () => client.head('127.0.0.1', plain.port, '/'),
        'OPTIONS': () => client.open('OPTIONS', '127.0.0.1', plain.port, '/'),
      };
      for (final verb in verbs.entries) {
        await (await verb.value()).close();
        expect(last('http')['method'], verb.key, reason: verb.key);
        expect(last('http').keys, ['scheme', 'method'], reason: verb.key);
      }
    });

    test('the client keeps its own settings', () async {
      present(_token);
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3)
        ..idleTimeout = const Duration(seconds: 7)
        ..autoUncompress = false;
      addTearDown(() => client.close(force: true));
      expect(client.connectionTimeout, const Duration(seconds: 3));
      expect(client.idleTimeout, const Duration(seconds: 7));
      expect(client.autoUncompress, isFalse);
    });

    test('taking it back sends nothing again', () async {
      present(_token);
      useTls(ca, null);
      await dioGet(httpsUrl());
      expect(last('https').keys, ['scheme', 'method']);
    });

    test('a different credential replaces the first one', () async {
      present(_token);
      present(_session);
      await dioGet(httpsUrl());
      expect(last('https')['cookie'], isNotNull);
      expect(last('https').containsKey('cf-access-client-id'), isFalse);
    });

    group('redirects', () {
      Future<Response<String>> get(
        String path, {
        Options? options,
        String host = '127.0.0.1',
      }) => Dio().get<String>(
        'https://$host:${tls.port}$path',
        options: (options ?? Options()).copyWith(validateStatus: (_) => true),
      );

      test('one to the same origin is followed, credential and all', () async {
        present(_token);
        redirects['/hop'] = (302, () => '/final');
        final response = await get('/hop');
        expect(response.statusCode, 200);
        expect(paths, ['https GET /hop', 'https GET /final']);
        expect(heard.map((h) => h['cf-access-client-id']), [
          'abc.access',
          'abc.access',
        ]);
      });

      test('an absolute URL on the same origin counts as the same', () async {
        present(_token);
        redirects['/hop'] = (301, () => '${httpsUrl()}final');
        expect((await get('/hop')).statusCode, 200);
        expect(paths, ['https GET /hop', 'https GET /final']);
      });

      test('a 303 turns a POST into a GET, as dart:io does', () async {
        present(_token);
        redirects['/post'] = (303, () => '/final');
        await Dio().post<void>(
          '${httpsUrl()}post',
          data: 'x',
          options: Options(validateStatus: (_) => true),
        );
        expect(paths, ['https POST /post', 'https GET /final']);
      });

      test(
        'another host is not followed, and the token stays behind',
        () async {
          present(_token);
          redirects['/hop'] = (302, () => '${httpsUrl('localhost')}final');
          final response = await get('/hop');
          expect(response.statusCode, 302);
          expect(
            response.headers.value('location'),
            '${httpsUrl('localhost')}final',
          );
          expect(paths, ['https GET /hop']);
        },
      );

      test('another port is another origin', () async {
        present(_token);
        redirects['/hop'] = (302, () => 'https://127.0.0.1:1/final');
        expect((await get('/hop')).statusCode, 302);
        expect(paths, ['https GET /hop']);
      });

      test('a downgrade to http is not followed', () async {
        present(_token);
        redirects['/hop'] = (302, () => 'http://127.0.0.1:${plain.port}/final');
        expect((await get('/hop')).statusCode, 302);
        expect(paths, ['https GET /hop']);
      });

      test(
        'Dio reports a redirect it was not let follow as a bad response',
        () async {
          present(_token);
          redirects['/hop'] = (302, () => '${httpsUrl('localhost')}final');
          await expectLater(
            Dio().get<void>('${httpsUrl()}hop'),
            throwsA(
              isA<DioException>().having(
                (e) => e.response?.statusCode,
                'status',
                302,
              ),
            ),
          );
        },
      );

      test('a request that asked not to follow gets the 3xx at once', () async {
        present(_token);
        redirects['/hop'] = (302, () => '/final');
        final response = await get(
          '/hop',
          options: Options(followRedirects: false),
        );
        expect(response.statusCode, 302);
        expect(paths, ['https GET /hop']);
      });

      test(
        'the limit is the caller\'s, and past it the request fails',
        () async {
          present(_token);
          await expectLater(
            get('/n/0'),
            throwsA(
              isA<DioException>().having(
                (e) => e.error,
                'error',
                isA<RedirectException>(),
              ),
            ),
          );
          expect(paths.length, 6, reason: 'the first request and five hops');
          paths.clear();
          await expectLater(
            get('/n/0', options: Options(maxRedirects: 2)),
            throwsA(isA<DioException>()),
          );
          expect(paths.length, 3);
        },
      );

      test('a loop is reported, not followed for ever', () async {
        present(_token);
        redirects['/a'] = (302, () => '/b');
        redirects['/b'] = (302, () => '/a');
        await expectLater(
          get('/a'),
          throwsA(
            isA<DioException>().having(
              (e) => '${e.error}',
              'error',
              contains('loop'),
            ),
          ),
        );
      });

      test(
        'a redirect with no Location is the same error dart:io gives',
        () async {
          present(_token);
          redirects['/hop'] = (302, () => '');
          // The header is set to an empty string: the first hop is to this very
          // path, which is a loop; either way it must end, and in an error.
          await expectLater(get('/hop'), throwsA(isA<DioException>()));
        },
      );

      test('the body after a followed redirect arrives whole', () async {
        present(_token);
        redirects['/hop'] = (302, () => '/body');
        expect((await get('/hop')).data, 'chunk1chunk2');
      });

      test(
        'a request without the credential follows to any host, as before',
        () async {
          present(
            ServiceToken(
              host: 'example.test',
              clientId: 'a',
              clientSecret: 'b',
            ),
          );
          redirects['/hop'] = (302, () => '${httpsUrl('localhost')}body');
          expect((await get('/hop')).data, 'chunk1chunk2');
          expect(paths, ['https GET /hop', 'https GET /body']);
        },
      );

      test(
        'a redirect with no Location header is the error dart:io gives',
        () async {
          present(_token);
          redirects['/hop'] = (302, () => null);
          await expectLater(
            get('/hop'),
            throwsA(
              isA<DioException>().having(
                (e) => e.error,
                'error',
                isA<RedirectException>(),
              ),
            ),
          );
        },
      );

      test('a Location that is not a URI ends in an error', () async {
        present(_token);
        redirects['/hop'] = (302, () => 'http://[::1');
        await expectLater(get('/hop'), throwsA(isA<DioException>()));
      });
    });

    group('a credential Cloudflare does not accept', () {
      // Access answers a request with a token it does not know by a 302 to its
      // team domain. A request that carries the token never follows that, so
      // the app must still tell the user what it was.
      test('is reported as refused, not as a failure to connect', () async {
        present(_token);
        redirects['/hop'] = (
          302,
          () => 'https://team.cloudflareaccess.com/cdn-cgi/access/login/x',
        );
        try {
          await createBareDio().get<void>('${httpsUrl()}hop');
          fail('let through');
        } on DioException catch (e) {
          expect(mapDioException(e).code, AppErrorCode.edgeAccessRejected);
        }
        // The team domain was never asked.
        expect(paths, ['https GET /hop']);
      });
    });

    group('the request itself', () {
      /// A client made now, so it is made after `present` installed the
      /// override: a client keeps what was in force when it was created.
      Future<HttpClientRequest> open(String method, String path) {
        final client = HttpClient();
        addTearDown(() => client.close(force: true));
        return client.openUrl(
          method,
          Uri.parse('${httpsUrl()}${path.substring(1)}'),
        );
      }

      test(
        'a Cookie the caller sets is kept beside the session cookie',
        () async {
          present(_session);
          // A 2FA call sends its own Cookie after the request is opened, and with
          // a body, which is written before `close`.
          for (final withBody in [false, true]) {
            final request = await open(withBody ? 'POST' : 'GET', '/x');
            request.headers.set('Cookie', '2fa_challenge=xyz');
            if (withBody) request.write('body');
            await (await request.close()).drain<void>();
            expect(
              last('https')['cookie'],
              '2fa_challenge=xyz; CF_Authorization=eyJ.jwt.value',
              reason: 'body: $withBody',
            );
          }
        },
      );

      test('the cookie jar is folded in with "; ", not ", "', () async {
        present(_session);
        final request = await open('GET', '/x');
        request.cookies.add(Cookie('a', 'b'));
        await (await request.close()).drain<void>();
        expect(last('https')['cookie'], 'a=b; CF_Authorization=eyJ.jwt.value');
      });

      test('many writes still send the session cookie once', () async {
        present(_session);
        final request = await open('POST', '/x');
        request.headers.set('Cookie', 'x=y');
        request
          ..write('a')
          ..write('b')
          ..add([99]);
        await request.flush();
        await (await request.close()).drain<void>();
        expect(last('https')['cookie'], 'x=y; CF_Authorization=eyJ.jwt.value');
      });

      test('a Cookie set after an empty write does not displace it', () async {
        present(_session);
        final request = await open('POST', '/x');
        // Nothing is buffered, so no header is committed yet.
        request
          ..add(const [])
          ..write('')
          ..writeAll(const []);
        await request.flush();
        request.headers.set('Cookie', 'late=1');
        await (await request.close()).drain<void>();
        expect(
          last('https')['cookie'],
          'late=1; CF_Authorization=eyJ.jwt.value',
        );
      });

      test('the token headers win over any the caller set', () async {
        present(_token);
        final request = await open('GET', '/x');
        request.headers.set('CF-Access-Client-Id', 'someone-else');
        await (await request.close()).drain<void>();
        expect(last('https')['cf-access-client-id'], 'abc.access');
      });

      test('close twice is one request, and its future is done', () async {
        present(_token);
        final request = await open('GET', '/x');
        final first = request.close();
        expect(request.close(), same(first));
        expect(request.done, same(first));
        await first;
        expect(paths, ['https GET /x']);
      });

      test('close while a stream is being added throws, then works', () async {
        present(_token);
        final request = await open('POST', '/x');
        final body = StreamController<List<int>>();
        final adding = request.addStream(body.stream);
        expect(request.close, throwsStateError);
        body.add([1, 2, 3]);
        await body.close();
        await adding;
        expect((await request.close()).statusCode, 200);
      });

      test('abort before close completes done with an error', () async {
        present(_token);
        final request = await open('GET', '/x');
        request.abort();
        await expectLater(request.done, throwsA(isA<HttpException>()));
        expect(paths, isEmpty);
      });

      test('abort while a redirect body drains stops the chain too', () async {
        present(_token);
        final request = await open('GET', '/slowbody');
        final sent = request.close();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        request.abort();
        await expectLater(sent, throwsA(isA<HttpException>()));
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(paths, ['https GET /slowbody']);
      });

      test(
        'a Cookie header in odd shapes still ends as one clean value',
        () async {
          present(_session);
          final request = await open('GET', '/x');
          request.headers.set('Cookie', 'a=1;CF_Authorization=old; ');
          await (await request.close()).drain<void>();
          expect(
            last('https')['cookie'],
            'a=1; CF_Authorization=eyJ.jwt.value',
          );
        },
      );

      test('several Cookie lines are sent as one', () async {
        present(_session);
        final request = await open('GET', '/x');
        // Joined, the lines already equal what the credential wants, so only a
        // check for one value tells them from the right header.
        request.headers
          ..add('Cookie', 'a=1')
          ..add('Cookie', 'CF_Authorization=eyJ.jwt.value');
        await (await request.close()).drain<void>();
        expect(last('https')['cookie'], 'a=1; CF_Authorization=eyJ.jwt.value');
      });

      test('abort during a redirect hop stops the chain', () async {
        present(_token);
        redirects['/hop'] = (302, () => '/slow');
        final request = await open('GET', '/hop');
        final sent = request.close();
        // Let the first hop answer, so the second (the slow one) is in flight.
        await Future<void>.delayed(const Duration(milliseconds: 150));
        request.abort();
        await expectLater(sent, throwsA(isA<HttpException>()));
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(paths, ['https GET /hop', 'https GET /slow']);
      });
    });
  });
}

// Fixtures in test/fixtures/tls: a throwaway root CA (its key discarded) and a
// server certificate it signed for localhost and 127.0.0.1.
List<int> _fixture(String name) =>
    File('test/fixtures/tls/$name').readAsBytesSync();
