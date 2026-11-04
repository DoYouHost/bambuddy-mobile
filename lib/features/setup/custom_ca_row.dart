import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/custom_ca.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/device_files.dart';

/// Import or remove the CA a server behind the user's own certificate
/// authority needs (#62). Any file type: Android's picker filters by MIME type,
/// and `.pem`/`.crt` map to none it knows, so [CustomCa.parse] is the filter.
class CustomCaRow extends ConsumerWidget {
  const CustomCaRow({super.key, this.enabled = true});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final ca = ref.watch(customCaProvider);
    if (ca == null) {
      return Center(
        child: logTag(
          'setup.ca_import',
          TextButton.icon(
            onPressed: enabled ? () => _import(context, ref, l10n) : null,
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

  Future<void> _import(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await pickFileFromDevice(withData: true);
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
