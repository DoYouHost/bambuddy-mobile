import 'dart:convert';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/diagnostics/diagnostic_recorder.dart';
import 'package:bambuddy_mobile/core/diagnostics/session_facts.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/features/common/api_failure_snack.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// The screen half of the funnel.
///
/// Most of our error handling never builds an `ActionOutcome` — a widget holds a
/// context, so it words the failure where it catches it. The recording used to
/// ride inside the outcome's constructor, so all of that reached the user and
/// none of the log.
void main() {
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

  Future<List<Map<String, dynamic>>> failures() async {
    final jsonl = await recorder.stop();
    return [
      for (final line in const LineSplitter().convert(jsonl))
        if (jsonDecode(line) case final Map<String, dynamic> row
            when row['evt'] == 'action_failed')
          row,
    ];
  }

  /// Pumps a screen and hands back its messenger and `l10n`, the two things
  /// every call site captures before the request it is about to make.
  Future<({ScaffoldMessengerState messenger, AppLocalizations l10n})> harness(
    WidgetTester tester,
  ) async {
    late ScaffoldMessengerState messenger;
    late AppLocalizations l10n;
    await tester.pumpWidget(
      plApp(
        Builder(
          builder: (context) {
            messenger = ScaffoldMessenger.of(context);
            l10n = AppLocalizations.of(context);
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    );
    return (messenger: messenger, l10n: l10n);
  }

  testWidgets('the user reads the server\'s own reason, and it is recorded', (
    tester,
  ) async {
    final h = await harness(tester);

    showApiFailure(
      h.messenger,
      const AuthException(
        AppErrorCode.forbidden,
        detail: "API key does not have 'can_control_printer' permission",
        method: 'POST',
        path: '/api/v1/printers/1/print/pause',
      ),
      h.l10n,
      action: 'printer.pause',
    );
    await tester.pump();

    expect(find.textContaining('can_control_printer'), findsOneWidget);

    final rows = await failures();
    expect(rows, hasLength(1));
    expect(rows.single['action'], 'printer.pause');
    expect(rows.single['path'], '/api/v1/printers/1/print/pause');
    expect(rows.single.containsKey('shown'), isFalse);
  });

  testWidgets('a feature may word one status better and still be recorded', (
    tester,
  ) async {
    final h = await harness(tester);

    showApiFailure(
      h.messenger,
      const ApiException(AppErrorCode.badResponse, statusCode: 409),
      h.l10n,
      action: 'tag_manage.rename',
      message: 'A tag with that name exists',
    );
    await tester.pump();

    expect(find.text('A tag with that name exists'), findsOneWidget);

    final rows = await failures();
    expect(rows.single['action'], 'tag_manage.rename');
    expect(rows.single['status'], 409);
  });

  testWidgets(
    'a screen left mid-request records the failure and shows nothing',
    (tester) async {
      final h = await harness(tester);

      // Null messenger is the call site saying "there is nobody to tell". The
      // failure still happened, and without the record it is indistinguishable
      // from a save that worked.
      showApiFailure(
        null,
        const ApiException(AppErrorCode.badResponse, statusCode: 500),
        h.l10n,
        action: 'spool_form.save',
      );
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);

      final rows = await failures();
      expect(rows, hasLength(1));
      expect(rows.single['action'], 'spool_form.save');
      expect(rows.single['shown'], isFalse);
    },
  );
}
