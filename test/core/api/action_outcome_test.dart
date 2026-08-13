import 'dart:convert';

import 'package:bambuddy_mobile/core/api/action_failure.dart';
import 'package:bambuddy_mobile/core/api/action_outcome.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/diagnostics/diagnostic_recorder.dart';
import 'package:bambuddy_mobile/core/diagnostics/session_facts.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The one vocabulary every feature now answers actions in.
///
/// Four features used to each own an `enum { ok, forbidden, error }`, catch the
/// exception in a notifier that has no `BuildContext`, and hand the widget a
/// code it translated back into wording of its own. The server's explanation
/// died at that flattening, in all four. What these pin is that it no longer
/// does, and that a failure the user is told about leaves a trace a bug report
/// can be read from.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the shape of an outcome', () {
    test('ok is not a failure and has nothing to report', () {
      expect(ActionOutcome.ok.isOk, isTrue);
      expect(ActionOutcome.ok.isForbidden, isFalse);
    });

    test('a refusal is recognisable without reading its text', () {
      // The screens that hide a control rather than complain — smart plugs,
      // AMS drying — branch on this, so it stays a question about the failure
      // and never a string comparison.
      final refused = ActionOutcome.failed(
        const AuthException(AppErrorCode.forbidden, detail: 'nope'),
      );

      expect(refused.isForbidden, isTrue);
      expect(refused.isOk, isFalse);
    });

    test('any other failure is not mistaken for a refusal', () {
      final broken = ActionOutcome.failed(
        const ApiException(AppErrorCode.badResponse, statusCode: 500),
      );

      expect(broken.isForbidden, isFalse);
      expect(broken.isOk, isFalse);
    });

    test('the exception survives intact, which is the whole point', () {
      const original = AuthException(
        AppErrorCode.forbidden,
        detail: "API key does not have 'can_control_printer' permission",
      );

      final outcome = ActionOutcome.failed(original);

      expect(outcome, isA<ActionFailed>());
      expect((outcome as ActionFailed).error, same(original));
    });
  });

  group('what the report shows', () {
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

    Future<List<Map<String, dynamic>>> failures() async {
      final jsonl = await recorder.stop();
      return [
        for (final line in const LineSplitter().convert(jsonl))
          if (jsonDecode(line) case final Map<String, dynamic> row
              when row['evt'] == 'action_failed')
            row,
      ];
    }

    test('a failure the user is told about is recorded with its reason',
        () async {
      // `http` already logs every error response. What it cannot say is which
      // of them stopped somebody — a screen that absorbs a 403 and one that
      // blocks on it look identical there.
      ActionOutcome.failed(
        const AuthException(
          AppErrorCode.forbidden,
          detail: "API key owner does not have 'printers:control' permission",
        ),
        action: 'printer.pause',
      );

      final rows = await failures();
      expect(rows, hasLength(1));
      expect(rows.single['action'], 'printer.pause');
      expect(rows.single['code'], 'forbidden');
      expect(rows.single['reason'], contains('printers:control'));
    });

    test('a success writes nothing', () async {
      expect(ActionOutcome.ok.isOk, isTrue);
      expect(await failures(), isEmpty);
    });

    test('a failure is recorded even where the caller named no action',
        () async {
      // The action tag is a nicety; losing the record because a call site did
      // not pass one would be the same silence this replaced.
      ActionOutcome.failed(
        const ApiException(AppErrorCode.badResponse, statusCode: 500),
      );

      final rows = await failures();
      expect(rows, hasLength(1));
      expect(rows.single['status'], 500);
      expect(rows.single.containsKey('action'), isFalse);
    });

    test('the record names the call, so it stands without the http lane',
        () async {
      // Two requests in flight and the `http` record above this one is a coin
      // toss; the method and path make it unambiguous.
      recordActionFailure(
        const AuthException(
          AppErrorCode.forbidden,
          detail: 'nope',
          method: 'POST',
          path: '/api/v1/queue/12/start',
        ),
        action: 'queue.start',
      );

      final rows = await failures();
      expect(rows.single['method'], 'POST');
      expect(rows.single['path'], '/api/v1/queue/12/start');
    });

    test('a message nobody was there to read is marked as such', () async {
      // The screen was left while the request was in flight. Before this the
      // `if (!mounted) return;` dropped it, and a failed save read as a
      // successful one.
      recordActionFailure(
        const ApiException(AppErrorCode.badResponse, statusCode: 500),
        action: 'spool_form.save',
        shown: false,
      );

      final rows = await failures();
      expect(rows.single['shown'], isFalse);
    });

    test('the ordinary row does not carry a shown flag at all', () async {
      // Written only in the negative, like `http`'s `empty` — the row that
      // reached somebody is the common one and stays short.
      recordActionFailure(
        const ApiException(AppErrorCode.badResponse, statusCode: 500),
        action: 'spool_form.save',
      );

      final rows = await failures();
      expect(rows.single.containsKey('shown'), isFalse);
    });
  });
}
