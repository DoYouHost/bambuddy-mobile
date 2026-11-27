import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bambuddy_mobile/core/api/client_cert.dart';
import 'package:bambuddy_mobile/core/api/custom_ca.dart';
import 'package:bambuddy_mobile/core/api/edge_access.dart';
import 'package:bambuddy_mobile/core/api/loopback_proxy.dart';
import 'package:bambuddy_mobile/core/api/tls_overrides.dart';
import 'package:flutter_test/flutter_test.dart';

// The loopback bridge (#62, #65): ExoPlayer and a WebView cannot reach a server
// behind a private CA or mutual TLS (NativeTlsTest shows that on a device), so
// the app fetches for them through dart:io. The upstream here is a real TLS
// server whose certificate only the imported CA vouches for, and which sees the
// client certificate the app presents.

List<int> _fixture(String name) =>
    File('test/fixtures/tls/$name').readAsBytesSync();

final _payload = Uint8List.fromList([for (var i = 0; i < 1000; i++) i % 251]);

void main() {
  late HttpServer upstream;
  late HttpOverrides? mocked;

  /// What the upstream heard: path, the headers that matter and the subject of
  /// the client certificate, in order.
  final heard = <Map<String, String>>[];

  setUp(() async {
    // The test binding answers every HttpClient with a canned 400.
    mocked = HttpOverrides.current;
    HttpOverrides.global = null;
    heard.clear();
    final context = SecurityContext()
      ..useCertificateChainBytes(_fixture('server.pem'))
      ..usePrivateKeyBytes(_fixture('server.key'))
      ..setTrustedCertificatesBytes(_fixture('client-ca.pem'));
    upstream = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
      requestClientCertificate: true,
    );
    upstream.listen((request) async {
      heard.add({
        'path': request.uri.path,
        'method': request.method,
        'subject': request.certificate?.subject ?? 'none',
        for (final name in [
          'x-api-key',
          'authorization',
          'range',
          'cf-access-client-id',
          'x-evil',
          'accept-encoding',
        ])
          if (request.headers.value(name) != null)
            name: request.headers.value(name)!,
      });
      final response = request.response;
      switch (request.uri.path) {
        case '/redirect':
          response.statusCode = 302;
          response.headers.set('location', '/video');
        case '/gzip':
          final bytes = gzip.encode(_payload);
          response.headers.set('content-encoding', 'gzip');
          response.headers.contentLength = bytes.length;
          response.add(bytes);
        default:
          final range = request.headers.value('range');
          response.headers.set('accept-ranges', 'bytes');
          response.headers.contentType = ContentType('video', 'mp4');
          if (range != null) {
            final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
            final from = int.parse(m[1]!);
            final to = int.parse(m[2]!);
            response.statusCode = 206;
            response.headers.set(
              'content-range',
              'bytes $from-$to/${_payload.length}',
            );
            response.add(_payload.sublist(from, to + 1));
          } else {
            response.add(_payload);
          }
      }
      await response.close();
    });
  });

  tearDown(() async {
    await upstream.close(force: true);
    useTls(null, null);
    HttpOverrides.global = mocked;
  });

  final ca = CustomCa.parse('ca.pem', _fixture('ca.pem'));
  final cert = ClientCert.parse(
    'phone.p12',
    _fixture('client.p12'),
    'fixture',
  ).cert;

  /// The upstream, as the app would be told to reach it.
  Uri target([String path = '/video']) =>
      Uri.parse('https://127.0.0.1:${upstream.port}$path');

  /// A plain client: what ExoPlayer or a WebView is, asking the loopback.
  Future<(int, Map<String, String>, List<int>)> ask(
    Uri url, {
    String method = 'GET',
    Map<String, String> headers = const {},
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, url)
        ..followRedirects = false;
      headers.forEach(request.headers.set);
      final response = await request.close();
      final body = <int>[];
      await for (final chunk in response) {
        body.addAll(chunk);
      }
      final seen = <String, String>{};
      response.headers.forEach((name, values) => seen[name] = values.first);
      return (response.statusCode, seen, body);
    } finally {
      client.close(force: true);
    }
  }

  group('what it is for', () {
    test(
      'a native stack cannot reach a server on a private CA itself',
      () async {
        // The state of things without the bridge: nothing vouches for it.
        useTls(ca, cert);
        final plain = HttpClient(context: SecurityContext());
        addTearDown(() => plain.close(force: true));
        await expectLater(
          plain.getUrl(target()),
          throwsA(isA<HandshakeException>()),
        );
      },
    );

    test('is wanted only for https with a CA or a client certificate', () {
      expect(
        needsLoopbackBridge(
          Uri.parse('https://h.example.com/x'),
          presentsTlsIdentity: true,
        ),
        isTrue,
      );
      expect(
        needsLoopbackBridge(
          Uri.parse('https://h.example.com/x'),
          presentsTlsIdentity: false,
        ),
        isFalse,
      );
      expect(
        needsLoopbackBridge(
          Uri.parse('http://h.example.com/x'),
          presentsTlsIdentity: true,
        ),
        isFalse,
      );
    });

    test('tls_overrides says whether there is an identity', () {
      expect(presentsTlsIdentity(), isFalse);
      useTls(ca, null);
      expect(presentsTlsIdentity(), isTrue);
      useTls(null, cert);
      expect(presentsTlsIdentity(), isTrue);
      useTls(
        null,
        null,
        ServiceToken(host: 'h.example.com', clientId: 'a', clientSecret: 'b'),
      );
      expect(presentsTlsIdentity(), isFalse, reason: 'Access is not TLS');
      useTls(null, null);
      expect(presentsTlsIdentity(), isFalse);
    });
  });

  group('through the bridge', () {
    late LoopbackLease lease;

    setUp(() async {
      useTls(ca, cert);
      lease = await LoopbackProxy.lease();
    });
    tearDown(() => lease.release());

    test("fetches with the app's trust and its client certificate", () async {
      final (status, headers, body) = await ask(lease.expose(target()));

      expect(status, 200);
      expect(body, _payload);
      expect(headers['content-type'], contains('video/mp4'));
      expect(heard.single['subject'], contains('bambuddy-mobile test client'));
    });

    test('passes a byte range through, and its answer back', () async {
      final (status, headers, body) = await ask(
        lease.expose(target()),
        headers: {'Range': 'bytes=10-19'},
      );

      expect(status, 206);
      expect(body, _payload.sublist(10, 20));
      expect(headers['content-range'], 'bytes 10-19/1000');
      expect(headers['accept-ranges'], 'bytes');
      expect(heard.single['range'], 'bytes=10-19');
    });

    test('answers HEAD with the headers and no body', () async {
      final (status, headers, body) = await ask(
        lease.expose(target()),
        method: 'HEAD',
      );
      expect(status, 200);
      expect(body, isEmpty);
      expect(headers['accept-ranges'], 'bytes');
      expect(heard.single['method'], 'HEAD');
    });

    test('sends the headers it was given, and only those', () async {
      final url = lease.expose(target(), headers: {'X-API-Key': 'bb_secret'});
      await ask(url, headers: {'Authorization': 'Bearer mine', 'X-Evil': '1'});

      expect(heard.single['x-api-key'], 'bb_secret');
      expect(heard.single, isNot(contains('authorization')));
      expect(heard.single, isNot(contains('x-evil')));
    });

    test('carries Cloudflare Access too, through the wrapper', () async {
      useTls(
        ca,
        cert,
        ServiceToken(
          host: '127.0.0.1',
          clientId: 'abc.access',
          clientSecret: 's',
        ),
      );
      // A lease taken after the change: the client is made with the identity of
      // its time.
      await lease.release();
      lease = await LoopbackProxy.lease();
      await ask(lease.expose(target()));
      expect(heard.single['cf-access-client-id'], 'abc.access');
    });

    test(
      'hands a compressed body on as it is, with its length and encoding',
      () async {
        // A proxy in front of bambuddy may gzip G-code. Unpacked here and sent on
        // with the packed length, the body would outrun its Content-Length.
        final (status, headers, body) = await ask(
          lease.expose(target('/gzip')),
        );

        expect(status, 200);
        expect(headers['content-encoding'], 'gzip');
        // The test client unpacks it, as a player or a page would.
        expect(body, _payload);
        expect(
          heard.single['accept-encoding'],
          'gzip',
          reason: 'as the caller asked',
        );
      },
    );

    test(
      'asks the upstream for what the caller can take, identity by default',
      () async {
        await ask(
          lease.expose(target()),
          headers: {'Accept-Encoding': 'identity'},
        );
        // A caller that says nothing is not offered gzip on dart:io's own accord.
        final client = HttpClient()..autoUncompress = false;
        addTearDown(() => client.close(force: true));
        final request = await client.getUrl(lease.expose(target()));
        request.headers.removeAll('accept-encoding');
        await (await request.close()).drain<void>();

        expect(heard.map((h) => h['accept-encoding']), [
          'identity',
          'identity',
        ]);
      },
    );

    test(
      'a header sent on two lines reaches the upstream as one value',
      () async {
        // Over a raw socket: dart:io's own client folds repeated adds into one
        // line, so only the wire shows the parser two values (`HttpHeaders.value`
        // throws on those).
        final port = Uri.parse(lease.origin).port;
        final socket = await Socket.connect('127.0.0.1', port);
        final path = lease.expose(target()).path;
        socket.write(
          'GET $path HTTP/1.1\r\nHost: 127.0.0.1:$port\r\n'
          'Range: bytes=0-1\r\nRange: bytes=2-3\r\n'
          'Accept-Encoding: gzip\r\nAccept-Encoding: identity\r\n'
          'Connection: close\r\n\r\n',
        );
        final text = latin1.decode([
          for (final chunk in await socket.toList()) ...chunk,
        ]);

        expect(text, startsWith('HTTP/1.1 206'));
        expect(heard.single['range'], 'bytes=0-1, bytes=2-3');
        expect(heard.single['accept-encoding'], 'gzip, identity');
      },
    );

    test('an upstream header sent on two lines is no crash either', () async {
      final context = SecurityContext()
        ..useCertificateChainBytes(_fixture('server.pem'))
        ..usePrivateKeyBytes(_fixture('server.key'));
      final raw = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      addTearDown(raw.close);
      raw.listen((socket) async {
        socket.listen((_) {}, onError: (_) {}, cancelOnError: true);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        socket.write(
          'HTTP/1.1 200 OK\r\nETag: "a"\r\nETag: "b"\r\n'
          'Accept-Ranges: bytes\r\nAccept-Ranges: none\r\n'
          'Content-Length: 2\r\nConnection: close\r\n\r\nok',
        );
        await socket.close();
      });

      final (status, headers, body) = await ask(
        lease.expose(Uri.parse('https://127.0.0.1:${raw.port}/x')),
      );

      expect(status, 200);
      expect(utf8.decode(body), 'ok');
      expect(headers['etag'], '"a"');
    });

    test('hands a redirect back as it is, without following it', () async {
      final (status, headers, _) = await ask(lease.expose(target('/redirect')));
      expect(status, 302);
      expect(headers, isNot(contains('location')));
      expect(heard.map((h) => h['path']), ['/redirect']);
    });

    test('says so when the upstream cannot be reached', () async {
      final url = lease.expose(Uri.parse('https://127.0.0.1:1/never'));
      final (status, _, body) = await ask(url);
      expect(status, 502);
      expect(body, isEmpty);
    });

    test('lets go of the upstream when the caller goes away', () async {
      // A raw TLS socket as the upstream, because it is the only kind that sees
      // the connection close: an HttpServer swallows what it writes to a peer that
      // has left, and would count to the end whatever the bridge did.
      final context = SecurityContext()
        ..useCertificateChainBytes(_fixture('server.pem'))
        ..usePrivateKeyBytes(_fixture('server.key'))
        ..setTrustedCertificatesBytes(_fixture('client-ca.pem'));
      final raw = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        context,
        requestClientCertificate: true,
      );
      addTearDown(raw.close);
      var sent = 0;
      raw.listen((socket) async {
        socket.listen((_) {}, onError: (_) {}, cancelOnError: true);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        try {
          socket.add(
            'HTTP/1.1 200 OK\r\nContent-Length: ${200 * 64 * 1024}\r\n\r\n'
                .codeUnits,
          );
          final chunk = Uint8List(64 * 1024);
          for (var i = 0; i < 200; i++) {
            socket.add(chunk);
            await socket.flush();
            sent++;
            // Slower than the loopback can take it, so the caller is what ends it.
            await Future<void>.delayed(const Duration(milliseconds: 3));
          }
          await socket.close();
        } on Object {
          // The bridge closed the connection.
        }
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(
        lease.expose(Uri.parse('https://127.0.0.1:${raw.port}/stream')),
      );
      final response = await request.close();
      var got = 0;
      final done = Completer<void>();
      late StreamSubscription<List<int>> sub;
      sub = response.listen((chunk) {
        got += chunk.length;
        if (got > 128 * 1024 && !done.isCompleted) {
          done.complete();
          sub.cancel();
        }
      });
      await done.future;
      client.close(force: true);
      // Long enough for the whole file to have been sent had the bridge stayed.
      await Future<void>.delayed(const Duration(milliseconds: 1000));

      expect(sent, lessThan(100), reason: 'of 200 chunks');
    });
  });

  group('what it refuses', () {
    late LoopbackLease lease;
    late Uri exposed;

    setUp(() async {
      useTls(ca, cert);
      lease = await LoopbackProxy.lease();
      exposed = lease.expose(target());
    });
    tearDown(() => lease.release());

    test('any path it was not given', () async {
      final base = Uri.parse(lease.origin);
      for (final path in [
        '/',
        '/video',
        '/${'0' * 32}',
        '${exposed.path}/extra',
        '${exposed.path}/',
      ]) {
        final (status, _, _) = await ask(base.replace(path: path));
        expect(status, 404, reason: path);
      }
      expect(heard, isEmpty);
    });

    test('a Host that is not the loopback address it listens on', () async {
      // DNS rebinding: a page on another name that resolves to 127.0.0.1.
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(exposed);
      request.headers.host = 'evil.example.com';
      final response = await request.close();
      await response.drain<void>();
      expect(response.statusCode, 404);
      expect(heard, isEmpty);
    });

    test('a method that writes', () async {
      for (final method in ['POST', 'PUT', 'DELETE']) {
        final (status, headers, _) = await ask(exposed, method: method);
        expect(status, 405, reason: method);
        expect(headers['allow'], 'GET, HEAD');
      }
      expect(heard, isEmpty);
    });

    test('listens on the loopback only', () async {
      final addresses = await NetworkInterface.list();
      final others = [
        for (final i in addresses)
          for (final a in i.addresses)
            if (!a.isLoopback && a.type == InternetAddressType.IPv4) a,
      ];
      final port = Uri.parse(lease.origin).port;
      for (final address in others) {
        await expectLater(
          Socket.connect(address, port, timeout: const Duration(seconds: 1)),
          throwsA(isA<SocketException>()),
          reason: '$address',
        );
      }
    });

    test('a path nobody can guess: 128 random bits, a new one each time', () {
      final paths = {for (var i = 0; i < 50; i++) lease.expose(target()).path};
      expect(paths, hasLength(50));
      for (final path in paths) {
        expect(path, matches(RegExp(r'^/[0-9a-f]{32}$')));
      }
    });
  });

  group('the lease', () {
    test('shares one listener, and closes it with the last release', () async {
      final a = await LoopbackProxy.lease();
      final b = await LoopbackProxy.lease();
      expect(a.origin, b.origin);
      final url = a.expose(target());

      await a.release();
      expect((await ask(url)).$1, isNot(0), reason: 'b still holds it');

      await b.release();
      await expectLater(ask(url), throwsA(isA<SocketException>()));
    });

    test(
      'takes its own URLs down with it, while another lease keeps the listener',
      () async {
        useTls(ca, cert);
        final a = await LoopbackProxy.lease();
        final b = await LoopbackProxy.lease();
        final mine = a.expose(target());
        final yours = b.expose(target());

        await a.release();

        expect((await ask(mine)).$1, 404, reason: 'a released lease\'s URL');
        expect(
          (await ask(yours)).$1,
          200,
          reason: 'the other lease is untouched',
        );
        expect(() => a.expose(target()), throwsStateError);
        await b.release();
      },
    );

    test('is released once, however many times it is told', () async {
      final a = await LoopbackProxy.lease();
      final b = await LoopbackProxy.lease();
      await a.release();
      await a.release();
      await a.release();
      expect((await ask(b.expose(target()))).$1, isNot(0));
      await b.release();
    });

    test(
      'a lease after the last release is a new listener and new paths',
      () async {
        useTls(ca, cert);
        final first = await LoopbackProxy.lease();
        final old = first.expose(target());
        await first.release();

        final second = await LoopbackProxy.lease();
        addTearDown(second.release);
        final (status, _, _) = await ask(
          Uri.parse(second.origin).replace(path: old.path),
        );
        expect(
          status,
          404,
          reason: 'the old path is gone with the old listener',
        );
        expect(utf8.encode(second.origin), isNotEmpty);
      },
    );
  });
}
