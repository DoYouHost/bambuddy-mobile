import 'dart:convert';
import 'dart:typed_data';

import 'package:bambuddy_mobile/core/api/api_client.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/edge_access.dart';
import 'package:bambuddy_mobile/core/api/edge_access_probe.dart';
import 'package:bambuddy_mobile/core/api/tls_overrides.dart';
import 'package:bambuddy_mobile/core/auth/auth_service.dart';
import 'package:bambuddy_mobile/core/auth/credentials_store.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// What Cloudflare Access does to a request it does not accept (#72): a redirect
// to the team domain, which the client follows to a 200 page of HTML. The
// adapter below plays the end of that: the page, and the redirect it came by.

final _token = ServiceToken(
  host: 'printers.example.com',
  clientId: 'abc.access',
  clientSecret: 's3cret',
);

const _login = 'https://team.cloudflareaccess.com/cdn-cgi/access/login/x';

/// Answers every request with [status], having been sent on through [hops] (the
/// hosts it was redirected to, in order), and with [location] as its `Location`
/// header when it is a 3xx handed over unfollowed. The default is Access's login
/// page: a 200 reached by a 302 to the team domain. A policy that denies the
/// visitor is Access's own 403.
class _Answer implements HttpClientAdapter {
  _Answer({
    this.status = 200,
    this.hops = const [_login],
    this.location,
    this.alsoLocation,
  });

  final int status;
  final List<String> hops;
  final String? location;

  /// A second `Location` header, for a response that says where to go twice.
  final String? alsoLocation;

  /// Requests answered so far.
  var calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody.fromString(
        '<html>Sign in</html>',
        status,
        headers: {
          Headers.contentTypeHeader: ['text/html'],
          if (location != null) 'location': [location!, ?alsoLocation],
        },
      )
      ..redirects = [
        for (final hop in hops) RedirectRecord(302, 'GET', Uri.parse(hop)),
      ];
  }

  @override
  void close({bool force = false}) {}
}

/// Answers as bambuddy would, for the case that must not change.
class _Bambuddy implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode({'auth_enabled': true, 'requires_setup': false}),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}

/// Counts what the interceptors in front of the probe are told.
class _Counting extends Interceptor {
  var responses = 0;
  var errors = 0;

  @override
  void onResponse(Response<dynamic> r, ResponseInterceptorHandler h) {
    responses++;
    h.next(r);
  }

  @override
  void onError(DioException e, ErrorInterceptorHandler h) {
    errors++;
    h.next(e);
  }
}

Dio _dio(HttpClientAdapter adapter) =>
    createBareDio()..httpClientAdapter = adapter;

void main() {
  tearDown(() => useTls(null, null));

  group('isCloudflareSignIn', () {
    test('is the team domain and nothing that only contains it', () {
      bool is_(String url) => isCloudflareSignIn(Uri.parse(url));
      expect(is_(_login), isTrue);
      expect(is_('https://TEAM.CloudflareAccess.com/'), isTrue);
      expect(is_('https://a.b.cloudflareaccess.com/'), isTrue);
      expect(is_('https://printers.example.com/'), isFalse);
      expect(is_('https://cloudflareaccess.com.evil.net/'), isFalse);
      expect(is_('https://notcloudflareaccess.com/'), isFalse);
      expect(is_('https://example.com/cloudflareaccess.com'), isFalse);
    });
  });

  group('a request that ends on the sign-in page', () {
    Future<AppApiException> failure(Dio dio) async {
      try {
        await dio.get<Object?>('https://printers.example.com/api/v1/x');
      } on DioException catch (e) {
        return mapDioException(e);
      }
      fail('the sign-in page was let through as an answer');
    }

    test('needs a credential when the app presents none', () async {
      final error = await failure(_dio(_Answer()));
      expect(error.code, AppErrorCode.edgeAccessRequired);
      expect(error.method, 'GET');
    });

    test('was refused one when the app presents it', () async {
      useTls(null, null, _token);
      final error = await failure(_dio(_Answer()));
      expect(error.code, AppErrorCode.edgeAccessRejected);
    });

    test('is not an answer from the server, so carries no response', () async {
      try {
        await _dio(_Answer()).get<Object?>('https://printers.example.com/');
        fail('let through');
      } on DioException catch (e) {
        expect(e.response, isNull);
      }
    });

    test('is the same error when the page is a 401, 403 or 5xx', () async {
      for (final status in [401, 403, 500]) {
        final error = await failure(_dio(_Answer(status: status)));
        expect(error.code, AppErrorCode.edgeAccessRequired, reason: '$status');
      }
    });

    test('does not start a re-login against bambuddy on a 401', () async {
      var relogins = 0;
      final dio = _dio(_Answer(status: 401));
      dio.interceptors.add(
        AuthInterceptor(
          authMode: AuthMode.jwt,
          credentials: InMemoryCredentialsStore()..jwt = 'old',
          retryDio: dio,
          refreshAuth: () async {
            relogins++;
            return 'new';
          },
        ),
      );
      await failure(dio);
      expect(relogins, 0);
    });

    test('is "needs" for a host the credential is not for', () async {
      useTls(null, null, _token);
      try {
        await _dio(_Answer()).get<Object?>('https://other.example.com/x');
        fail('let through');
      } on DioException catch (e) {
        expect(
          (e.error! as AppApiException).code,
          AppErrorCode.edgeAccessRequired,
        );
      }
    });

    test('reaches the setup probe as that error, after one request', () async {
      final page = _Answer();
      final auth = AuthService(
        bareDio: _dio(page),
        credentials: InMemoryCredentialsStore(),
      );
      await expectLater(
        auth.probeAuthStatus('https://printers.example.com'),
        throwsA(
          isA<AppApiException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.edgeAccessRequired,
          ),
        ),
      );
      // The version check does not swallow it and ask again.
      expect(page.calls, 1);
    });
  });

  group('what is not a sign-in', () {
    Future<Response<Object?>> get(Dio dio, String url) => dio.get<Object?>(url);

    test('a request made to the team domain itself', () async {
      // A user who pastes the Zero Trust App Launcher as the server address
      // gets `notBambuddy`, not a request for a credential.
      final res = await get(
        _dio(_Answer(hops: [])),
        'https://team.cloudflareaccess.com/',
      );
      expect(res.statusCode, 200);
    });

    test('a request to the team domain that was upgraded to https', () async {
      final res = await get(
        _dio(_Answer(hops: ['https://team.cloudflareaccess.com/'])),
        'http://team.cloudflareaccess.com/',
      );
      expect(res.statusCode, 200);
    });

    test('a request to the team domain that went on to the provider', () async {
      // The App Launcher sends a visitor to the identity provider: that is the
      // page the user asked for, not the server asking for a credential.
      final res = await get(
        _dio(_Answer(hops: [_login, 'https://idp.example.net/auth'])),
        'https://team.cloudflareaccess.com/',
      );
      expect(res.statusCode, 200);
    });

    test(
      'an alias that redirected to the canonical host before Access',
      () async {
        // example.com -> printers.example.com -> Access -> printers.example.com:
        // the host that sent it to the team domain answered.
        final res = await get(
          _dio(
            _Answer(
              hops: [
                'https://printers.example.com/api/v1/x',
                _login,
                'https://printers.example.com/api/v1/x',
              ],
            ),
          ),
          'https://example.com/api/v1/x',
        );
        expect(res.statusCode, 200);
      },
    );

    test('a round trip that began with a relative redirect', () async {
      // The host that sent it to the team domain is only known by resolving
      // the relative hop against the request.
      final res = await get(
        _dio(_Answer(hops: ['/b', _login, 'https://printers.example.com/x'])),
        'https://printers.example.com/a',
      );
      expect(res.statusCode, 200);
    });

    test('a 302 with two Location headers does not say where to go', () async {
      final res =
          await _dio(
            _Answer(
              status: 302,
              hops: [],
              location: _login,
              alsoLocation: '/x',
            ),
          ).get<Object?>(
            'https://printers.example.com/api/v1/x',
            options: Options(validateStatus: (_) => true),
          );
      expect(res.statusCode, 302);
    });

    test(
      'a round trip through the team domain that ended on the server',
      () async {
        final res = await get(
          _dio(
            _Answer(hops: [_login, 'https://printers.example.com/api/v1/x']),
          ),
          'https://printers.example.com/api/v1/x',
        );
        expect(res.statusCode, 200);
      },
    );

    test('a redirect inside the server\'s own host', () async {
      final res = await get(
        _dio(_Answer(hops: ['https://printers.example.com/api/v1/x/'])),
        'https://printers.example.com/api/v1/x',
      );
      expect(res.statusCode, 200);
    });
  });

  group('what is, by another road', () {
    Future<AppErrorCode> codeOf(Dio dio) async {
      try {
        await dio.get<Object?>('https://printers.example.com/api/v1/x');
      } on DioException catch (e) {
        return mapDioException(e).code;
      }
      fail('let through');
    }

    test('through a relative redirect first', () async {
      // /a -> (relative) /b -> team domain: the journey is resolved hop by hop.
      final code = await codeOf(_dio(_Answer(hops: ['/b', _login])));
      expect(code, AppErrorCode.edgeAccessRequired);
    });

    test(
      'carries the host Cloudflare is in front of, not the one typed',
      () async {
        // example.com -> www.example.com -> Access: the credential belongs to www.
        Object? error;
        try {
          await _dio(
            _Answer(hops: ['https://www.example.com/api/v1/x', _login]),
          ).get<Object?>('https://example.com/api/v1/x');
        } on DioException catch (e) {
          error = e.error;
        }
        expect(error, isA<EdgeAccessException>());
        expect((error! as EdgeAccessException).host, 'www.example.com');
      },
    );

    test(
      'and the host that sent it there when the request started on it',
      () async {
        Object? error;
        try {
          await _dio(_Answer()).get<Object?>('https://Printers.Example.com/x');
        } on DioException catch (e) {
          error = e.error;
        }
        expect((error! as EdgeAccessException).host, 'printers.example.com');
      },
    );

    test(
      'is a refusal when the credential is for that canonical host',
      () async {
        useTls(
          null,
          null,
          ServiceToken(
            host: 'www.example.com',
            clientId: 'a',
            clientSecret: 'b',
          ),
        );
        final code = await codeOf(
          _dio(_Answer(hops: ['https://www.example.com/x', _login])),
        );
        expect(code, AppErrorCode.edgeAccessRejected);
      },
    );

    test(
      'needs one when the hop that went to Cloudflare was plain http',
      () async {
        // The credential is never sent over http, so a refusal is not a refusal.
        useTls(null, null, _token);
        Object? error;
        try {
          await _dio(_Answer()).get<Object?>('http://printers.example.com/x');
        } on DioException catch (e) {
          error = e.error;
        }
        expect(
          (error! as EdgeAccessException).code,
          AppErrorCode.edgeAccessRequired,
        );
      },
    );

    test('on through the team domain to the identity provider', () async {
      // One identity provider, and Access sends the visitor straight on.
      final code = await codeOf(
        _dio(_Answer(hops: [_login, 'https://idp.example.net/auth'])),
      );
      expect(code, AppErrorCode.edgeAccessRequired);
    });

    test(
      'a 302 handed over unfollowed, as a request with a credential gets it',
      () async {
        final code = await codeOf(
          _dio(_Answer(status: 302, hops: [], location: _login)),
        );
        expect(code, AppErrorCode.edgeAccessRequired);
      },
    );

    test('and it is a refusal when the app presented the credential', () async {
      useTls(null, null, _token);
      final code = await codeOf(
        _dio(_Answer(status: 302, hops: [], location: _login)),
      );
      expect(code, AppErrorCode.edgeAccessRejected);
    });

    test('a 302 to another page of the server is not one', () async {
      final res =
          await _dio(
            _Answer(status: 302, hops: [], location: '/api/v1/x/'),
          ).get<Object?>(
            'https://printers.example.com/api/v1/x',
            options: Options(validateStatus: (_) => true),
          );
      expect(res.statusCode, 302);
    });

    test('and one with a Location that is not a URI is left alone', () async {
      final res =
          await _dio(
            _Answer(status: 302, hops: [], location: 'http://[::1'),
          ).get<Object?>(
            'https://printers.example.com/api/v1/x',
            options: Options(validateStatus: (_) => true),
          );
      expect(res.statusCode, 302);
    });
  });

  test(
    'the probes before it see the exchange once, as the answer it was',
    () async {
      final seen = _Counting();
      final dio = _dio(_Answer())..interceptors.insert(0, seen);
      await expectLater(
        dio.get<Object?>('https://printers.example.com/api/v1/x'),
        throwsA(isA<DioException>()),
      );
      expect((seen.responses, seen.errors), (1, 0));
    },
  );

  test('an answer from bambuddy itself is untouched', () async {
    useTls(null, null, _token);
    final res = await _dio(
      _Bambuddy(),
    ).get<Object?>('https://printers.example.com/api/v1/auth/status');
    expect(res.statusCode, 200);
  });

  test('what an isolate presents is what useTls was given', () {
    expect(presentedEdgeAccess(), isNull);
    useTls(null, null, _token);
    expect(presentedEdgeAccess(), _token);
    useTls(null, null);
    expect(presentedEdgeAccess(), isNull);
  });
}
