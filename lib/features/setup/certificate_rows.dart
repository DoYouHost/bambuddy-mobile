import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/client_cert.dart';
import '../../core/api/custom_ca.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/device_files.dart';

/// The CA (#62) and the client certificate (#65) behind one import button:
/// the file says which it is. A key, or a password, makes it the client
/// certificate, even one that fails to load; a bare certificate is a CA. Each kind has one slot, so an
/// import replaces what was there and the button never hides. Any file type:
/// the picker filters by MIME type, and `.pem`, `.der` or a file with no
/// extension would not be offered at all, so the parsers are the filter.
class CertificateRows extends ConsumerStatefulWidget {
  const CertificateRows({super.key, this.enabled = true, this.area = 'setup'});

  final bool enabled;

  /// The screen the controls log under.
  final String area;

  @override
  ConsumerState<CertificateRows> createState() => _CertificateRowsState();
}

class _CertificateRowsState extends ConsumerState<CertificateRows> {
  /// A second tap while the picker opens would fail as "already active" and
  /// read as a broken file.
  bool _picking = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final ca = ref.watch(customCaProvider);
    final cert = ref.watch(clientCertProvider);
    final enabled = widget.enabled && !_picking;
    final tls = ref.read(tlsIdentityProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ca != null)
          _Installed(
            id: '${widget.area}.ca_remove',
            icon: Icons.verified_user,
            label: l10n.customCaTrusted(ca.name),
            tooltip: l10n.customCaRemove,
            confirmTitle: l10n.customCaRemoveTitle,
            confirmMessage: l10n.customCaRemoveMessage,
            onRemove: enabled ? () => tls.setCa(null) : null,
          ),
        if (cert != null)
          _Installed(
            id: '${widget.area}.client_cert_remove',
            icon: Icons.badge,
            label: l10n.clientCertInUse(cert.name),
            tooltip: l10n.clientCertRemove,
            confirmTitle: l10n.clientCertRemoveTitle,
            confirmMessage: l10n.clientCertRemoveMessage,
            onRemove: enabled ? () => tls.setCert(null) : null,
          ),
        logTag(
          '${widget.area}.cert_import',
          TextButton.icon(
            onPressed: enabled ? () => _import(l10n) : null,
            icon: Icon(
              Icons.verified_user_outlined,
              size: DashIcon.md,
              color: t.textSecondary,
            ),
            label: Text(l10n.certificateImport),
            style: TextButton.styleFrom(foregroundColor: t.textSecondary),
          ),
        ),
      ],
    );
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
      // The client certificate goes first: CustomCa.parse takes the
      // certificates out of any PEM, a bundle with a key included.
      var client = ClientCert.parse(file.name, bytes, '');
      final locked = client.wrongPassword;
      if (locked) {
        final password = await showDialog<String>(
          context: context,
          builder: (_) =>
              _PasswordDialog(id: '${widget.area}.client_cert_password'),
        );
        if (password == null || !mounted) return;
        client = ClientCert.parse(file.name, bytes, password);
      }
      final tls = ref.read(tlsIdentityProvider.notifier);
      if (client.cert case final cert?) {
        await tls.setCert(cert);
        return;
      }
      // A password or a key says the file is a client certificate; the CA
      // slot would keep its certificate and drop the reason it failed.
      if (locked || ClientCert.holdsKey(bytes)) {
        messenger.snack(
          client.wrongPassword
              ? l10n.clientCertWrongPassword
              : l10n.clientCertInvalid,
        );
        return;
      }
      final ca = CustomCa.parse(file.name, bytes);
      if (ca == null) {
        messenger.snack(l10n.certificateInvalid);
        return;
      }
      await tls.setCa(ca);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }
}

class _Installed extends StatelessWidget {
  const _Installed({
    required this.id,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.confirmTitle,
    required this.confirmMessage,
    required this.onRemove,
  });

  final String id;
  final IconData icon;
  final String label;
  final String tooltip;
  final String confirmTitle;
  final String confirmMessage;
  final Future<void> Function()? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final remove = onRemove;
    return Row(
      children: [
        Icon(icon, size: DashIcon.md, color: t.accentGreen),
        const SizedBox(width: DashSpace.sm),
        Expanded(child: Text(label, style: t.body)),
        IconButton(
          onPressed: remove == null ? null : () => _remove(context, remove),
          tooltip: tooltip,
          icon: Icon(Icons.close, color: t.textSecondary),
        ).tagged(id),
      ],
    );
  }

  Future<void> _remove(
    BuildContext context,
    Future<void> Function() remove,
  ) async {
    final yes = await confirmDialog(
      context,
      id: '${id}_confirm',
      title: confirmTitle,
      message: confirmMessage,
      confirmLabel: AppLocalizations.of(context).certificateRemoveConfirm,
      destructive: true,
    );
    if (!yes || !context.mounted) return;
    await remove();
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
