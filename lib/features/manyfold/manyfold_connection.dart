import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/manyfold.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/api_failure_snack.dart';
import 'manyfold_providers.dart';
import 'manyfold_widgets.dart';

/// The stored connection, without the secret.
final manyfoldConfigProvider = FutureProvider.autoDispose<ManyfoldConfig>(
  (ref) => ref.watch(manyfoldRepositoryProvider).config(),
);

/// URL, client ID and secret of the Manyfold OAuth application — the web's
/// `ManyfoldConnectionCard`, for whoever holds `settings:update`.
class ManyfoldConnectionCard extends ConsumerStatefulWidget {
  const ManyfoldConnectionCard({super.key, this.onDone});

  /// Back to browsing; `null` while there is nothing to go back to.
  final VoidCallback? onDone;

  @override
  ConsumerState<ManyfoldConnectionCard> createState() =>
      _ManyfoldConnectionCardState();
}

class _ManyfoldConnectionCardState
    extends ConsumerState<ManyfoldConnectionCard> {
  final _url = TextEditingController();
  final _clientId = TextEditingController();
  final _secret = TextEditingController();
  bool _seeded = false;

  /// The last test's answer, until a field changes.
  ({bool ok, String text})? _testResult;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_url, _clientId, _secret]) {
      c.addListener(_edited);
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _clientId.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _edited() {
    if (_testResult != null) setState(() => _testResult = null);
    setState(() {});
  }

  bool _complete(ManyfoldConfig? config) =>
      _url.text.trim().isNotEmpty &&
      _clientId.text.trim().isNotEmpty &&
      (_secret.text.trim().isNotEmpty || (config?.hasClientSecret ?? false));

  void _refresh() {
    ref
      ..invalidate(manyfoldConfigProvider)
      ..invalidate(manyfoldStatusProvider)
      ..invalidate(manyfoldModelsProvider)
      ..invalidate(manyfoldModelProvider)
      ..invalidate(manyfoldPreviewProvider);
  }

  Future<void> _test() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final count = await ref
          .read(manyfoldRepositoryProvider)
          .testConfig(
            url: _url.text,
            clientId: _clientId.text,
            clientSecret: _secret.text,
          );
      if (mounted) {
        setState(() => _testResult = (ok: true, text: l10n.mfTestOk(count)));
      }
    } on Object catch (e) {
      if (e is! ManyfoldFailure && e is! AppApiException) rethrow;
      if (e case ManyfoldFailure(:final cause) || final AppApiException cause) {
        recordActionFailure(cause, action: 'manyfold.test', shown: mounted);
      }
      if (mounted) {
        setState(
          () => _testResult = (ok: false, text: manyfoldErrorText(e, l10n)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(manyfoldRepositoryProvider)
          .saveConfig(
            url: _url.text,
            clientId: _clientId.text,
            clientSecret: _secret.text,
          );
      _secret.clear();
      messenger.snack(l10n.mfSaved);
      if (!mounted) return;
      _refresh();
      widget.onDone?.call();
    } on Object catch (e) {
      if (e is! ManyfoldFailure && e is! AppApiException) rethrow;
      showManyfoldFailure(
        mounted ? messenger : null,
        e,
        l10n,
        action: 'manyfold.save',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final sure = await confirmDialog(
      context,
      id: 'manyfold.disconnect',
      title: l10n.mfDisconnectTitle,
      message: l10n.mfDisconnectBody,
      confirmLabel: l10n.mfDisconnect,
      destructive: true,
    );
    if (!sure || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(manyfoldRepositoryProvider).deleteConfig();
      _url.clear();
      _clientId.clear();
      _secret.clear();
      messenger.snack(l10n.mfDisconnected);
      if (mounted) _refresh();
    } on Object catch (e) {
      if (e is! ManyfoldFailure && e is! AppApiException) rethrow;
      showManyfoldFailure(
        mounted ? messenger : null,
        e,
        l10n,
        action: 'manyfold.disconnect.confirm',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final config = ref.watch(manyfoldConfigProvider).valueOrNull;
    if (config != null && !_seeded) {
      _seeded = true;
      _url.text = config.url;
      _clientId.text = config.clientId;
    }
    final complete = _complete(config);
    final result = _testResult;
    final onDone = widget.onDone;

    return Container(
      padding: const EdgeInsets.all(DashSpace.lg),
      decoration: t.cardBox,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.mfConnectionTitle, style: t.titleSm),
          const SizedBox(height: DashSpace.sm),
          Text(l10n.mfConnectionHelp, style: t.bodySoft),
          const SizedBox(height: DashSpace.lg),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            style: t.bodyStrong,
            decoration: dashFieldDecoration(
              t,
              labelText: l10n.mfUrl,
              hintText: l10n.mfUrlPlaceholder,
            ),
          ).tagged('manyfold.url'),
          const SizedBox(height: DashSpace.md),
          TextField(
            controller: _clientId,
            autocorrect: false,
            style: t.bodyStrong,
            decoration: dashFieldDecoration(t, labelText: l10n.mfClientId),
          ).tagged('manyfold.client_id'),
          const SizedBox(height: DashSpace.md),
          TextField(
            controller: _secret,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            style: t.bodyStrong,
            decoration: dashFieldDecoration(
              t,
              labelText: l10n.mfClientSecret,
              helperText: config?.hasClientSecret ?? false
                  ? l10n.mfClientSecretStored
                  : null,
            ),
          ).tagged('manyfold.client_secret'),
          if (result != null) ...[
            const SizedBox(height: DashSpace.md),
            Text(
              result.text,
              style: t.body.copyWith(
                color: result.ok ? t.accentGreenInk : t.dangerInk,
              ),
            ),
          ],
          const SizedBox(height: DashSpace.lg),
          ButtonPair(
            primaryLabel: l10n.mfSave,
            secondaryLabel: l10n.mfTest,
            primary: FilledButton.icon(
              onPressed: _busy || !complete ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(l10n.mfSave),
            ).tagged('manyfold.save'),
            secondary: OutlinedButton.icon(
              onPressed: _busy || !complete ? null : _test,
              icon: const Icon(Icons.wifi_tethering),
              label: Text(l10n.mfTest),
            ).tagged('manyfold.test'),
          ),
          if (config?.configured ?? false) ...[
            const SizedBox(height: DashSpace.sm),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: t.dangerInk),
              onPressed: _busy ? null : _disconnect,
              icon: const Icon(Icons.link_off),
              label: Text(l10n.mfDisconnect),
            ).tagged('manyfold.disconnect'),
          ],
          if (onDone != null)
            TextButton(
              onPressed: _busy ? null : onDone,
              child: Text(l10n.cancel),
            ).tagged('manyfold.connection_cancel'),
        ],
      ),
    );
  }
}
