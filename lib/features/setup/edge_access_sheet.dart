import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/edge_access.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// Sets up, replaces or removes the Cloudflare Access credential of [host]
/// (#72). True when the sheet saved or removed one, so the setup screen knows
/// to ask the server again.
///
/// The host is the one the credential is bound to, taken by the caller: from
/// the error Cloudflare answered the setup probe with, or from the saved
/// credential in settings. Never typed here.
///
/// Whether it saved is read from the write, not from how the sheet closed: a
/// save that finishes as the sheet is being dismissed (a drag closes a bottom
/// sheet past any `PopScope`) still happened, so the write in flight is waited
/// for. And it counts when it changed nothing: the same token typed again is
/// what a person does once the policy on the Cloudflare side is fixed, and the
/// server has to be asked again.
Future<bool> showEdgeAccessSheet(
  BuildContext context, {
  required String host,
  required String area,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  // A second tap in the frame of the first would stack a second sheet. Kept per
  // container, not in a global: a sheet that is torn down with its app never
  // completes, and would block the next one for good.
  if (_open[container] ?? false) return false;
  _open[container] = true;
  try {
    Future<void>? write;
    await dashSheet<void>(
      context,
      builder: (_) => EdgeAccessSheet(
        host: host,
        area: area,
        onWrite: (started) => write = started,
      ),
    );
    try {
      await write;
    } on Object {
      // The sheet reports a failed write itself; it did not save.
      return false;
    }
    return write != null;
  } finally {
    _open[container] = false;
  }
}

final _open = Expando<bool>('edgeAccessSheetOpen');

class EdgeAccessSheet extends ConsumerStatefulWidget {
  const EdgeAccessSheet({
    super.key,
    required this.host,
    required this.area,
    required this.onWrite,
  });

  final String host;

  /// The screen it was opened from, for the log ids: the sheet is the same
  /// everywhere and must not name itself.
  final String area;

  /// Told of the write the sheet starts, so the function that opened it can wait
  /// for it after the sheet is gone.
  final void Function(Future<void> write) onWrite;

  @override
  ConsumerState<EdgeAccessSheet> createState() => _EdgeAccessSheetState();
}

class _EdgeAccessSheetState extends ConsumerState<EdgeAccessSheet> {
  late final TextEditingController _id;
  final _secret = TextEditingController();
  bool _saving = false;

  /// What is saved for this host, shown so it can be replaced or removed.
  late final EdgeAccess? _current;

  @override
  void initState() {
    super.initState();
    final saved = ref.read(edgeAccessProvider);
    _current = saved != null && saved.appliesTo(_https) ? saved : null;
    // The id is not a secret and is what a person recognises it by; the secret
    // is never shown again.
    _id = TextEditingController(
      text: switch (_current) {
        ServiceToken(:final clientId) => clientId,
        _ => '',
      },
    );
  }

  Uri get _https => Uri(scheme: 'https', host: widget.host);

  @override
  void dispose() {
    _id.dispose();
    _secret.dispose();
    super.dispose();
  }

  bool get _ready =>
      !_saving && _id.text.trim().isNotEmpty && _secret.text.trim().isNotEmpty;

  /// A change in the frame of another: both taps reach their handlers before the
  /// buttons are rebuilt disabled, and a second write of a change that failed
  /// would fail the same way and be reported twice.
  Future<void> _change(EdgeAccess? access) async {
    if (_saving) return;
    setState(() => _saving = true);
    await _write(access);
  }

  /// The change goes through [TlsIdentityNotifier], which keeps a failed one from
  /// leaving half a change. A failure that is not the user's to fix is the
  /// app's bug: it is rethrown after the buttons are released, and lands in the
  /// report as an uncaught error.
  ///
  /// Closing the sheet is its own step, after and outside that: a sheet that was
  /// dismissed while this was writing is already gone, and popping again would
  /// take the screen behind it.
  Future<void> _write(EdgeAccess? access) async {
    final route = ModalRoute.of(context);
    final write = ref.read(tlsIdentityProvider.notifier).setEdge(access);
    widget.onWrite(write);
    try {
      await write;
    } catch (_) {
      if (mounted) setState(() => _saving = false);
      rethrow;
    }
    if (!mounted || route?.isCurrent != true) return;
    Navigator.of(context).pop();
  }

  Future<void> _save() => _change(
    ServiceToken(
      host: widget.host,
      clientId: _id.text.trim(),
      clientSecret: _secret.text.trim(),
    ),
  );

  Future<void> _remove(AppLocalizations l10n) async {
    if (_saving) return;
    // Held across the confirmation too: a Save in the frame of this tap would
    // write behind the dialog, and the confirmation would then delete it.
    setState(() => _saving = true);
    final yes = await confirmDialog(
      context,
      id: '${widget.area}.edge_access_remove_confirm',
      title: l10n.edgeAccessRemoveTitle,
      message: l10n.edgeAccessRemoveMessage,
      confirmLabel: l10n.certificateRemoveConfirm,
      destructive: true,
    );
    if (!mounted) return;
    if (!yes) {
      setState(() => _saving = false);
      return;
    }
    await _write(null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    const gutter = EdgeInsets.symmetric(horizontal: DashSpace.gutter);
    // Held open while it writes: the sheet closes itself when that is done.
    return PopScope(
      canPop: !_saving,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: gutter,
                  child: Text(l10n.edgeAccessTitle, style: t.titleMd),
                ),
                const SizedBox(height: DashSpace.xs),
                Padding(
                  padding: gutter,
                  child: Text(
                    l10n.edgeAccessFor(widget.host),
                    style: t.monoMicro,
                  ),
                ),
                const SizedBox(height: DashSpace.md),
                Padding(
                  padding: gutter,
                  child: Text(l10n.edgeAccessServiceToken, style: t.bodyStrong),
                ),
                Padding(
                  padding: gutter,
                  child: Text(
                    l10n.edgeAccessServiceTokenHint,
                    style: t.bodySoft,
                  ),
                ),
                const SizedBox(height: DashSpace.md),
                Padding(
                  padding: gutter,
                  child: TextField(
                    controller: _id,
                    enabled: !_saving,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: t.bodyStrong,
                    onChanged: (_) => setState(() {}),
                    decoration: dashFieldDecoration(
                      t,
                      labelText: l10n.edgeAccessClientId,
                    ),
                  ).tagged('${widget.area}.edge_access_client_id'),
                ),
                const SizedBox(height: DashSpace.md),
                Padding(
                  padding: gutter,
                  child: TextField(
                    controller: _secret,
                    enabled: !_saving,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.visiblePassword,
                    style: t.bodyStrong,
                    onChanged: (_) => setState(() {}),
                    decoration: dashFieldDecoration(
                      t,
                      labelText: l10n.edgeAccessClientSecret,
                    ),
                  ).tagged('${widget.area}.edge_access_client_secret'),
                ),
                const SizedBox(height: DashSpace.md),
                Padding(
                  padding: gutter,
                  child: FilledButton(
                    onPressed: _ready ? _save : null,
                    child: Text(l10n.edgeAccessSave),
                  ).tagged('${widget.area}.edge_access_save'),
                ),
                if (_current != null)
                  Padding(
                    padding: gutter,
                    child: TextButton(
                      onPressed: _saving ? null : () => _remove(l10n),
                      style: TextButton.styleFrom(foregroundColor: t.dangerInk),
                      child: Text(l10n.edgeAccessRemove),
                    ).tagged('${widget.area}.edge_access_remove'),
                  ),
                const SizedBox(height: DashSpace.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
