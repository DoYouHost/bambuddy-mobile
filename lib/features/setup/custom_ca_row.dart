import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/custom_ca.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/device_files.dart';

/// Import or remove the CA a server behind the user's own certificate
/// authority needs (#62). Any file type: the picker filters by MIME type, and
/// `.pem`, `.der` or a file with no extension would not be offered at all, so
/// [CustomCa.parse] is the filter.
class CustomCaRow extends ConsumerStatefulWidget {
  const CustomCaRow({super.key, this.enabled = true});

  final bool enabled;

  @override
  ConsumerState<CustomCaRow> createState() => _CustomCaRowState();
}

class _CustomCaRowState extends ConsumerState<CustomCaRow> {
  /// A second tap while the picker opens would fail as "already active" and
  /// read as a broken file.
  bool _picking = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final ca = ref.watch(customCaProvider);
    final enabled = widget.enabled && !_picking;
    if (ca == null) {
      return Center(
        child: logTag(
          'setup.ca_import',
          TextButton.icon(
            onPressed: enabled ? () => _import(l10n) : null,
            icon: Icon(
              Icons.verified_user_outlined,
              size: DashIcon.md,
              color: t.textSecondary,
            ),
            label: Text(l10n.customCaImport),
            style: TextButton.styleFrom(foregroundColor: t.textSecondary),
          ),
        ),
      );
    }
    return Row(
      children: [
        Icon(Icons.verified_user, size: DashIcon.md, color: t.accentGreen),
        const SizedBox(width: DashSpace.sm),
        Expanded(child: Text(l10n.customCaTrusted(ca.name), style: t.body)),
        IconButton(
          onPressed: enabled
              ? () => ref.read(customCaProvider.notifier).set(null)
              : null,
          tooltip: l10n.customCaRemove,
          icon: Icon(Icons.close, color: t.textSecondary),
        ).tagged('setup.ca_remove'),
      ],
    );
  }

  Future<void> _import(AppLocalizations l10n) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _picking = true);
    final PickedFileResult picked;
    try {
      picked = await pickFileFromDevice(withData: true);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
    if (!mounted) return;
    final file = picked.file;
    if (picked.outcome == DeviceFileOutcome.failed) {
      messenger.snack(l10n.customCaPickFailed);
      return;
    }
    if (file == null) return;
    final ca = CustomCa.parse(file.name, file.bytes ?? const []);
    if (ca == null) {
      messenger.snack(l10n.customCaInvalid);
      return;
    }
    await ref.read(customCaProvider.notifier).set(ca);
  }
}
