import 'package:bambuddy_mobile/core/api/action_outcome.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/l10n/error_messages.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a refused action actually reads like on screen.
///
/// A 403 is the one error whose code says nothing useful on its own: "not
/// allowed" is true of every one of them, and which permission was missing
/// lives only in what the server wrote. These pin that the reason survives to
/// the user, and that the one refusal with a different remedy — the API key's
/// owner account being gone — is not filed under "check your permissions".
void main() {
  late AppLocalizations pl;
  late AppLocalizations en;

  setUp(() async {
    pl = await AppLocalizations.delegate.load(const Locale('pl'));
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('403', () {
    test('the server reason is quoted inside a localized frame', () {
      const e = AuthException(
        AppErrorCode.forbidden,
        detail: "API key does not have 'can_control_printer' permission",
      );

      expect(e.localized(pl), contains('can_control_printer'));
      expect(e.localized(pl), startsWith('Brak uprawnień'));
      expect(e.localized(en), contains('can_control_printer'));
      expect(e.localized(en), startsWith('Not allowed'));
    });

    test('a login is refused in its own words, not the key\'s', () {
      // The server distinguishes the two auth modes; the message used to claim
      // "your API key" to everyone, including users who have never made one.
      const e = AuthException(
        AppErrorCode.forbidden,
        detail: 'Missing required permissions: printers:control',
      );

      expect(e.localized(pl), contains('printers:control'));
      expect(e.localized(pl), isNot(contains('klucz API')));
    });

    test(
      'with nothing to quote, the fallback blames no credential in particular',
      () {
        const e = AuthException(AppErrorCode.forbidden);

        expect(e.localized(pl), isNot(contains('klucz API')));
        expect(e.localized(en), isNot(contains('API key')));
        expect(e.localized(pl), isNotEmpty);
      },
    );

    test('a deactivated key owner gets the remedy that actually applies', () {
      // "Check the key's permissions" is a dead end here: no scope or group
      // change brings the account back.
      const e = AuthException(
        AppErrorCode.forbidden,
        detail: 'API key owner is deactivated or no longer exists',
      );

      expect(e.localized(pl), contains('Konto właściciela'));
      expect(e.localized(en), contains('deactivated or deleted'));
      // The server's English is replaced here, not framed.
      expect(e.localized(pl), isNot(contains('no longer exists')));
    });
  });

  test('other codes are unaffected by the detail', () {
    const e = AuthException(AppErrorCode.unauthorized, detail: 'anything');
    expect(e.localized(pl), pl.errUnauthorized);
  });

  /// The policy every feature now follows: it decides *whether* to speak, never
  /// *what to say*. `null` is what lets a caller write
  /// `messageFor(l10n) ?? itsOwnConfirmation` — the success wording stays the
  /// feature's, the failure wording never is.
  group('an action outcome', () {
    test(
      'success says nothing, so the caller can fall back to its own line',
      () {
        expect(ActionOutcome.ok.messageFor(pl), isNull);
      },
    );

    test('a failure reads exactly as the shared translator puts it', () {
      const failure = AuthException(
        AppErrorCode.forbidden,
        detail: "API key does not have 'can_control_printer' permission",
      );

      final outcome = ActionOutcome.failed(failure);

      expect(outcome.messageFor(pl), failure.localized(pl));
      expect(outcome.messageFor(pl), contains('can_control_printer'));
    });

    test('a transport failure is explained too, not flattened to "failed"', () {
      // The old per-feature wording said "could not send the command" for an
      // unreachable server, a 500 and a refusal alike.
      final outcome = ActionOutcome.failed(
        const NetworkException(AppErrorCode.serverUnreachable),
      );

      expect(outcome.messageFor(pl), pl.errServerUnreachable);
    });
  });
}
