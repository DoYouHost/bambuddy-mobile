import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// What every status the server can answer with turns into. The auth flow reads
/// these codes to decide what to tell the user, and the three that matter are
/// the ones a user can trigger by hand: a wrong password (401), a key without
/// the scope (403), and one attempt too many (429) — bambuddy rate-limits
/// failed logins per username and per IP and answers 429 *before* checking the
/// password, so it must not read as "wrong password".
DioException _badResponse(int status) {
  final options = RequestOptions(path: '/api/v1/auth/login');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      requestOptions: options,
      statusCode: status,
      data: {'detail': 'whatever'},
    ),
  );
}

/// [_badResponse] with the `detail` the route actually wrote, for the cases
/// where that text is the whole point.
DioException _badResponseWithDetail(int status, String detail) {
  final options = RequestOptions(path: '/api/v1/printers/1/print/stop');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      requestOptions: options,
      statusCode: status,
      data: {'detail': detail},
    ),
  );
}

DioException _ofType(DioExceptionType type) => DioException(
      requestOptions: RequestOptions(path: '/api/v1/printers/'),
      type: type,
      message: 'boom',
    );

void main() {
  group('mapDioException by status', () {
    test('401 → unauthorized, as an AuthException', () {
      final mapped = mapDioException(_badResponse(401));
      expect(mapped, isA<AuthException>());
      expect(mapped.code, AppErrorCode.unauthorized);
    });

    test('403 → forbidden, and never unauthorized', () {
      // The difference decides whether the app logs the user out: a key that
      // lacks a permission is not an expired session.
      final mapped = mapDioException(_badResponse(403));
      expect(mapped, isA<AuthException>());
      expect(mapped.code, AppErrorCode.forbidden);
    });

    test('403 keeps what the server said was missing', () {
      // The only party that knows which permission it was is the server, and
      // it says so in both auth modes. Without this the user is told "not
      // allowed" and left to guess which of a dozen permissions it was.
      final mapped = mapDioException(_badResponseWithDetail(
        403,
        "API key does not have 'can_control_printer' permission",
      ));

      expect(mapped.code, AppErrorCode.forbidden);
      expect(mapped.detail, contains('can_control_printer'));
    });

    test('a 403 the server did not explain still maps, with no detail', () {
      // A reverse proxy refusing on its own answers HTML, not {"detail": ...}.
      final options = RequestOptions(path: '/api/v1/printers/');
      final mapped = mapDioException(DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: 403,
          data: '<html>Forbidden</html>',
        ),
      ));

      expect(mapped.code, AppErrorCode.forbidden);
      expect(mapped.detail, isNull);
    });
  });

  group('isApiKeyOwnerDisabled', () {
    test('the deactivated-owner refusal is told apart from a missing permission',
        () {
      // Different remedy: no scope or group change fixes it, the account has
      // to come back. Server 1.2.6+, and it arrives on every route at once.
      final gone = mapDioException(_badResponseWithDetail(
        403,
        'API key owner is deactivated or no longer exists',
      ));
      final missing = mapDioException(_badResponseWithDetail(
        403,
        "API key owner does not have 'printers:control' permission",
      ));

      expect(gone.isApiKeyOwnerDisabled, isTrue);
      expect(missing.isApiKeyOwnerDisabled, isFalse,
          reason: 'both start with "API key owner"');
    });

    test('a refusal with no detail is not claimed to be anything', () {
      const bare = AuthException(AppErrorCode.forbidden);
      expect(bare.isApiKeyOwnerDisabled, isFalse);
    });

    test('429 → tooManyAttempts, carrying the status', () {
      final mapped = mapDioException(_badResponse(429));
      expect(mapped.code, AppErrorCode.tooManyAttempts);
      expect(mapped.statusCode, 429);
    });

    test('every other 4xx/5xx → badResponse with the status preserved', () {
      // 400 is what login answers when auth got disabled server-side, 502/503
      // is a reverse proxy whose bambuddy is down — all of them must keep the
      // number, since that is the only thing the message can show.
      for (final status in [400, 404, 409, 422, 500, 502, 503, 504]) {
        final mapped = mapDioException(_badResponse(status));
        expect(mapped, isA<ApiException>(), reason: 'status $status');
        expect(mapped.code, AppErrorCode.badResponse, reason: 'status $status');
        expect(mapped.statusCode, status);
      }
    });
  });

  group('mapDioException by transport failure', () {
    test('timeouts and connection loss → serverUnreachable', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.connectionError,
      ]) {
        final mapped = mapDioException(_ofType(type));
        expect(mapped, isA<NetworkException>(), reason: '$type');
        expect(mapped.code, AppErrorCode.serverUnreachable, reason: '$type');
      }
    });

    test('a rejected certificate is its own message, not "unreachable"', () {
      // Self-signed TLS is a common self-hosted setup; the user needs to know
      // it is the certificate rather than the address.
      final mapped = mapDioException(_ofType(DioExceptionType.badCertificate));
      expect(mapped, isA<NetworkException>());
      expect(mapped.code, AppErrorCode.badCertificate);
    });

    test('cancel and unknown → connectionError', () {
      for (final type in [DioExceptionType.cancel, DioExceptionType.unknown]) {
        expect(mapDioException(_ofType(type)).code, AppErrorCode.connectionError,
            reason: '$type');
      }
    });
  });

  group('mapDioException passthrough', () {
    test('an AppApiException already inside the DioException survives', () {
      // How AuthService reports invalid credentials from inside an interceptor:
      // the classified error must not be re-derived from the status.
      const original = AuthException(AppErrorCode.invalidCredentials);
      final wrapped = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.badResponse,
        error: original,
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 500,
        ),
      );
      expect(mapDioException(wrapped), same(original));
    });

    test('toString carries the status and detail for the log', () {
      const e = ApiException(AppErrorCode.badResponse,
          statusCode: 502, detail: 'bad gateway');
      expect(e.toString(), contains('502'));
      expect(e.toString(), contains('bad gateway'));
    });
  });

  group('guard', () {
    test('passes the value through', () async {
      expect(await guard(() async => 42), 42);
    });

    test('maps a DioException and leaves other errors alone', () async {
      await expectLater(
        guard<int>(() async => throw _badResponse(429)),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', AppErrorCode.tooManyAttempts)),
      );
      await expectLater(
        guard<int>(() async => throw StateError('not a Dio error')),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('guardKeepingDetail', () {
    test('passes the value through', () async {
      expect(await guardKeepingDetail(() async => 42), 42);
    });

    test('a 400 arrives with the rule the server named', () async {
      // The difference from `guard`, and the whole reason this exists: the
      // plain mapper drops a 400's detail, so a screen could say no more than
      // "server returned error 400" about a refusal that explained itself.
      await expectLater(
        guardKeepingDetail<int>(() async => throw _badResponseWithDetail(
            400, "Cannot cancel item with status 'printing'")),
        throwsA(isA<ApiException>().having((e) => e.detail, 'detail',
            "Cannot cancel item with status 'printing'")),
      );
      expect(
        (await _thrownBy(() => guard<int>(() async =>
            throw _badResponseWithDetail(400, 'the rule it broke')))).detail,
        isNull,
        reason: 'plain guard is what drops it',
      );
    });

    test('422 keeps its detail too, since validation says which field',
        () async {
      await expectLater(
        guardKeepingDetail<int>(() async => throw _badResponseWithDetail(
            422, 'filament_used_grams must be between 0 and 100000')),
        throwsA(isA<ApiException>()
            .having((e) => e.detail, 'detail', contains('100000'))),
      );
    });

    test('every other status maps exactly as guard does', () async {
      // It only *adds* 400/422 to the plain mapper, so a permission refusal
      // must still arrive as an AuthException with its own detail.
      final forbidden = await _thrownBy(() =>
          guardKeepingDetail<int>(() async => throw _badResponseWithDetail(
              403, "API key does not have 'can_queue' permission")));
      expect(forbidden, isA<AuthException>());
      expect(forbidden.detail, contains('can_queue'));

      await expectLater(
        guardKeepingDetail<int>(() async => throw _badResponse(429)),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', AppErrorCode.tooManyAttempts)),
      );
    });

    test('an error that is not from Dio is left alone', () async {
      await expectLater(
        guardKeepingDetail<int>(() async => throw StateError('parse blew up')),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('guardOrNull', () {
    test('auth failures still throw so the UI can redirect', () async {
      for (final status in [401, 403]) {
        await expectLater(
          guardOrNull<int>(() async => throw _badResponse(status)),
          throwsA(isA<AuthException>()),
          reason: 'status $status',
        );
      }
    });

    test('everything else degrades to null so one dead resource is survivable',
        () async {
      // The dashboard composes many single-entity fetches; a 500 on one printer
      // must not empty the whole screen.
      for (final status in [429, 500, 502, 503]) {
        expect(await guardOrNull<int>(() async => throw _badResponse(status)),
            isNull, reason: 'status $status');
      }
      expect(
        await guardOrNull<int>(
            () async => throw _ofType(DioExceptionType.connectionError)),
        isNull,
      );
      expect(
        await guardOrNull<int>(() async => throw StateError('parse blew up')),
        isNull,
      );
    });
  });

  group('the call the failure came from', () {
    // `action_failed` carries these so a reader is not left matching it against
    // the `http` lane by eye, which is guesswork with two requests in flight.
    test('every mapped failure names its method and path', () {
      final cases = <String, AppApiException>{
        '401': mapDioException(_badResponse(401)),
        '403': mapDioException(_badResponse(403)),
        '429': mapDioException(_badResponse(429)),
        '500': mapDioException(_badResponse(500)),
        'offline': mapDioException(_ofType(DioExceptionType.connectionError)),
        'timeout': mapDioException(_ofType(DioExceptionType.receiveTimeout)),
        'tls': mapDioException(_ofType(DioExceptionType.badCertificate)),
      };
      cases.forEach((name, mapped) {
        expect(mapped.method, 'GET', reason: name);
        expect(mapped.path, isNotEmpty, reason: name);
      });
    });

    test('the path is the sanitised one, without host or query', () {
      // Same reduction `HttpProbe` applies: the host is the user's private
      // network and camera tokens live in the query string.
      final options = RequestOptions(
        path: '/api/v1/printers/1/camera',
        baseUrl: 'http://192.168.1.50:8080',
        queryParameters: const {'token': 'secret'},
      );
      final mapped = mapDioException(DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: 500,
        ),
      ));

      expect(mapped.path, '/api/v1/printers/1/camera');
      expect(mapped.path, isNot(contains('192.168')));
      expect(mapped.path, isNot(contains('secret')));
    });

    test('keeping a 422 detail keeps the call with it', () {
      final options = RequestOptions(path: '/api/v1/inventory/spools');
      final mapped = mapDioExceptionKeepingDetail(DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: 422,
          data: const {'detail': 'rgba must be RRGGBBAA'},
        ),
      ));

      expect(mapped.detail, 'rgba must be RRGGBBAA');
      expect(mapped.path, '/api/v1/inventory/spools');
    });
  });
}

/// The exception [send] threw, for the assertions that inspect more of it than
/// one `throwsA` matcher reads well.
Future<AppApiException> _thrownBy(Future<void> Function() send) async {
  try {
    await send();
  } on AppApiException catch (e) {
    return e;
  }
  fail('expected the call to throw');
}
