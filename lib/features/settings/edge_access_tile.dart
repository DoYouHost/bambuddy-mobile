import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/edge_access.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../setup/edge_access_sheet.dart';

/// The Cloudflare Access credential outside the setup screen (#72), where a
/// token that was revoked or reissued is replaced or removed. Only there when
/// one is saved: a person whose server is not behind Access never sees it, and
/// one whose is gets it offered by the setup screen the moment it matters.
class EdgeAccessTile extends ConsumerWidget {
  const EdgeAccessTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(edgeAccessProvider);
    if (access == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: DashSpace.sm),
      child: SettingsEntryTile(
        icon: Icons.cloud_outlined,
        title: l10n.edgeAccessTitle,
        subtitle: switch (access) {
          ServiceToken() => l10n.edgeAccessConfigured(access.host),
          BrowserSession() => access.host,
        },
        onTap: () => showEdgeAccessSheet(
          context,
          host: access.host,
          area: 'app_settings',
        ),
        id: 'app_settings.edge_access',
      ),
    );
  }
}
