import 'dart:io';
import 'dart:typed_data';

import 'package:bambuddy_mobile/core/api/api_client.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/custom_ca.dart';
import 'package:bambuddy_mobile/core/api/edge_access.dart';
import 'package:bambuddy_mobile/core/api/media_auth.dart';
import 'package:bambuddy_mobile/core/api/tls_overrides.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/features/archive/timelapse_screen.dart';
import 'package:bambuddy_mobile/features/archive/timelapse_url.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

// Cloudflare Access (#72) in front of the timelapse: the player (ExoPlayer)
// follows a redirect with every header it holds, so the question is asked first
// with the Dart client, which does not. Asked as a HEAD, which has no body to
// stop.

const _login = 'https://team.cloudflareaccess.com/cdn-cgi/access/login/x';
const _video =
    'https://printers.example.com/api/v1/archives/42/timelapse?token=t';

final _token = ServiceToken(
  host: 'printers.example.com',
  clientId: 'abc.access',
  clientSecret: 's3cret',
);

/// What the server (and Cloudflare) answer the HEAD question with.
enum _Answer { video, signIn, idpChain, otherRedirect, error, down }

class _Server implements HttpClientAdapter {
  _Server(this.answer);

  final _Answer answer;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    switch (answer) {
      case _Answer.down:
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'no route',
        );
      case _Answer.video:
        return ResponseBody.fromBytes(const [], 200);
      case _Answer.otherRedirect:
        // Some other proxy's sign-in, which EdgeRequest does not follow either.
        return ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': ['https://sso.example.net/login'],
          },
        );
      case _Answer.error:
        return ResponseBody.fromString('boom', 500);
      case _Answer.signIn:
        // A request that carries a credential is handed the 302 itself.
        return ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': [_login],
          },
        );
      case _Answer.idpChain:
        return ResponseBody.fromString('<html>idp</html>', 200)
          ..redirects = [
            RedirectRecord(302, 'GET', Uri.parse(_login)),
            RedirectRecord(302, 'GET', Uri.parse('https://idp.example.net/a')),
          ];
    }
  }

  @override
  void close({bool force = false}) {}
}

TimelapseSource _source({String url = _video}) =>
    (url: url, auth: const MediaAuth(headers: {'X-API-Key': 'bb_key'}));

Dio _dio(_Server server) => createBareDio()..httpClientAdapter = server;

void main() {
  tearDown(() => useTls(null, null));

  group('checkEdgeAccess', () {
    test('asks nothing while no credential is presented', () async {
      final server = _Server(_Answer.signIn);
      await checkEdgeAccess(_dio(server), _source());
      expect(server.requests, isEmpty);
    });

    test('asks nothing for a video on another host', () async {
      useTls(null, null, _token);
      final server = _Server(_Answer.signIn);
      await checkEdgeAccess(
        _dio(server),
        _source(url: 'https://cdn.example.net/v.mp4'),
      );
      expect(server.requests, isEmpty);
    });

    test('asks with a HEAD, as the session does', () async {
      useTls(null, null, _token);
      final server = _Server(_Answer.video);
      await checkEdgeAccess(_dio(server), _source());

      expect(server.requests, hasLength(1));
      final request = server.requests.single;
      expect(request.method, 'HEAD');
      expect(request.headers['X-API-Key'], 'bb_key');
      expect(request.headers, isNot(contains('Range')));
    });

    test('is the refusal when Cloudflare redirects the request', () async {
      useTls(null, null, _token);
      await expectLater(
        checkEdgeAccess(_dio(_Server(_Answer.signIn)), _source()),
        throwsA(
          isA<EdgeAccessException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.edgeAccessRejected,
          ),
        ),
      );
    });

    test('and when it sends the request on to an identity provider', () async {
      useTls(null, null, _token);
      await expectLater(
        checkEdgeAccess(_dio(_Server(_Answer.idpChain)), _source()),
        throwsA(isA<EdgeAccessException>()),
      );
    });

    test('refuses a redirect to anywhere else too, with its status', () async {
      // The player would follow it with every credential it holds.
      useTls(null, null, _token);
      await expectLater(
        checkEdgeAccess(_dio(_Server(_Answer.otherRedirect)), _source()),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 302)),
      );
    });

    test('leaves any other answer to the player', () async {
      useTls(null, null, _token);
      await checkEdgeAccess(_dio(_Server(_Answer.error)), _source());
      await checkEdgeAccess(_dio(_Server(_Answer.down)), _source());
    });
  });

  group('on a real socket', () {
    test('does not pull down a video the server sent whole', () async {
      // The server ignores ranges and sends 12 MB, a chunk at a time, to any GET.
      // The question is a HEAD, so the video is never asked for.
      final mocked = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = mocked);
      final context = SecurityContext()
        ..useCertificateChainBytes(
          File('test/fixtures/tls/server.pem').readAsBytesSync(),
        )
        ..usePrivateKeyBytes(
          File('test/fixtures/tls/server.key').readAsBytesSync(),
        );
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      addTearDown(() => server.close(force: true));
      final methods = <String>[];
      var written = 0;
      server.listen((request) async {
        methods.add(request.method);
        if (request.method != 'GET') {
          await request.response.close();
          return;
        }
        final chunk = Uint8List(64 * 1024);
        try {
          for (var i = 0; i < 200; i++) {
            request.response.add(chunk);
            await request.response.flush();
            written++;
          }
          await request.response.close();
        } on Object {
          // The client went away.
        }
      });
      useTls(
        CustomCa.parse(
          'ca.pem',
          File('test/fixtures/tls/ca.pem').readAsBytesSync(),
        ),
        null,
        ServiceToken(host: '127.0.0.1', clientId: 'a', clientSecret: 'b'),
      );

      await checkEdgeAccess(
        createBareDio(),
        _source(
          url:
              'https://127.0.0.1:${server.port}/api/v1/archives/42/timelapse?token=t',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(methods, ['HEAD']);
      expect(written, 0);
    });
  });

  group('the screen', () {
    late SharedPreferences prefs;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    Future<void> pumpScreen(
      WidgetTester tester,
      _Answer answer, {
      bool settle = true,
    }) async {
      useTls(null, null, _token);
      await pumpPhone(
        tester,
        const TimelapseScreen(archiveId: 42),
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          serverProfileOverride(
            const ServerProfile(
              baseUrl: 'https://printers.example.com',
              authMode: AuthMode.none,
            ),
          ),
          credentialsStoreProvider.overrideWithValue(
            InMemoryCredentialsStore(),
          ),
          mediaAuthServiceProvider.overrideWithValue(_FakeMediaAuth()),
          bareDioProvider.overrideWithValue(_dio(_Server(answer))),
        ],
      );
      // A failure with a status keeps an animation going.
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump(const Duration(seconds: 1));
      }
    }

    testWidgets('says Cloudflare refused it and starts no player', (
      tester,
    ) async {
      await pumpScreen(tester, _Answer.signIn);

      expect(find.text(pl.errEdgeAccessRejected), findsOneWidget);
      // The player was never built, so it never failed in its own way.
      expect(find.text(pl.timelapseError), findsNothing);
    });

    testWidgets('a redirect to anywhere else is shown with its status', (
      tester,
    ) async {
      await pumpScreen(tester, _Answer.otherRedirect, settle: false);

      expect(find.text(pl.timelapseHttpError(302)), findsOneWidget);
      expect(find.text(pl.timelapseError), findsNothing);
    });
  });
}

class _FakeMediaAuth extends MediaAuthService {
  _FakeMediaAuth()
    : super.forIsolate(
        dio: Dio(),
        authMode: AuthMode.none,
        credentials: InMemoryCredentialsStore(),
      );

  @override
  Future<MediaAuth> auth({bool forceRefresh = false}) async =>
      const MediaAuth(queryToken: 't');
}
