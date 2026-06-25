import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/cloud_auth.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';

/// Ekran konta chmury Bambu (logowanie) — w „ustawieniach" aplikacji (szuflada),
/// celowo osobny od ekranu MakerWorld. Logowanie tu jest warunkiem pobierania
/// modeli z MakerWorld; ekran importu kieruje tutaj, gdy brak tokenu.
class CloudAccountScreen extends ConsumerWidget {
  const CloudAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(cloudAuthStatusProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.cloudAccountTitle)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const _LoginForm(),
        data: (status) => status.isAuthenticated
            ? _SignedIn(status: status)
            : const _LoginForm(),
      ),
    );
  }
}

/// Widok zalogowany: e-mail/region + wyloguj.
class _SignedIn extends ConsumerStatefulWidget {
  const _SignedIn({required this.status});

  final CloudAuthStatus status;

  @override
  ConsumerState<_SignedIn> createState() => _SignedInState();
}

class _SignedInState extends ConsumerState<_SignedIn> {
  bool _busy = false;

  Future<void> _signOut() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(cloudRepositoryProvider).logout();
      ref.invalidate(cloudAuthStatusProvider);
      ref.invalidate(makerworldStatusProvider);
    } on AppApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.localized(l10n))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = widget.status;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.cloud_done),
            title: Text(status.email ?? l10n.cloudSignedIn),
            subtitle: status.region == null ? null : Text(_regionLabel(l10n)),
          ),
        ),
        const SizedBox(height: 16),
        Text(l10n.cloudCredsNote,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 24),
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _signOut,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.logout),
          label: Text(l10n.cloudSignOut),
        ),
      ],
    );
  }

  String _regionLabel(AppLocalizations l10n) =>
      widget.status.region == 'china' ? l10n.cloudRegionChina : l10n.cloudRegionGlobal;
}

/// Formularz logowania: e-mail/hasło/region, a po `needs_verification` — kod 2FA.
class _LoginForm extends ConsumerStatefulWidget {
  const _LoginForm();

  @override
  ConsumerState<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends ConsumerState<_LoginForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();

  String _region = 'global';
  bool _busy = false;
  bool _obscure = true;

  /// Trwa etap weryfikacji 2FA (po `needs_verification`).
  bool _verifying = false;
  String? _tfaKey;
  String _verificationPrompt = '';

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  AppLocalizations get _l10n => AppLocalizations.of(context);

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _signIn() async {
    FocusScope.of(context).unfocus();
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      _snack(_l10n.cloudFillCredentials);
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await ref.read(cloudRepositoryProvider).login(
            email: email,
            password: password,
            region: _region,
          );
      _handleResult(res);
    } on AppApiException catch (e) {
      _snack(e.localized(_l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    final code = _code.text.trim();
    if (code.isEmpty) {
      _snack(_l10n.cloudEnterCode);
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await ref.read(cloudRepositoryProvider).verify(
            email: _email.text.trim(),
            code: code,
            tfaKey: _tfaKey,
            region: _region,
          );
      _handleResult(res);
    } on AppApiException catch (e) {
      _snack(e.localized(_l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _handleResult(CloudLoginResult res) {
    if (!mounted) return;
    if (res.needsVerification) {
      setState(() {
        _verifying = true;
        _tfaKey = res.tfaKey;
        _verificationPrompt = res.message;
      });
      return;
    }
    if (res.success) {
      ref.invalidate(cloudAuthStatusProvider);
      ref.invalidate(makerworldStatusProvider);
      _snack(_l10n.cloudSignedInOk);
      if (context.canPop()) context.pop();
      return;
    }
    // Brak sukcesu i brak weryfikacji → komunikat z serwera (lub ogólny).
    _snack(res.message.isNotEmpty ? res.message : _l10n.cloudSignInFailed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.cloudCredsNote,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 20),
        TextField(
          controller: _email,
          enabled: !_verifying && !_busy,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: l10n.cloudEmail,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _password,
          enabled: !_verifying && !_busy,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: l10n.cloudPassword,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'global', label: Text(l10n.cloudRegionGlobal)),
            ButtonSegment(value: 'china', label: Text(l10n.cloudRegionChina)),
          ],
          selected: {_region},
          onSelectionChanged: (_verifying || _busy)
              ? null
              : (sel) => setState(() => _region = sel.first),
        ),
        if (_verifying) ...[
          const SizedBox(height: 20),
          Text(
            _verificationPrompt.isNotEmpty
                ? _verificationPrompt
                : l10n.cloudVerificationPrompt,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.cloudVerificationCode,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.pin_outlined),
            ),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _busy ? null : (_verifying ? _verify : _signIn),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_verifying ? l10n.cloudVerify : l10n.cloudSignIn),
        ),
      ],
    );
  }
}
