import 'dart:typed_data';

import 'package:bambuddy_mobile/core/api/action_failure.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/auth/two_factor.dart';
import 'package:bambuddy_mobile/core/diagnostics/auth_probe.dart';
import 'package:bambuddy_mobile/core/diagnostics/diagnostic_recorder.dart';
import 'package:bambuddy_mobile/core/diagnostics/log_event.dart';
import 'package:bambuddy_mobile/core/diagnostics/session_facts.dart';
import 'package:bambuddy_mobile/core/api/api_client.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The redactor is thoroughly tested on its own in `log_redactor_test.dart`.
/// What was never tested is whether it is actually *reached* — a probe that
/// wrote to the sink directly, or a field name nothing on the denylist matches,
/// would sail past a net that passes every unit test it has.
///
/// So these go through the real `DiagnosticRecorder`, seeded with the secrets a
/// real session carries, and assert on the raw JSONL — the exact bytes that end
/// up attached to a public, permanent GitHub issue.
/// Answers every request with whatever the test hands it, so the interceptor
/// chain runs for real without a socket.
class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.reply);

  final Object Function(RequestOptions options) reply;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final answer = reply(options);
    if (answer is DioException) throw answer;
    return answer as ResponseBody;
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String body, [int status = 200]) => ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// What `sessionSecrets` puts in front of the redactor on a real device.
  const apiKey = 'bb_live_7f3a9c2e8b1d4f6a0c5e';
  const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJl';
  const host = 'bambuddy.morgan-home.lan';

  /// Values no session ever hands over, so only shape can catch them.
  const serial = '03W7AC461800123';
  const email = 'kacper.nowak@gmail.com';
  const ip = '192.168.1.50';

  late DiagnosticRecorder recorder;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    recorder = DiagnosticRecorder(
      settings: SettingsRepository(await SharedPreferences.getInstance()),
      loadFacts: () async => const SessionFacts(
        app: '0.12.1+1201000',
        flavor: 'mobile',
        secrets: {apiKey: '[APIKEY]', jwt: '[JWT]', host: '[HOST]'},
      ),
      resolveDirectory: () async => null,
    );
    addTearDown(recorder.discard);
    await recorder.start();
  });

  /// Everything a leak could hide in, checked against the whole session at once.
  Future<void> expectNothingLeaked(String jsonl) async {
    for (final secret in [apiKey, jwt, host, serial, email, ip]) {
      expect(jsonl, isNot(contains(secret)),
          reason: '$secret reached the uploaded log');
    }
  }

  test('a secret handed to any lane comes back out redacted', () async {
    // One value per lane, each written the way its own probe writes it.
    final store = DiagnosticRecorder.active!;
    store.add(LogSource.app, 'probe', fields: {'note': 'key is $apiKey'});
    store.add(LogSource.ws, 'frame', fields: {'detail': 'from $host'});
    store.add(LogSource.err, 'boom', fields: {'msg': 'auth $jwt failed'});
    store.add(LogSource.ui, 'tap', fields: {'label': 'printer $serial'});
    store.add(LogSource.fgs, 'poll', fields: {'to': 'http://$ip:8080/api'});
    store.add(LogSource.notif, 'sent', fields: {'who': email});

    await expectNothingLeaked(await recorder.stop());
  });

  test('a field named like a secret is blanked whatever it holds', () async {
    // The denylist works on the *name*, so a value the shape passes cannot
    // survive by looking innocent.
    final store = DiagnosticRecorder.active!;
    store.add(LogSource.app, 'probe', fields: {
      'password': 'hunter2',
      'access_code': '12345678',
      'authorization': 'Bearer abc',
      'username': 'kacper',
      'headers': {'X-API-Key': apiKey},
    });

    final jsonl = await recorder.stop();
    expect(jsonl, isNot(contains('hunter2')));
    expect(jsonl, isNot(contains('12345678')));
    expect(jsonl, isNot(contains('kacper')));
    await expectNothingLeaked(jsonl);
  });

  test('nesting is not an escape hatch', () async {
    // A probe that logs a structure rather than a scalar must not be a hole:
    // `scrub` recurses through maps and lists at every depth.
    final store = DiagnosticRecorder.active!;
    store.add(LogSource.app, 'probe', fields: {
      'outer': {
        'list': [
          {'deep': 'ping $host'},
          'token=$jwt',
        ],
      },
    });

    await expectNothingLeaked(await recorder.stop());
  });

  group('the http lane, driven through the real interceptor chain', () {
    /// A real Dio so the probe is exercised the way production reaches it,
    /// rather than by calling the interceptor by hand.
    Dio dioAnswering(Object Function(RequestOptions options) reply) =>
        createBareDio()
          ..options.baseUrl = 'http://$host:8080'
          ..httpClientAdapter = _ScriptedAdapter(reply);

    test('a rejected login keeps neither what it sent nor where it went',
        () async {
      final dio = dioAnswering(
        (_) => _json('{"detail":"Incorrect username or password"}', 401),
      );

      await expectLater(
        dio.post<dynamic>(
          '/api/v1/auth/login',
          data: {'username': 'kacper', 'password': 'hunter2'},
          options: Options(headers: {'X-API-Key': apiKey}),
        ),
        throwsA(isA<DioException>()),
      );

      final jsonl = await recorder.stop();
      expect(jsonl, isNot(contains('hunter2')));
      expect(jsonl, isNot(contains('X-API-Key')));
      // The status is the diagnosis and survives.
      expect(jsonl, contains('401'));
      await expectNothingLeaked(jsonl);
    });

    test('a camera token in the query never reaches the record', () async {
      // `?token=` is how the camera and thumbnail routes authenticate, and a
      // path is recorded for every single request.
      final dio = dioAnswering((_) => _json('{}', 200));

      await dio.get<dynamic>(
        '/api/v1/printers/1/camera',
        queryParameters: const {'token': 'cam_7f3a9c2e8b1d4f6a'},
      );

      final jsonl = await recorder.stop();
      expect(jsonl, isNot(contains('cam_7f3a9c2e8b1d4f6a')));
      await expectNothingLeaked(jsonl);
    });

    test('a serial the server echoes back is masked inside the sample',
        () async {
      // Sampled bodies go through the inverted rule, with the serial pattern
      // applied on top of it.
      final dio = dioAnswering(
        (_) => _json('[{"id":1,"serial":"$serial","model":"X1C"}]'),
      );

      await dio.get<dynamic>('/api/v1/printers/');

      await expectNothingLeaked(await recorder.stop());
    });

    test('an unreachable host is masked even in the socket message', () async {
      // "Failed host lookup: 'x.lan'" is a socket message, not a URL, so it
      // only stays out of a public issue because the host is a known secret.
      final dio = dioAnswering(
        (options) => DioException.connectionError(
          requestOptions: options,
          reason: "Failed host lookup: '$host'",
        ),
      );

      await expectLater(
        dio.get<dynamic>('/api/v1/printers/'),
        throwsA(isA<DioException>()),
      );

      final jsonl = await recorder.stop();
      // The shape of the failure is the whole diagnosis and must survive it.
      expect(jsonl, contains('Failed host lookup'));
      await expectNothingLeaked(jsonl);
    });
  });

  test('a filename in the route reaches neither lane', () async {
    // `/projects/{id}/attachments/{filename}` is the one route that puts the
    // user's own text in a path, and a path is recorded for every request. It
    // used to arrive verbatim in both the http lane and the action record.
    const filename = 'faktura-jan-kowalski-2026.pdf';
    final dio = createBareDio()
      ..options.baseUrl = 'http://$host:8080'
      ..httpClientAdapter = _ScriptedAdapter((_) => _json('{}', 403));

    await expectLater(
      dio.delete<dynamic>('/api/v1/projects/3/attachments/$filename'),
      throwsA(isA<DioException>()),
    );
    // The screen's half of the same failure.
    recordActionFailure(
      mapDioException(DioException(
        requestOptions: RequestOptions(
          path: '/api/v1/projects/3/attachments/$filename',
          method: 'DELETE',
          baseUrl: 'http://$host:8080',
        ),
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: ''),
          statusCode: 403,
        ),
      )),
      action: 'project.attachment_delete',
    );

    final jsonl = await recorder.stop();
    expect(jsonl, isNot(contains('kowalski')));
    expect(jsonl, isNot(contains('.pdf')));
    // Which route it was still has to survive, or the masking cost the
    // diagnosis it was protecting.
    expect(jsonl, contains('/api/v1/projects/3/attachments/<seg>'));
    await expectNothingLeaked(jsonl);
  });

  test('an exception built by hand cannot smuggle a path past the record',
      () async {
    // `path` is an ordinary field, so a guarantee that rests on every
    // construction site going through `mapDioException` is not a guarantee.
    // This is the shape that got past the first version of the fix.
    recordActionFailure(
      const AuthException(
        AppErrorCode.forbidden,
        method: 'DELETE',
        path: '/api/v1/projects/3/attachments/faktura-jan-kowalski-2026.pdf',
      ),
      action: 'project.attachment_delete',
    );

    final jsonl = await recorder.stop();
    expect(jsonl, isNot(contains('kowalski')));
    expect(jsonl, contains('/api/v1/projects/3/attachments/<seg>'));
  });

  group('the lanes added with the action funnel', () {
    test('a refusal quoting an address has it masked, and stays readable',
        () async {
      // The server's `detail` is quoted to the user verbatim, so whatever it
      // wrote also lands in the record. It is the one field a 403 needs, and
      // the one that can carry somebody's address.
      recordActionFailure(
        const AuthException(
          AppErrorCode.forbidden,
          detail: "User $email does not have 'printers:control' permission",
          method: 'POST',
          path: '/api/v1/printers/1/print/pause',
        ),
        action: 'printer.pause',
      );

      final jsonl = await recorder.stop();
      expect(jsonl, isNot(contains(email)));
      // Masking the address must not cost the reason it was refused.
      expect(jsonl, contains('printers:control'));
      expect(jsonl, contains('/api/v1/printers/1/print/pause'));
    });

    test('the 2FA lane keeps the pre-auth token and the cookie out', () async {
      // Either one is a live credential for the next five minutes.
      const preAuth = 'pre_auth_9c2e8b1d4f6a0c5e7f3a';
      const cookie = '2fa_challenge=abc123def456; Path=/; HttpOnly';
      AuthProbe.twoFactorRequired(const TwoFactorChallenge(
        preAuthToken: preAuth,
        methods: [TwoFactorMethod.totp, TwoFactorMethod.email],
        challengeCookie: cookie,
      ));
      AuthProbe.twoFactorVerified(
        TwoFactorMethod.totp,
        failure: TwoFactorFailure.code,
        status: 401,
      );

      final jsonl = await recorder.stop();
      expect(jsonl, isNot(contains(preAuth)));
      expect(jsonl, isNot(contains('abc123def456')));
      // What replaced them still separates "the binding arrived" from "a proxy
      // dropped Set-Cookie", which is the pair this lane exists to tell apart.
      expect(jsonl, contains('"binding":true'));
      expect(jsonl, contains('"reason":"code"'));
      await expectNothingLeaked(jsonl);
    });
  });
}
