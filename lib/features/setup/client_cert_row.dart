import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/client_cert.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/device_files.dart';

/// Import or remove the certificate a reverse proxy with mutual TLS asks for
/// (#65). Any file type, as for the CA: [ClientCert.parse] is the filter. A
/// file without a password goes straight in; the password is asked for only
/// when the file says it needs one.
class ClientCertRow extends ConsumerStatefulWidget {
  const ClientCertRow({super.key, this.enabled = true, this.area = 'setup'});

  final bool enabled;

  /// The screen the row's controls log under.
  final String area;

  @override
  ConsumerState<ClientCertRow> createState() => _ClientCertRowState();
}

class _ClientCertRowState extends ConsumerState<ClientCertRow> {
  /// A second tap while the picker opens would fail as "already active".
  bool _picking = false;

  String get _id => '${widget.area}.client_cert';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final cert = ref.watch(clientCertProvider);
    final enabled = widget.enabled && !_picking;
    if (cert == null) {
      return Center(
        child: logTag(
          '${_id}_import',
          TextButton.icon(
            onPressed: enabled ? () => _import(l10n) : null,
            icon: Icon(
              Icons.badge_outlined,
              size: DashIcon.md,
              color: t.textSecondary,
            ),
            label: Text(l10n.clientCertImport),
            style: TextButton.styleFrom(foregroundColor: t.textSecondary),
          ),
        ),
      );
    }
    return Row(
      children: [
        Icon(Icons.badge, size: DashIcon.md, color: t.accentGreen),
        const SizedBox(width: DashSpace.sm),
        Expanded(child: Text(l10n.clientCertInUse(cert.name), style: t.body)),
        IconButton(
          onPressed: enabled ? () => _remove(l10n) : null,
          tooltip: l10n.clientCertRemove,
          icon: Icon(Icons.close, color: t.textSecondary),
        ).tagged('${_id}_remove'),
      ],
    );
  }

  Future<void> _remove(AppLocalizations l10n) async {
    final yes = await confirmDialog(
      context,
      id: '${_id}_remove_confirm',
      title: l10n.clientCertRemoveTitle,
      message: l10n.clientCertRemoveMessage,
      confirmLabel: l10n.certificateRemoveConfirm,
      destructive: true,
    );
    if (!yes || !mounted) return;
    await ref.read(tlsIdentityProvider.notifier).setCert(null);
  }

  Future<void> _import(AppLocalizations l10n) async {
    if (_picking) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _picking = true);
    try {
      final picked = await pickFileFromDevice();
      if (!mounted) return;
      if (picked.outcome == DeviceFileOutcome.failed) {
        messenger.snack(l10n.customCaPickFailed);
        return;
      }
      final file = picked.file;
      if (file == null) return;
      final bytes = await readSmallPickedFile(file, ClientCert.maxBytes);
      if (!mounted) return;
      var result = ClientCert.parse(file.name, bytes, '');
      if (result.wrongPassword) {
        final password = await showDialog<String>(
          context: context,
          builder: (_) => _PasswordDialog(id: '${_id}_password'),
        );
        if (password == null || !mounted) return;
        result = ClientCert.parse(file.name, bytes, password);
      }
      final cert = result.cert;
      if (cert == null) {
        messenger.snack(
          result.wrongPassword
              ? l10n.clientCertWrongPassword
              : l10n.clientCertInvalid,
        );
        return;
      }
      await ref.read(tlsIdentityProvider.notifier).setCert(cert);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }
}

/// Not `promptName`: that trims, and a password may end in a space, and shows
/// what is typed.
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.id});

  final String id;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = MaterialLocalizations.of(context);
    return logSurface(
      widget.id,
      AlertDialog(
        scrollable: true,
        title: Text(l10n.clientCertPasswordTitle),
        content: TextField(
          controller: _controller,
          autofocus: true,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          keyboardType: TextInputType.visiblePassword,
          decoration: InputDecoration(labelText: l10n.passwordLabel),
          onSubmitted: (v) => Navigator.pop(context, v),
        ).tagged('${widget.id}.field'),
        actions: [
          logTag(
            '${widget.id}.cancel',
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(labels.cancelButtonLabel),
            ),
          ),
          logTag(
            '${widget.id}.save',
            FilledButton(
              onPressed: () => Navigator.pop(context, _controller.text),
              child: Text(labels.okButtonLabel),
            ),
          ),
        ],
      ),
    );
  }
}
