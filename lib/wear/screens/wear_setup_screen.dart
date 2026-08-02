import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/two_factor.dart';
import '../../features/setup/providers.dart';
import '../../features/setup/setup_error_text.dart';
import '../../l10n/app_localizations.dart';

/// Compact, watch-sized server setup. Reuses the phone app's [setupControllerProvider]
/// verbatim (probe → auth), just with a vertically-scrollable, round-safe layout.
class WearSetupScreen extends ConsumerStatefulWidget {
  const WearSetupScreen({super.key});

  @override
  ConsumerState<WearSetupScreen> createState() => _WearSetupScreenState();
}

class _WearSetupScreenState extends ConsumerState<WearSetupScreen> {
  final _url = TextEditingController();
  final _apiKey = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _useLogin = false;

  @override
  void dispose() {
    _url.dispose();
    _apiKey.dispose();
    _username.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(setupControllerProvider);
    final controller = ref.read(setupControllerProvider.notifier);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          children: [
            const Center(
              child: Text('Bambuddy',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),
            _compactField(_url, l10n.wearServerUrl,
                keyboard: TextInputType.url, enabled: !state.busy),
            const SizedBox(height: 8),
            if (state.busy)
              const Center(child: Padding(
                padding: EdgeInsets.all(8),
                child: SizedBox(
                    width: 22, height: 22, child: CircularProgressIndicator()),
              ))
            else if (!state.needsAuth)
              FilledButton(
                onPressed: () => controller.probe(_url.text),
                child: Text(l10n.wearConnect),
              ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _errorText(l10n, state.error!),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error, fontSize: 12),
                ),
              ),
            if (state.twoFactor case final challenge?)
              ..._twoFactorSection(controller, l10n, challenge, state)
            else if (state.needsAuth && !state.busy)
              ..._authSection(controller, l10n),
          ],
        ),
      ),
    );
  }

  List<Widget> _authSection(SetupController controller, AppLocalizations l10n) => [
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: false, label: Text(l10n.wearAuthKey)),
            ButtonSegment(value: true, label: Text(l10n.wearAuthLogin)),
          ],
          selected: {_useLogin},
          onSelectionChanged: (s) => setState(() => _useLogin = s.first),
        ),
        const SizedBox(height: 8),
        if (!_useLogin) ...[
          _compactField(_apiKey, '${l10n.apiKeyLabel} (bb_…)'),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => controller.connectWithApiKey(_apiKey.text),
            child: Text(l10n.fmSave),
          ),
        ] else ...[
          _compactField(_username, l10n.wearUsername),
          const SizedBox(height: 8),
          _compactField(_password, l10n.passwordLabel, obscure: true),
          const SizedBox(height: 8),
          FilledButton(
            // Watch has no background re-login flow; always remember credentials
            // so an expired JWT recovers silently.
            onPressed: () => controller.connectWithLogin(
              username: _username.text.trim(),
              password: _password.text,
              remember: true,
            ),
            child: Text(l10n.cloudSignIn),
          ),
        ],
      ];

  /// The code step, watch-sized. Same controller as the phone, so the whole
  /// flow (challenge, e-mail resend, expiry) behaves identically; only the
  /// method picker is dropped — the wrist is no place for a segmented control,
  /// so the watch answers with whatever the server listed first (TOTP where the
  /// account has it) and the phone handles the exotic cases.
  List<Widget> _twoFactorSection(
    SetupController controller,
    AppLocalizations l10n,
    TwoFactorChallenge challenge,
    SetupState state,
  ) {
    final method = challenge.methods.first;
    return [
      const SizedBox(height: 12),
      Text(
        l10n.twoFactorTitle,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      _compactField(_code, l10n.twoFactorCodeLabel,
          keyboard: method.isNumericCode
              ? TextInputType.number
              : TextInputType.visiblePassword,
          enabled: !state.busy),
      const SizedBox(height: 8),
      if (method == TwoFactorMethod.email)
        TextButton(
          onPressed: state.busy ? null : controller.sendTwoFactorEmailCode,
          child: Text(
            state.emailCodeSent
                ? l10n.twoFactorResendEmail
                : l10n.twoFactorSendEmail,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      FilledButton(
        onPressed: state.busy
            ? null
            : () =>
                controller.verifyTwoFactor(method: method, code: _code.text),
        child: Text(l10n.twoFactorVerify),
      ),
      TextButton(
        onPressed: state.busy
            ? null
            : () {
                _code.clear();
                controller.cancelTwoFactor();
              },
        child: Text(l10n.twoFactorBack, style: const TextStyle(fontSize: 12)),
      ),
    ];
  }

  Widget _compactField(
    TextEditingController controller,
    String label, {
    TextInputType? keyboard,
    bool obscure = false,
    bool enabled = true,
  }) =>
      TextField(
        controller: controller,
        enabled: enabled,
        obscureText: obscure,
        keyboardType: keyboard,
        autocorrect: false,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );
}

/// Localized via the shared setup mapper; anything unexpected stays short.
String _errorText(AppLocalizations l10n, Object error) {
  final s = setupErrorText(l10n, error);
  return s.length > 80 ? '${s.substring(0, 80)}…' : s;
}
