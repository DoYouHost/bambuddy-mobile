import 'package:bambuddy_mobile/core/api/action_outcome.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/l10n/server_refusal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ladder three features used to each build for themselves: a known
/// refusal is localized, an unknown one is quoted, and one the server did not
/// explain falls back to the error code.
void main() {
  late AppLocalizations en;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  final rules = <RefusalRule>[
    (['last admin', 'delete'], (l) => l.usersErrLastAdminDelete),
    (['last admin'], (l) => l.usersErrLastAdmin),
    (['your own account'], (l) => l.usersErrSelfDelete),
  ];

  AppApiException refusal(String? detail, {int status = 400}) => ApiException(
    status == 403 ? AppErrorCode.forbidden : AppErrorCode.badResponse,
    statusCode: status,
    detail: detail,
  );

  test('a known refusal is localized', () {
    expect(
      serverRefusal(en, refusal('Cannot delete the last admin user'), rules),
      en.usersErrLastAdminDelete,
    );
  });

  test('every needle has to appear, so a rule cannot half-match', () {
    // "last admin" + "delete" is a different rule from "last admin" alone, and
    // a deactivation must not be reported as a deletion.
    expect(
      serverRefusal(en, refusal('Cannot deactivate the last admin'), rules),
      en.usersErrLastAdmin,
    );
  });

  test('the first matching rule wins, so order is the specificity', () {
    // Both rows match this one; the more specific is listed first.
    expect(
      serverRefusal(en, refusal('Cannot delete the last admin user'), rules),
      isNot(en.usersErrLastAdmin),
    );
  });

  test('matching ignores case, since only the server picks the wording', () {
    expect(
      serverRefusal(en, refusal('YOU CANNOT DELETE YOUR OWN ACCOUNT'), rules),
      en.usersErrSelfDelete,
    );
  });

  test('a refusal no rule knows is quoted, never swallowed', () {
    // A phrasing we have not seen still beats "server returned error 400".
    expect(
      serverRefusal(en, refusal('Budget reservation is locked'), rules),
      'Budget reservation is locked',
    );
  });

  test('a refusal the server did not explain falls back to the code', () {
    expect(serverRefusal(en, refusal(null), rules), en.errBadResponse(400));
    expect(serverRefusal(en, refusal('   '), rules), en.errBadResponse(400));
  });

  test('a 403 keeps the frame the code builds, not the bare detail', () {
    // Not a rule violation, and quoting it raw drops the "Not allowed:" frame
    // — and with it the deactivated-owner case `AppApiExceptionL10n` handles.
    const said = "API key does not have 'can_queue' permission";
    expect(
      serverRefusal(en, refusal(said, status: 403), rules),
      en.errForbiddenDetail(said),
    );
  });

  test('a lost connection is translated, never quoted from Dio', () {
    // The regression this guards: `NetworkException` carries Dio's own message
    // in `detail`, so quoting any non-null detail put untranslated English in
    // front of anyone whose Wi-Fi dropped mid-write.
    for (final code in [
      AppErrorCode.serverUnreachable,
      AppErrorCode.connectionError,
    ]) {
      final message = serverRefusal(
        en,
        NetworkException(code, detail: 'Connecting timed out [10000ms]'),
        rules,
      );
      expect(message, isNot(contains('10000ms')), reason: '$code');
      expect(
        message,
        code == AppErrorCode.serverUnreachable
            ? en.errServerUnreachable
            : en.errConnection,
      );
    }
  });

  test('a 429 keeps its own wording rather than the server\'s', () {
    expect(
      serverRefusal(
        en,
        const ApiException(
          AppErrorCode.tooManyAttempts,
          statusCode: 429,
          detail: 'Too many failed attempts',
        ),
        rules,
      ),
      en.errTooManyAttempts,
    );
  });

  group('outcomeRefusal', () {
    test('a success says nothing', () {
      expect(outcomeRefusal(en, ActionOutcome.ok, rules), isNull);
    });

    test('a failure reads as the refusal it carries', () {
      expect(
        outcomeRefusal(en, ActionOutcome.failed(refusal('last admin')), rules),
        en.usersErrLastAdmin,
      );
    });
  });
}
