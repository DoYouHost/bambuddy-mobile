import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/setup/providers.dart';

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
    final state = ref.watch(setupControllerProvider);
    final controller = ref.read(setupControllerProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          children: [
            const Center(
              child: Text('BambuBuddy',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 12),
            _compactField(_url, 'Server URL',
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
                child: const Text('Connect'),
              ),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _errorText(state.error!),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error, fontSize: 12),
                ),
              ),
            if (state.needsAuth && !state.busy) ..._authSection(controller),
          ],
        ),
      ),
    );
  }

  List<Widget> _authSection(SetupController controller) => [
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('Key')),
            ButtonSegment(value: true, label: Text('Login')),
          ],
          selected: {_useLogin},
          onSelectionChanged: (s) => setState(() => _useLogin = s.first),
        ),
        const SizedBox(height: 8),
        if (!_useLogin) ...[
          _compactField(_apiKey, 'API key (bb_…)'),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => controller.connectWithApiKey(_apiKey.text),
            child: const Text('Save'),
          ),
        ] else ...[
          _compactField(_username, 'Username'),
          const SizedBox(height: 8),
          _compactField(_password, 'Password', obscure: true),
          const SizedBox(height: 8),
          FilledButton(
            // Watch has no background re-login flow; always remember credentials
            // so an expired JWT recovers silently.
            onPressed: () => controller.connectWithLogin(
              username: _username.text.trim(),
              password: _password.text,
              remember: true,
            ),
            child: const Text('Sign in'),
          ),
        ],
      ];

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

/// Best-effort message; the watch keeps it short. Rich localized mapping stays
/// on the phone app.
String _errorText(Object error) {
  final s = error.toString();
  return s.length > 80 ? '${s.substring(0, 80)}…' : s;
}
