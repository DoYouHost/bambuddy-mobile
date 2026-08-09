import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/diagnostics/log_tag.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/models/cloud_auth.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/error_messages.dart';
import '../../providers.dart';

/// Bambu Cloud account screen (login) — in app "settings" (drawer), intentionally
/// separate from MakerWorld screen. Login here is prerequisite for importing models
/// from MakerWorld; import screen directs here if no token.
class CloudAccountScreen extends ConsumerWidget {
  const CloudAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(cloudAuthStatusProvider);
    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.cloudAccountTitle),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const _LoginForm(),
          data: (status) => status.isAuthenticated
              ? _SignedIn(status: status)
              : const _LoginForm(),
        ),
      ),
    );
  }
}

/// Signed-in view: email/region + logout.
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
    final t = DashTokens.of(context);
    final status = widget.status;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: t.cardGradient,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: t.cardBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: t.accentGreen.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.cloud_done, color: t.accentGreenInk),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      status.email ?? l10n.cloudSignedIn,
                      style: TextStyle(
                        fontFamily: DashTokens.fontUi,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                    if (status.region != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        _regionLabel(l10n),
                        style: TextStyle(
                          fontFamily: DashTokens.fontUi,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: t.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          l10n.cloudCredsNote,
          style: TextStyle(
            fontFamily: DashTokens.fontUi,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: t.textTertiary,
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: t.textPrimary,
            side: BorderSide(color: t.cardBorder),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: _busy ? null : _signOut,
          icon: _busy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: t.textPrimary),
                )
              : const Icon(Icons.logout),
          label: Text(l10n.cloudSignOut),
        ).tagged('cloud.sign_out'),
      ],
    );
  }

  String _regionLabel(AppLocalizations l10n) =>
      widget.status.region == 'china' ? l10n.cloudRegionChina : l10n.cloudRegionGlobal;
}

/// Login form: email/password/region, then on `needs_verification` — 2FA code.
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

  /// Currently in 2FA verification stage (after `needs_verification`).
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
      if (!mounted) return;
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
      if (!mounted) return;
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
    // No success and no verification → server message (or generic).
    _snack(res.message.isNotEmpty ? res.message : _l10n.cloudSignInFailed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    final t = DashTokens.of(context);
    TextStyle fieldStyle() => TextStyle(
          fontFamily: DashTokens.fontUi,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: t.textPrimary,
        );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: t.cardGradient,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: t.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.cloudCredsNote,
                style: TextStyle(
                  fontFamily: DashTokens.fontUi,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: t.textTertiary,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _email,
                enabled: !_verifying && !_busy,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                style: fieldStyle(),
                decoration: dashFieldDecoration(
                  t,
                  labelText: l10n.cloudEmail,
                ).copyWith(prefixIcon: const Icon(Icons.email_outlined)),
              ).tagged('cloud.email'),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                enabled: !_verifying && !_busy,
                obscureText: _obscure,
                style: fieldStyle(),
                decoration: dashFieldDecoration(
                  t,
                  labelText: l10n.cloudPassword,
                ).copyWith(
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                        color: t.textTertiary),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ).tagged('cloud.reveal_password'),
                ),
              ).tagged('cloud.password'),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                      value: 'global', label: Text(l10n.cloudRegionGlobal)),
                  ButtonSegment(
                      value: 'china', label: Text(l10n.cloudRegionChina)),
                ],
                selected: {_region},
                onSelectionChanged: (_verifying || _busy)
                    ? null
                    : (sel) => setState(() => _region = sel.first),
              ).tagged('cloud.region'),
              if (_verifying) ...[
                const SizedBox(height: 20),
                Text(
                  _verificationPrompt.isNotEmpty
                      ? _verificationPrompt
                      : l10n.cloudVerificationPrompt,
                  style: TextStyle(
                    fontFamily: DashTokens.fontUi,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: t.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _code,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  style: fieldStyle(),
                  decoration: dashFieldDecoration(
                    t,
                    labelText: l10n.cloudVerificationCode,
                  ).copyWith(prefixIcon: const Icon(Icons.pin_outlined)),
                ).tagged('cloud.code'),
              ],
              const SizedBox(height: 24),
              FilledButton(
                style: dashPrimaryButtonStyle(t),
                onPressed: _busy ? null : (_verifying ? _verify : _signIn),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFF0A0C08)),
                      )
                    : Text(_verifying ? l10n.cloudVerify : l10n.cloudSignIn),
              ).tagged('cloud.sign_in'),
            ],
          ),
        ),
      ],
    );
  }
}
