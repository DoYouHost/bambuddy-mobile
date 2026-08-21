import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/two_factor.dart';
import '../../core/diagnostics/log_tag.dart';
import '../../core/demo/demo_config.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../bug_report/recording_banner.dart';
import '../common/dash_progress.dart';
import '../common/qr_scanner_screen.dart';
import 'api_key_qr.dart';
import 'providers.dart';
import 'setup_error_text.dart';

/// Connection setup: URL → auth mode probe → (optional) API key or login+password.
/// API keys recommended: no expiry and scopes, unlike 24-hour JWT.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _url = TextEditingController();
  final _apiKey = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _remember = false;
  bool _useLogin = false;

  /// Which second factor the user picked. Null until the challenge arrives —
  /// then it defaults to the server's first offered method.
  TwoFactorMethod? _method;

  @override
  void dispose() {
    _url.dispose();
    _apiKey.dispose();
    _username.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  /// Fill the fields with the demo credentials (store-review mode) and probe
  /// right away — the user only has to tap "Sign in and connect" afterwards.
  void _fillDemo() {
    setState(() {
      _url.text = 'demo';
      _username.text = DemoConfig.username;
      _password.text = DemoConfig.password;
      _useLogin = true;
    });
    ref.read(setupControllerProvider.notifier).probe(_url.text);
  }

  /// Open the QR scanner and apply a scanned bambuddy config code. The code
  /// carries the server URL + API key together, so we fill both and re-probe;
  /// the user just reviews and taps "Save and connect".
  Future<void> _scanApiKey() async {
    final l10n = AppLocalizations.of(context);
    final cfg = await Navigator.of(context).push<ScannedApiKeyConfig>(
      MaterialPageRoute(
        builder: (_) => QrScannerScreen<ScannedApiKeyConfig>(
          title: l10n.scanApiKeyTitle,
          hint: l10n.scanApiKeyHint,
          extract: parseScannedApiKey,
        ),
      ),
    );
    if (cfg == null || !mounted) return;
    setState(() {
      _apiKey.text = cfg.apiKey;
      _useLogin = false; // a scanned config is always an API key
      if (cfg.baseUrl != null) _url.text = cfg.baseUrl!;
    });
    // A combined code carries the URL: probe it so the auth section appears with
    // the key already filled. A key-only code leaves the current URL untouched.
    if (cfg.baseUrl != null) {
      await ref.read(setupControllerProvider.notifier).probe(cfg.baseUrl!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final state = ref.watch(setupControllerProvider);
    final controller = ref.read(setupControllerProvider.notifier);

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(
          context,
          title: l10n.connectToServer,
          // Reachable before there is a server at all — a setup that will not
          // connect is one of the reports worth having.
          actions: [
            logTag(
              'setup.bug_report',
              IconButton(
                onPressed: () => context.push(bugReportRoute),
                tooltip: l10n.bugReportTitle,
                icon: Icon(Icons.bug_report_outlined, color: t.textSecondary),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: t.cardGradient,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: t.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                logTag(
                  'setup.server_url',
                  TextField(
                    controller: _url,
                    enabled: !state.busy,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    style: t.bodyStrong,
                    decoration: dashFieldDecoration(
                      t,
                      labelText: l10n.serverAddressLabel,
                      hintText: l10n.serverAddressHint,
                      helperText: l10n.serverAddressHelper,
                      suffixIcon: IconButton(
                        onPressed: state.busy ? null : _scanApiKey,
                        tooltip: l10n.scanApiKeyTitle,
                        icon:
                            Icon(Icons.qr_code_scanner, color: t.textSecondary),
                      ).tagged('setup.scan_api_key'),
                    ),
                    onSubmitted: (v) => controller.probe(v),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  style: dashPrimaryButtonStyle(t),
                  onPressed:
                      state.busy ? null : () => controller.probe(_url.text),
                  child: Text(l10n.testConnection),
                ).tagged('setup.test_connection'),
                const SizedBox(height: 4),
                Center(
                  child: logTag(
                    'setup.demo',
                    TextButton.icon(
                      onPressed: state.busy ? null : _fillDemo,
                      icon: Icon(
                        Icons.play_circle_outline,
                        size: 18,
                        color: t.textSecondary,
                      ),
                      label: Text(l10n.tryDemo),
                      style: TextButton.styleFrom(
                        foregroundColor: t.textSecondary,
                        textStyle: const TextStyle(
                          fontFamily: DashTokens.fontUi,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                if (state.busy)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: DashLoading(),
                  ),
                if (state.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      setupErrorText(l10n, state.error!),
                      style: t.body.copyWith(color: t.danger),
                    ),
                  ),
                if (state.twoFactor case final challenge?)
                  ..._twoFactorSection(t, l10n, controller, challenge, state)
                else if (state.needsAuth && !state.busy)
                  ..._authSection(t, l10n, controller),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Step two of a login the server answered with `requires_2fa`.
  ///
  /// Replaces the login form rather than appearing under it: the password is
  /// already accepted at this point, and leaving its fields on screen invites
  /// re-submitting them, which mints a second challenge and voids this one.
  List<Widget> _twoFactorSection(
    DashTokens t,
    AppLocalizations l10n,
    SetupController controller,
    TwoFactorChallenge challenge,
    SetupState state,
  ) {
    final method = _method ?? challenge.methods.first;
    return [
      const SizedBox(height: 24),
      Text(
        l10n.twoFactorTitle,
        style: t.titleSm,
      ),
      const SizedBox(height: 8),
      if (challenge.methods.length > 1) ...[
        SegmentedButton<TwoFactorMethod>(
          showSelectedIcon: false,
          segments: [
            for (final m in challenge.methods)
              ButtonSegment(value: m, label: Text(_methodLabel(l10n, m))),
          ],
          selected: {method},
          // Clearing the field on a switch: a 6-digit TOTP left in place while
          // the user moves to backup codes would be submitted as an 8-character
          // one and burn an attempt against the 5-per-15-minutes limit.
          onSelectionChanged: (s) => setState(() {
            _method = s.first;
            _code.clear();
          }),
        ).tagged('setup.two_factor_method'),
        const SizedBox(height: 12),
      ],
      Text(
        _methodExplain(l10n, method, sent: state.emailCodeSent),
        style: t.bodySoft,
      ),
      const SizedBox(height: 12),
      logTag(
        'setup.two_factor_code',
        TextField(
          controller: _code,
          enabled: !state.busy,
          autofocus: true,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: method.codeLength,
          keyboardType: method.isNumericCode
              ? TextInputType.number
              : TextInputType.visiblePassword,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            if (method.isNumericCode)
              FilteringTextInputFormatter.digitsOnly
            else
              FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
          ],
          style: t.monoHeadline.copyWith(letterSpacing: 4),
          decoration: dashFieldDecoration(t, labelText: l10n.twoFactorCodeLabel),
          onSubmitted: (v) =>
              controller.verifyTwoFactor(method: method, code: v),
        ),
      ),
      if (method == TwoFactorMethod.email)
        logTag(
          'setup.two_factor_send_email',
          TextButton.icon(
            onPressed:
                state.busy ? null : controller.sendTwoFactorEmailCode,
            icon: Icon(Icons.mail_outline, size: 18, color: t.textSecondary),
            label: Text(state.emailCodeSent
                ? l10n.twoFactorResendEmail
                : l10n.twoFactorSendEmail),
            style: TextButton.styleFrom(
              foregroundColor: t.textSecondary,
              textStyle: const TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      const SizedBox(height: 4),
      FilledButton(
        style: dashPrimaryButtonStyle(t),
        onPressed: state.busy
            ? null
            : () =>
                controller.verifyTwoFactor(method: method, code: _code.text),
        child: Text(l10n.twoFactorVerify),
      ).tagged('setup.two_factor_verify'),
      const SizedBox(height: 4),
      Center(
        child: logTag(
          'setup.two_factor_cancel',
          TextButton(
            onPressed: state.busy
                ? null
                : () {
                    _code.clear();
                    setState(() => _method = null);
                    controller.cancelTwoFactor();
                  },
            style: TextButton.styleFrom(
              foregroundColor: t.textSecondary,
              textStyle: const TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(l10n.twoFactorBack),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        l10n.twoFactorSessionNote,
        style: t.label,
      ),
    ];
  }

  String _methodLabel(AppLocalizations l10n, TwoFactorMethod method) =>
      switch (method) {
        TwoFactorMethod.totp => l10n.twoFactorMethodTotp,
        TwoFactorMethod.email => l10n.twoFactorMethodEmail,
        TwoFactorMethod.backup => l10n.twoFactorMethodBackup,
      };

  String _methodExplain(
    AppLocalizations l10n,
    TwoFactorMethod method, {
    required bool sent,
  }) =>
      switch (method) {
        TwoFactorMethod.totp => l10n.twoFactorExplainTotp,
        TwoFactorMethod.email =>
          sent ? l10n.twoFactorExplainEmailSent : l10n.twoFactorExplainEmail,
        TwoFactorMethod.backup => l10n.twoFactorExplainBackup,
      };

  List<Widget> _authSection(
          DashTokens t, AppLocalizations l10n, SetupController controller) =>
      [
        const SizedBox(height: 24),
        Text(
          l10n.serverRequiresAuth,
          style: t.titleSm,
        ),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(l10n.authModeApiKey)),
            ButtonSegment(value: true, label: Text(l10n.authModeLogin)),
          ],
          selected: {_useLogin},
          onSelectionChanged: (s) => setState(() => _useLogin = s.first),
        ).tagged('setup.auth_mode'),
        const SizedBox(height: 16),
        if (!_useLogin) ...[
          Text(
            l10n.apiKeyExplain,
            style: t.bodySoft,
          ),
          const SizedBox(height: 12),
          logTag(
            'setup.api_key',
            TextField(
              controller: _apiKey,
              autocorrect: false,
              style: t.monoValue,
              decoration: dashFieldDecoration(
                t,
                labelText: l10n.apiKeyLabel,
                hintText: 'bb_…',
                suffixIcon: IconButton(
                  onPressed: _scanApiKey,
                  tooltip: l10n.scanApiKeyTitle,
                  icon: Icon(Icons.qr_code_scanner, color: t.textSecondary),
                ).tagged('setup.scan_api_key'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: dashPrimaryButtonStyle(t),
            onPressed: () => controller.connectWithApiKey(_apiKey.text),
            child: Text(l10n.saveAndConnect),
          ).tagged('setup.connect_api_key'),
        ] else ...[
          Text(
            l10n.loginExplain,
            style: t.bodySoft,
          ),
          const SizedBox(height: 12),
          logTag(
            'setup.username',
            TextField(
              controller: _username,
              autocorrect: false,
              style: t.bodyStrong,
              decoration: dashFieldDecoration(t, labelText: l10n.usernameLabel),
            ),
          ),
          const SizedBox(height: 12),
          logTag(
            'setup.password',
            TextField(
              controller: _password,
              obscureText: true,
              style: t.bodyStrong,
              decoration: dashFieldDecoration(t, labelText: l10n.passwordLabel),
            ),
          ),
          CheckboxListTile(
            value: _remember,
            onChanged: (v) => setState(() => _remember = v ?? false),
            title: Text(
              l10n.rememberMe,
              style: t.bodyStrong,
            ),
            subtitle: Text(
              l10n.rememberMeSubtitle,
              style: t.labelSoft.copyWith(color: t.textSecondary),
            ),
            activeColor: t.accentGreen,
            checkColor: const Color(0xFF0A0C08),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ).tagged('setup.remember_me'),
          FilledButton(
            style: dashPrimaryButtonStyle(t),
            onPressed: () => controller.connectWithLogin(
              username: _username.text.trim(),
              password: _password.text,
              remember: _remember,
            ),
            child: Text(l10n.signInAndConnect),
          ).tagged('setup.connect_login'),
        ],
      ];
}
