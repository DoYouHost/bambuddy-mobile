import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/two_factor.dart';
import '../../core/demo/demo_config.dart';
import '../../core/settings/server_profile.dart';
import '../../core/watch/watch_config_sync.dart';
import '../../core/watch/wear_text_input.dart';
import '../../features/setup/providers.dart';
import '../../features/setup/setup_error_text.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../wear_action.dart';
import '../wear_providers.dart';
import '../wear_theme.dart';
import '../widgets/wear_scroll_view.dart';
import '../widgets/wear_spinner.dart';

/// Compact, watch-sized server setup. Reuses the phone app's [setupControllerProvider]
/// verbatim (probe → auth), just with a vertically-scrollable, round-safe layout.
///
/// Typing is the fallback, not the plan: the screen leads with the phone→watch
/// handoff, because a wrist is a bad place to enter a URL and a worse one to
/// enter a password. When someone does type, the text comes from the watch's own
/// input activity — a Flutter `TextField` has no working keyboard on Wear OS
/// (see [WearTextInput]).
class WearSetupScreen extends ConsumerStatefulWidget {
  const WearSetupScreen({super.key});

  @override
  ConsumerState<WearSetupScreen> createState() => _WearSetupScreenState();
}

class _WearSetupScreenState extends ConsumerState<WearSetupScreen>
    with WearAction {
  final _url = TextEditingController();
  final _apiKey = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _wearInput = WearTextInput();

  bool _useLogin = false;

  /// Typing was chosen over the handoff. Sticky for the rest of the flow: the
  /// auth step is part of the same manual path.
  bool _manual = false;

  /// The last check found nothing latched — worth saying out loud, or the button
  /// looks broken.
  bool _phoneEmpty = false;

  /// The last check failed outright, as opposed to coming back empty.
  Object? _phoneError;

  /// Whether fields hand off to the watch input activity. Settled before the
  /// fields are reachable, since they live behind "enter manually".
  bool _viaWatchInput = false;

  @override
  void initState() {
    super.initState();
    _resolveInputPath();
  }

  Future<void> _resolveInputPath() async {
    final supported = await _wearInput.isSupported();
    if (mounted && supported) setState(() => _viaWatchInput = true);
  }

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

    final offer = ref.watch(pendingWatchConfigProvider);
    return Scaffold(
      body: SafeArea(
        child: WearScrollView(
          // Every branch below is a step of its own; naming it here is what
          // brings the scroll back to the top when the screen swaps.
          resetKey: _manual ? 'manual' : (offer != null ? 'offer' : 'handoff'),
          children: [
            const Center(
              child: Text('Bambuddy', style: WearText.title),
            ),
            const SizedBox(height: 12),
            if (offer case final offer? when !_manual)
              ..._offerSection(l10n, offer)
            else if (!_manual)
              ..._phoneHandoffSection(l10n)
            else
              ..._manualSection(controller, l10n, state),
          ],
        ),
      ),
    );
  }

  /// What the phone sent, shown before it is used rather than after.
  ///
  /// The push carries credentials for a server the watch has never talked to, so
  /// it is worth a look: a phone that switched servers used to reconfigure the
  /// watch silently, and nothing on the watch said which server it was on.
  List<Widget> _offerSection(AppLocalizations l10n, WatchConfig offer) => [
        Text(
          l10n.wearFromPhone,
          textAlign: TextAlign.center,
          style: WearText.body,
        ),
        const SizedBox(height: 4),
        Text(
          offer.profile.displayName,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: WearText.section,
        ),
        const SizedBox(height: 2),
        Text(
          switch (offer.profile.authMode) {
            AuthMode.apiKey => l10n.wearAuthKey,
            AuthMode.jwt => l10n.wearAuthLogin,
            AuthMode.none => l10n.wearAuthNone,
          },
          textAlign: TextAlign.center,
          style: WearText.fine,
        ),
        if (_phoneError != null) ...[
          const SizedBox(height: 6),
          Text(
            _errorText(l10n, _phoneError!),
            textAlign: TextAlign.center,
            style: _errorStyle(context),
          ),
        ],
        const SizedBox(height: 10),
        if (busy)
          wearSpinner
        else
          FilledButton(
            onPressed: () => _useOffer(offer),
            child: Text(l10n.wearFromPhoneUse),
          ),
        TextButton(
          onPressed: () =>
              ref.read(pendingWatchConfigProvider.notifier).dismiss(),
          child: Text(l10n.wearFromPhoneLater),
        ),
      ];

  /// Adopt the offered config. The failure has to stay on screen: it is what
  /// stands between the user and a working watch, so a message that times out
  /// would be no message at all.
  Future<void> _useOffer(WatchConfig offer) {
    setState(() => _phoneError = null);
    return run(
      () => ref.read(pendingWatchConfigProvider.notifier).adopt(offer),
      onError: (error) => setState(() => _phoneError = error),
    );
  }

  /// The path almost everybody should take: the phone already knows the server
  /// and the credentials, and pushes both over the Data Layer.
  List<Widget> _phoneHandoffSection(AppLocalizations l10n) => [
        Text(
          l10n.wearSetupPhoneTitle,
          textAlign: TextAlign.center,
          style: WearText.section,
        ),
        const SizedBox(height: 6),
        Text(
          l10n.wearSetupPhoneBody,
          textAlign: TextAlign.center,
          style: WearText.small,
        ),
        if (_phoneEmpty || _phoneError != null) ...[
          const SizedBox(height: 6),
          Text(
            switch (_phoneError) {
              final error? => _errorText(l10n, error),
              null => l10n.wearSetupPhoneEmpty,
            },
            textAlign: TextAlign.center,
            style: _errorStyle(context),
          ),
        ],
        const SizedBox(height: 10),
        if (busy)
          wearSpinner
        else
          FilledButton(
            onPressed: _checkPhone,
            child: Text(l10n.wearSetupPhoneCheck),
          ),
        TextButton(
          onPressed: () => setState(() => _manual = true),
          child: Text(l10n.wearSetupManual),
        ),
        TextButton(
          onPressed: busy ? null : _startDemo,
          child: Text(l10n.wearSetupDemo),
        ),
      ];

  /// Straight into demo mode, without a keyboard anywhere near it.
  ///
  /// Runs the shared controller rather than writing a profile here: demo is
  /// entered exactly one way in both apps, and the watch only skips the typing
  /// the phone still asks a reviewer for. The address and credentials are
  /// constants and the backend is in-process, so there is no network step to
  /// fail — the error check is for the day the shared flow changes under us.
  Future<void> _startDemo() => run(() async {
        final controller = ref.read(setupControllerProvider.notifier);
        await controller.probe(DemoConfig.baseUrl);
        await controller.connectWithLogin(
          username: DemoConfig.username,
          password: DemoConfig.password,
          remember: true,
        );
        if (!mounted) return;
        final error = ref.read(setupControllerProvider).error;
        if (error != null) setState(() => _phoneError = error);
      });

  /// Look for what the phone last latched and *offer* it. A live push is picked
  /// up by `WearApp` on its own; this button is for the config that arrived
  /// while the watch app was closed, and for the user who wants to see
  /// something happen.
  Future<void> _checkPhone() {
    setState(() {
      _phoneEmpty = false;
      _phoneError = null;
    });
    return run(
      () async {
        // Bounded on purpose: the Data Layer call never answers at all where
        // Google Play services are missing, and the run guard covers a throw,
        // not a call that simply never returns. Coming back empty at least
        // leaves the manual path reachable.
        final found = await ref
            .read(watchConfigSyncProvider)
            .latestPending()
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
        if (!mounted) return;
        // Empty is an outcome, not a failure — hence a field of its own rather
        // than an error.
        setState(() => _phoneEmpty = found == null);
        if (found != null) {
          ref.read(pendingWatchConfigProvider.notifier).offer(found);
        }
      },
      onError: (error) => setState(() => _phoneError = error),
    );
  }

  List<Widget> _manualSection(
    SetupController controller,
    AppLocalizations l10n,
    SetupState state,
  ) =>
      [
        _compactField(_url, l10n.wearServerUrl,
            keyboard: TextInputType.url, enabled: !state.busy),
        const SizedBox(height: 8),
        if (state.busy)
          wearSpinner
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
              style: _errorStyle(context),
            ),
          ),
        if (state.twoFactor case final challenge?)
          ..._twoFactorSection(controller, l10n, challenge, state)
        else if (state.needsAuth && !state.busy)
          ..._authSection(controller, l10n)
        else if (!state.busy)
          // Only offered before the server answers: once we are past the probe,
          // dropping back to the handoff would throw that progress away.
          TextButton(
            onPressed: () => setState(() => _manual = false),
            child: Text(l10n.wearSetupPhoneTitle),
          ),
      ];

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
        style: WearText.section,
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
        child: Text(l10n.twoFactorBack),
      ),
    ];
  }

  Widget _compactField(
    TextEditingController controller,
    String label, {
    TextInputType? keyboard,
    bool obscure = false,
    bool enabled = true,
  }) {
    final l10n = AppLocalizations.of(context);
    final decoration = InputDecoration(
      labelText: label,
      isDense: true,
      border: const OutlineInputBorder(),
    );
    if (!_viaWatchInput) {
      return TextField(
        controller: controller,
        enabled: enabled,
        obscureText: obscure,
        keyboardType: keyboard,
        autocorrect: false,
        style: WearText.value,
        decoration: decoration,
      );
    }
    return TextField(
      controller: controller,
      enabled: enabled,
      // The value is edited elsewhere, so nothing here may take focus — a focused
      // field on the watch is exactly what asks for the keyboard that never comes.
      readOnly: true,
      canRequestFocus: false,
      obscureText: obscure,
      style: WearText.value,
      onTap: enabled ? () => _editOnWatch(controller, label) : null,
      decoration: decoration.copyWith(
        suffixIcon: const Icon(Icons.keyboard_alt_outlined, size: 16),
        // Drops away once the field has a value, so the hint teaches the gesture
        // without permanently eating a line on a 450 px screen.
        helperText: controller.text.isEmpty ? l10n.wearSetupTapToType : null,
      ),
    );
  }

  Future<void> _editOnWatch(
      TextEditingController controller, String label) async {
    try {
      final text = await _wearInput.request(label: label);
      if (text != null && mounted) setState(() => controller.text = text);
    } on WearTextInputUnavailable {
      // Nothing to hand the request to. An editable field is a poor answer on a
      // watch, but a dead tap is no answer at all.
      if (mounted) setState(() => _viaWatchInput = false);
    }
  }
}

/// Every failure on this screen is a line of small red text under the button
/// that caused it — the setup flow has no other place to put one.
TextStyle _errorStyle(BuildContext context) =>
    WearText.small.copyWith(color: Theme.of(context).colorScheme.error);

/// Localized via the shared setup mapper; anything unexpected stays short.
String _errorText(AppLocalizations l10n, Object error) {
  final s = setupErrorText(l10n, error);
  return s.length > 80 ? '${s.substring(0, 80)}…' : s;
}
