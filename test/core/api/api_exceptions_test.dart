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
}
