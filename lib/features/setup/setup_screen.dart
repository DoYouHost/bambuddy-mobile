import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final state = ref.watch(setupControllerProvider);
    final controller = ref.read(setupControllerProvider.notifier);

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.connectToServer),
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
                  ),
                  onSubmitted: (v) => controller.probe(v),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  style: dashPrimaryButtonStyle(t),
                  onPressed:
                      state.busy ? null : () => controller.probe(_url.text),
                  child: Text(l10n.testConnection),
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
        ),
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
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: dashPrimaryButtonStyle(t),
            onPressed: () => controller.connectWithApiKey(_apiKey.text),
            child: Text(l10n.saveAndConnect),
          ),
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
          const SizedBox(height: 12),
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
          ),
          FilledButton(
            style: dashPrimaryButtonStyle(t),
            onPressed: () => controller.connectWithLogin(
              username: _username.text.trim(),
              password: _password.text,
              remember: _remember,
            ),
            child: Text(l10n.signInAndConnect),
          ),
        ],
      ];
}
