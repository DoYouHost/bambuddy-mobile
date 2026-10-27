import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/auth/two_factor.dart';
import 'package:bambuddy_mobile/features/setup/providers.dart';
import 'package:bambuddy_mobile/features/setup/setup_screen.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets for the first-run setup: the bare
/// address step, its validation and connection errors, the demo shortcut, the
/// authentication choice (API key and login) and the second-factor step in its
/// three method layouts. Steps that need a server's answer run on a fixed
/// [SetupState] rather than a mocked probe: the controller is covered by its own
/// tests, and what is measured here is the card each state draws. Not covered:
/// the QR scanner behind the address field's icon (a live camera preview, which
/// a host test cannot produce) and the busy spinner (an endless animation).
void main() {
  a11ySurface(
    'setup',
    demo: false,
    home: () => const SetupScreen(),
    shows: find.text(pl.testConnection),
  );

  a11ySurface(
    'setup, empty address',
    demo: false,
    home: () => const SetupScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('setup.test_connection'));
      await settle(tester);
    },
    shows: find.text(pl.errMissingUrl),
  );

  a11ySurface(
    'setup, server unreachable',
    demo: false,
    overrides: [
      noServerProfileOverride,
      _fixed(
        const SetupState(
          error: NetworkException(AppErrorCode.serverUnreachable),
        ),
      ),
    ],
    home: () => const SetupScreen(),
    shows: find.text(pl.testConnection),
  );

  // The real controller, the real demo shortcut: fills the sign-in form.
  a11ySurface(
    'setup, demo shortcut',
    demo: false,
    home: () => const SetupScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('setup.demo'));
      await settle(tester);
    },
    shows: find.text(pl.signInAndConnect),
  );

  a11ySurface(
    'setup, API key',
    demo: false,
    overrides: [noServerProfileOverride, _fixed(_authRequired)],
    home: () => const SetupScreen(),
    shows: find.text(pl.saveAndConnect),
  );

  a11ySurface(
    'setup, login',
    demo: false,
    overrides: [noServerProfileOverride, _fixed(_authRequired)],
    home: () => const SetupScreen(),
    arrange: (tester) async {
      await tester.tap(find.text(pl.authModeLogin));
      await settle(tester);
    },
    shows: find.text(pl.signInAndConnect),
  );

  a11ySurface(
    'setup, login, missing credentials',
    demo: false,
    overrides: [
      noServerProfileOverride,
      _fixed(
        SetupState(
          probe: _authRequired.probe,
          baseUrl: _authRequired.baseUrl,
          error: SetupErrorCode.missingCredentials,
        ),
      ),
    ],
    home: () => const SetupScreen(),
    arrange: (tester) async {
      await tester.tap(find.text(pl.authModeLogin));
      await settle(tester);
    },
    shows: find.text(pl.errMissingCredentials),
  );

  a11ySurface(
    'setup, second factor, authenticator app only',
    demo: false,
    overrides: [
      noServerProfileOverride,
      _fixed(_challenge(const [TwoFactorMethod.totp])),
    ],
    home: () => const SetupScreen(),
    shows: find.text(pl.twoFactorVerify),
  );

  // The method picker, the e-mail send button and its "not sent yet" copy.
  a11ySurface(
    'setup, second factor, e-mail',
    demo: false,
    overrides: [
      noServerProfileOverride,
      _fixed(_challenge(TwoFactorMethod.values)),
    ],
    home: () => const SetupScreen(),
    arrange: (tester) async {
      await tester.tap(find.text(pl.twoFactorMethodEmail));
      await settle(tester);
    },
    shows: find.text(pl.twoFactorSendEmail),
  );

  a11ySurface(
    'setup, second factor, e-mail sent',
    demo: false,
    overrides: [
      noServerProfileOverride,
      _fixed(_challenge(TwoFactorMethod.values, emailCodeSent: true)),
    ],
    home: () => const SetupScreen(),
    arrange: (tester) async {
      await tester.tap(find.text(pl.twoFactorMethodEmail));
      await settle(tester);
    },
    shows: find.text(pl.twoFactorResendEmail),
  );

  a11ySurface(
    'setup, second factor, backup code',
    demo: false,
    overrides: [
      noServerProfileOverride,
      _fixed(_challenge(TwoFactorMethod.values)),
    ],
    home: () => const SetupScreen(),
    arrange: (tester) async {
      await tester.tap(find.text(pl.twoFactorMethodBackup));
      await settle(tester);
    },
    shows: find.text(pl.twoFactorExplainBackup),
  );
}

/// What a probe of a server with authentication on leaves behind.
const _authRequired = SetupState(
  probe: (
    authEnabled: true,
    requiresSetup: false,
    baseUrl: 'http://printers.lan:8000',
  ),
  baseUrl: 'http://printers.lan:8000',
);

SetupState _challenge(
  List<TwoFactorMethod> methods, {
  bool emailCodeSent = false,
}) => SetupState(
  probe: _authRequired.probe,
  baseUrl: _authRequired.baseUrl,
  twoFactor: TwoFactorChallenge(preAuthToken: 'pre-auth', methods: methods),
  emailCodeSent: emailCodeSent,
);

/// The controller standing still on [state]: no timer, no request.
Override _fixed(SetupState state) =>
    setupControllerProvider.overrideWith(() => _FixedSetup(state));

class _FixedSetup extends SetupController {
  _FixedSetup(this._state);

  final SetupState _state;

  @override
  SetupState build() => _state;
}
