import 'dart:convert';

import 'package:bambuddy_mobile/core/auth/two_factor.dart';
import 'package:bambuddy_mobile/core/diagnostics/auth_probe.dart';
import 'package:bambuddy_mobile/core/diagnostics/diagnostic_recorder.dart';
import 'package:bambuddy_mobile/core/diagnostics/session_facts.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the 2FA records are worth once the redactor has been over them.
///
/// The point of `two_factor_required` is telling "the binding cookie arrived"
/// from "it did not" — the difference between a user's wrong code and a reverse
/// proxy eating `Set-Cookie`, and the second one is invisible everywhere else.
/// A record that reads the same in both cases costs a diagnosis, and the
/// redactor blanks by *field name*, so the naming is the behaviour here, not a
/// detail.
void main() {
  // The recorder attaches the interaction probe on start, which needs a
  // binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late DiagnosticRecorder recorder;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    recorder = DiagnosticRecorder(
      settings: SettingsRepository(await SharedPreferences.getInstance()),
      loadFacts: () async =>
          const SessionFacts(app: '0.12.1+1201000', flavor: 'mobile'),
      resolveDirectory: () async => null,
    );
    addTearDown(recorder.discard);
    await recorder.start();
  });

  /// Only what this probe wrote — the session snapshot the recorder always
  /// opens with is not what any of these tests is about.
  Future<List<Map<String, dynamic>>> records() async {
    final jsonl = await recorder.stop();
    return [
      for (final line in const LineSplitter().convert(jsonl))
        if (jsonDecode(line) case final Map<String, dynamic> row
            when '${row['evt']}'.startsWith('two_factor'))
          row,
    ];
  }

  TwoFactorChallenge challenge({String? cookie}) => TwoFactorChallenge(
    preAuthToken: 'pre-auth-xyz',
    methods: const [TwoFactorMethod.totp, TwoFactorMethod.backup],
    challengeCookie: cookie,
  );

  test('the binding survives the redactor as a readable yes or no', () async {
    // Regression: the field was called `cookie`, which is on the redactor's
    // secret-name list, so a live recording carried `"cookie":"[REDACTED]"` —
    // the same text whether the binding came through or not.
    AuthProbe.twoFactorRequired(challenge(cookie: 'wiazanie-123'));
    AuthProbe.twoFactorRequired(challenge());

    expect((await records()).map((r) => r['binding']), [true, false]);
  });

  test('neither the cookie nor the pre-auth token is in the record', () async {
    AuthProbe.twoFactorRequired(challenge(cookie: 'wiazanie-123'));

    final line = jsonEncode(await records());
    expect(line, isNot(contains('wiazanie-123')));
    expect(line, isNot(contains('pre-auth-xyz')));
  });

  test(
    'the offered methods are named, since they shape the whole step',
    () async {
      AuthProbe.twoFactorRequired(challenge(cookie: 'x'));

      expect((await records()).single['methods'], ['totp', 'backup']);
    },
  );

  test('a verification says which factor and how it failed', () async {
    AuthProbe.twoFactorVerified(TwoFactorMethod.totp);
    AuthProbe.twoFactorVerified(
      TwoFactorMethod.backup,
      failure: TwoFactorFailure.code,
      status: 401,
    );

    expect(
      (await records()).map(
        (r) => [r['evt'], r['method'], r['ok'], r['reason']],
      ),
      [
        ['two_factor_verify', 'totp', true, null],
        ['two_factor_verify', 'backup', false, 'code'],
      ],
    );
  });

  test(
    'a lapsed challenge is its own record, not a failed verification',
    () async {
      // Nothing went out, so calling it a rejection would put a request in the
      // log that never happened.
      AuthProbe.twoFactorLapsed();

      expect((await records()).single['evt'], 'two_factor_lapsed');
    },
  );
}
