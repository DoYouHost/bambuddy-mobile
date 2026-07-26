import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/demo/demo_config.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../bug_report/recording_banner.dart';
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
  bool _remember = false;
  bool _useLogin = false;

  @override
  void dispose() {
    _url.dispose();
    _apiKey.dispose();
    _username.dispose();
    _password.dispose();
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
                    style: TextStyle(
                      fontFamily: DashTokens.fontUi,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: t.textPrimary,
                    ),
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
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (state.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      setupErrorText(l10n, state.error!),
                      style: TextStyle(
                        fontFamily: DashTokens.fontUi,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.danger,
                      ),
                    ),
                  ),
                if (state.needsAuth && !state.busy)
                  ..._authSection(t, l10n, controller),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _authSection(
          DashTokens t, AppLocalizations l10n, SetupController controller) =>
      [
        const SizedBox(height: 24),
        Text(
          l10n.serverRequiresAuth,
          style: TextStyle(
            fontFamily: DashTokens.fontUi,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
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
            style: TextStyle(
              fontFamily: DashTokens.fontUi,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          logTag(
            'setup.api_key',
            TextField(
              controller: _apiKey,
              autocorrect: false,
              style: TextStyle(
                fontFamily: DashTokens.fontMono,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: t.textPrimary,
              ),
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
            style: TextStyle(
              fontFamily: DashTokens.fontUi,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          logTag(
            'setup.username',
            TextField(
              controller: _username,
              autocorrect: false,
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: t.textPrimary,
              ),
              decoration: dashFieldDecoration(t, labelText: l10n.usernameLabel),
            ),
          ),
          const SizedBox(height: 12),
          logTag(
            'setup.password',
            TextField(
              controller: _password,
              obscureText: true,
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: t.textPrimary,
              ),
              decoration: dashFieldDecoration(t, labelText: l10n.passwordLabel),
            ),
          ),
          CheckboxListTile(
            value: _remember,
            onChanged: (v) => setState(() => _remember = v ?? false),
            title: Text(
              l10n.rememberMe,
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: t.textPrimary,
              ),
            ),
            subtitle: Text(
              l10n.rememberMeSubtitle,
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 12,
                color: t.textSecondary,
              ),
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
