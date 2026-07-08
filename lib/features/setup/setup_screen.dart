import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final state = ref.watch(setupControllerProvider);
    final controller = ref.read(setupControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.connectToServer)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _url,
              enabled: !state.busy,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l10n.serverAddressLabel,
                hintText: l10n.serverAddressHint,
                helperText: l10n.serverAddressHelper,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (v) => controller.probe(v),
            ),
            const SizedBox(height: 12),
            FilledButton(
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
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            if (state.needsAuth && !state.busy)
              ..._authSection(l10n, controller),
          ],
        ),
      ),
    );
  }

  List<Widget> _authSection(
          AppLocalizations l10n, SetupController controller) =>
      [
        const SizedBox(height: 24),
        Text(
          l10n.serverRequiresAuth,
          style: const TextStyle(fontWeight: FontWeight.bold),
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
          Text(l10n.apiKeyExplain),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKey,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l10n.apiKeyLabel,
              hintText: 'bb_…',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => controller.connectWithApiKey(_apiKey.text),
            child: Text(l10n.saveAndConnect),
          ),
        ] else ...[
          Text(l10n.loginExplain),
          const SizedBox(height: 12),
          TextField(
            controller: _username,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l10n.usernameLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(
              labelText: l10n.passwordLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          CheckboxListTile(
            value: _remember,
            onChanged: (v) => setState(() => _remember = v ?? false),
            title: Text(l10n.rememberMe),
            subtitle: Text(l10n.rememberMeSubtitle),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          FilledButton(
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
