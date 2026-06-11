import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Konfiguracja połączenia: URL → sonda trybu auth → (opcjonalnie)
/// klucz API albo login+hasło. Klucze API rekomendowane: nie wygasają
/// i mają scope'y, w przeciwieństwie do 24-godzinnego JWT.
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
    final state = ref.watch(setupControllerProvider);
    final controller = ref.read(setupControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Połącz z serwerem')),
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
              decoration: const InputDecoration(
                labelText: 'Adres serwera bambuddy',
                hintText: 'np. 192.168.1.10:8000',
                helperText:
                    'Dostęp zdalny: użyj HTTPS przez reverse proxy',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => controller.probe(v),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed:
                  state.busy ? null : () => controller.probe(_url.text),
              child: const Text('Testuj połączenie'),
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
                  state.error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            if (state.needsAuth && !state.busy) ..._authSection(controller),
          ],
        ),
      ),
    );
  }

  List<Widget> _authSection(SetupController controller) => [
        const SizedBox(height: 24),
        const Text(
          'Serwer wymaga uwierzytelnienia',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('Klucz API (zalecane)'),
            ),
            ButtonSegment(value: true, label: Text('Login i hasło')),
          ],
          selected: {_useLogin},
          onSelectionChanged: (s) => setState(() => _useLogin = s.first),
        ),
        const SizedBox(height: 16),
        if (!_useLogin) ...[
          const Text(
            'Klucz API nie wygasa i ma ograniczone uprawnienia — '
            'utwórz go na serwerze: Settings → API Keys.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKey,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Klucz API',
              hintText: 'bb_…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => controller.connectWithApiKey(_apiKey.text),
            child: const Text('Zapisz i połącz'),
          ),
        ] else ...[
          const Text(
            'Sesja logowania wygasa po 24 h. Zaznacz „Zapamiętaj mnie", '
            'żeby aplikacja logowała się ponownie automatycznie.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _username,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Login lub e-mail',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Hasło',
              border: OutlineInputBorder(),
            ),
          ),
          CheckboxListTile(
            value: _remember,
            onChanged: (v) => setState(() => _remember = v ?? false),
            title: const Text('Zapamiętaj mnie'),
            subtitle: const Text(
              'Hasło trafi do szyfrowanego magazynu (Android Keystore)',
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          FilledButton(
            onPressed: () => controller.connectWithLogin(
              username: _username.text.trim(),
              password: _password.text,
              remember: _remember,
            ),
            child: const Text('Zaloguj i połącz'),
          ),
        ],
      ];
}
