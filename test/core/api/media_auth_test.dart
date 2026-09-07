import 'package:bambuddy_mobile/core/api/camera_token.dart';
import 'package:bambuddy_mobile/core/api/media_auth.dart';
import 'package:bambuddy_mobile/core/api/media_token.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

const _baseUrl = 'http://s.local:8000';
const _mediaPath = '/api/v1/auth/media-token';

/// Counts what each mint route was actually asked, and answers the media one
/// with [mediaStatus]. The mock adapter cannot do this: its route handler runs
/// once at declaration, so it can neither count calls nor change its answer.
class _MintStub extends Interceptor {
  /// What `POST /auth/media-token` answers; 404 is a server older than #3025.
  var mediaStatus = 200;
  var mediaMints = 0;
  var cameraMints = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path == _mediaPath) {
      mediaMints++;
      if (mediaStatus != 200) {
        return handler.reject(
          DioException(
            requestOptions: options,
            response: Response(
              requestOptions: options,
              statusCode: mediaStatus,
            ),
          ),
        );
      }
      return handler.resolve(
        Response(
          requestOptions: options,
          statusCode: 200,
          data: {'token': 'media$mediaMints'},
        ),
      );
    }
    cameraMints++;
    handler.resolve(
      Response(
        requestOptions: options,
        statusCode: 200,
        data: {'token': 'cam$cameraMints'},
      ),
    );
  }
}

void main() {
  late Dio dio;
  late _MintStub mints;

  MediaAuthService serviceFor(AuthMode authMode, {String? apiKey = 'bb_key'}) =>
      MediaAuthService(
        media: MediaTokenService(dio),
        camera: CameraTokenService(dio),
        authMode: authMode,
        credentials: InMemoryCredentialsStore()..apiKey = apiKey,
      );

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: _baseUrl));
    mints = _MintStub();
    dio.interceptors.add(mints);
  });

  group('MediaAuth.sign', () {
    test('appends the token to a bare URL', () {
      const auth = MediaAuth(queryToken: 'abc');
      expect(
        auth.sign('$_baseUrl/x/thumbnail'),
        '$_baseUrl/x/thumbnail?token=abc',
      );
    });

    test('keeps a query the caller already put there', () {
      const auth = MediaAuth(queryToken: 'abc');
      expect(
        auth.sign('$_baseUrl/printers/1/cover?view=top'),
        '$_baseUrl/printers/1/cover?view=top&token=abc',
      );
    });

    test('escapes a token that is not URL-safe', () {
      const auth = MediaAuth(queryToken: 'a b&c');
      expect(auth.sign('/x'), '/x?token=a+b%26c');
    });

    test('leaves the URL alone when the credential is a header', () {
      const auth = MediaAuth(headers: {'X-API-Key': 'bb_key'});
      expect(auth.sign('$_baseUrl/x?view=top'), '$_baseUrl/x?view=top');
      expect(auth.query, isEmpty);
    });

    test('query mirrors the token so a Dio caller sends the same thing', () {
      expect(const MediaAuth(queryToken: 'abc').query, {'token': 'abc'});
    });
  });

  group('MediaAuthService', () {
    test('a signed-in user gets the media token in the query', () async {
      final auth = await serviceFor(AuthMode.jwt).auth();

      expect(auth.queryToken, 'media1');
      expect(auth.headers, isEmpty);
      expect(mints.cameraMints, 0, reason: 'the camera token is not involved');
    });

    test(
      'an API key gets the header, because the route refuses its token',
      () async {
        final auth = await serviceFor(AuthMode.apiKey).auth();

        expect(auth.queryToken, isNull);
        expect(auth.headers, {'X-API-Key': 'bb_key'});
      },
    );

    test('an API-key session with no key stored signs nothing', () async {
      final auth = await serviceFor(AuthMode.apiKey, apiKey: null).auth();

      expect(auth.queryToken, isNull);
      expect(auth.headers, isEmpty);
    });

    test('a server without the mint falls back to the camera token', () async {
      mints.mediaStatus = 404;

      final auth = await serviceFor(AuthMode.jwt).auth();

      expect(auth.queryToken, 'cam1');
      expect(auth.headers, isEmpty);
    });

    test(
      'an API key on such a server also falls back — the header is refused there',
      () async {
        mints.mediaStatus = 404;

        final auth = await serviceFor(AuthMode.apiKey).auth();

        expect(auth.queryToken, 'cam1');
        expect(auth.headers, isEmpty);
      },
    );

    test('the missing mint is asked for once, not per image', () async {
      mints.mediaStatus = 404;
      final service = serviceFor(AuthMode.jwt);

      await service.auth();
      await service.auth();
      await service.auth();

      expect(mints.mediaMints, 1);
    });

    test(
      'invalidate re-probes the mint — the server may have been upgraded',
      () async {
        mints.mediaStatus = 404;
        final service = serviceFor(AuthMode.jwt);
        expect((await service.auth()).queryToken, 'cam1');

        mints.mediaStatus = 200;
        service.invalidate();

        expect((await service.auth()).queryToken, 'media2');
      },
    );

    test(
      'invalidate drops the token the next call would have reused',
      () async {
        final service = serviceFor(AuthMode.jwt);
        expect((await service.auth()).queryToken, 'media1');
        expect((await service.auth()).queryToken, 'media1', reason: 'cached');

        service.invalidate();

        expect((await service.auth()).queryToken, 'media2');
      },
    );

    test(
      'forceRefresh mints without waiting for the lifetime to lapse',
      () async {
        final service = serviceFor(AuthMode.jwt);
        await service.auth();

        expect((await service.auth(forceRefresh: true)).queryToken, 'media2');
      },
    );

    test(
      'forceRefresh re-probes too, so the isolate that never invalidates still '
      'notices an upgraded server',
      () async {
        mints.mediaStatus = 404;
        final service = serviceFor(AuthMode.jwt);
        expect((await service.auth()).queryToken, 'cam1');

        mints.mediaStatus = 200;

        expect((await service.auth(forceRefresh: true)).queryToken, 'media2');
      },
    );

    test(
      'invalidate drops the camera token on the fallback path, where it is the '
      'credential that just failed',
      () async {
        mints.mediaStatus = 404;
        final service = serviceFor(AuthMode.jwt);
        expect((await service.auth()).queryToken, 'cam1');

        service.invalidate();

        expect((await service.auth()).queryToken, 'cam2');
      },
    );

    test(
      'invalidate leaves the camera token alone on a server that has the mint '
      '— there it belongs to the live view, which re-mints it itself',
      () async {
        final service = serviceFor(AuthMode.jwt);
        await service.auth();

        service.invalidate();
        await service.auth();

        expect(mints.cameraMints, 0);
      },
    );

    test('expiresAt is null while the credential is a header', () async {
      final service = serviceFor(AuthMode.apiKey);
      await service.auth();

      expect(service.expiresAt, isNull);
    });

    test('expiresAt follows whichever token is in play', () async {
      final signedIn = serviceFor(AuthMode.jwt);
      await signedIn.auth();
      expect(signedIn.expiresAt, isNotNull);

      mints.mediaStatus = 404;
      final old = serviceFor(AuthMode.jwt);
      await old.auth();
      expect(old.expiresAt, isNotNull, reason: 'the camera token TTL');
    });
  });
}
