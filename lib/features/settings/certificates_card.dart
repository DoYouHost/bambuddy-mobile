import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../setup/certificate_rows.dart';

/// The CA (#62) and the client certificate (#65) outside the setup screen,
/// which a signed-in user never sees again: a certificate that expires or is
/// reissued is replaced here. "Remove all" appears only once there are two,
/// since with one it is that row's own button.
class CertificatesCard extends ConsumerWidget {
  const CertificatesCard({super.key});

  static const _area = 'app_settings';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    final both =
        ref.watch(customCaProvider) != null &&
        ref.watch(clientCertProvider) != null;
    const inset = EdgeInsets.symmetric(
      horizontal: DashSpace.md,
      vertical: DashSpace.xs,
    );
    return SettingsCard(
      rows: [
        const Padding(
          padding: inset,
          child: CertificateRows(area: _area),
        ),
        if (both)
          Center(
            child: logTag(
              '$_area.certificates_remove_all',
              TextButton(
                onPressed: () => _removeAll(context, ref, l10n),
                style: TextButton.styleFrom(foregroundColor: t.dangerInk),
                child: Text(l10n.certificatesRemoveAll),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _removeAll(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final yes = await confirmDialog(
      context,
      id: '$_area.certificates_remove_all_confirm',
      title: l10n.certificatesRemoveAllTitle,
      message: l10n.certificatesRemoveAllMessage,
      confirmLabel: l10n.certificateRemoveConfirm,
      destructive: true,
    );
    if (!yes || !context.mounted) return;
    await ref.read(tlsIdentityProvider.notifier).setBoth(null, null);
  }
}
