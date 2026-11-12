import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../core/models/external_link.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../common/dash_async.dart';
import '../common/media_image.dart';
import '../common/web_link.dart';
import 'external_links_providers.dart';

/// The web sidebar's other apps as a list: the name, where it lives, and the
/// count it reports. A tap opens the link in the browser — the web shows some
/// of them in a frame (`open_in_new_tab`), which a phone has no place for.
/// Read only; adding and ordering links stay in the web UI. The drawer re-reads
/// the list as it opens, so this screen starts from fresh counts.
class ExternalLinksScreen extends ConsumerWidget {
  const ExternalLinksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    Future<void> refresh() => ref.refresh(externalLinksProvider.future);
    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.linkedAppsTitle),
        body: dashAsync(
          context,
          ref.watch(externalLinksProvider),
          onRetry: refresh,
          data: (links) => RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              padding: screenListPadding(context),
              children: [
                if (links.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: DashSpace.xl),
                    child: Text(
                      l10n.linkedAppsEmpty,
                      textAlign: TextAlign.center,
                      style: t.labelSoft.copyWith(color: t.textSecondary),
                    ),
                  ),
                for (final link in links) ExternalLinkTile(link: link),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ExternalLinkTile extends StatelessWidget {
  const ExternalLinkTile({super.key, required this.link});

  final ExternalLink link;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return TappableCard(
      id: 'links.item',
      onTap: () => openWebLink(context, link.url),
      child: Row(
        children: [
          _LinkIcon(link: link),
          const SizedBox(width: DashSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(link.name, style: t.titleSm),
                if (link.address.isNotEmpty)
                  Text(
                    link.address,
                    style: t.monoMicro.copyWith(color: t.textTertiary),
                  ),
              ],
            ),
          ),
          if (link.badge > 0) ...[
            const SizedBox(width: DashSpace.md),
            ExternalLinkBadge(count: link.badge),
          ],
          const SizedBox(width: DashSpace.md),
          Icon(Icons.open_in_new, size: DashIcon.sm, color: t.textTertiary),
        ],
      ),
    );
  }
}

/// The count as the web draws it: amber, capped at 99+.
class ExternalLinkBadge extends StatelessWidget {
  const ExternalLinkBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return DashPill(
      label: externalLinkBadgeLabel(count),
      accent: t.warning,
      accentInk: t.warningInk,
      dense: true,
    );
  }
}

/// The picture the link was given on the web, or its first letter: the web
/// names a Lucide glyph, which has no counterpart here. The letter is also what
/// shows while the picture loads and when it cannot be drawn (an SVG, or an
/// older server that wants another token for it).
class _LinkIcon extends StatelessWidget {
  const _LinkIcon({required this.link});

  final ExternalLink link;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final radius = BorderRadius.circular(DashRadius.md);
    Widget letter() => Container(
      width: DashSize.d40,
      height: DashSize.d40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.accentGreen.withValues(alpha: DashAlpha.wash),
        borderRadius: radius,
      ),
      child: Text(
        link.initial,
        style: t.titleMd.copyWith(color: t.accentGreenInk),
      ),
    );
    if (!link.hasCustomIcon) return letter();
    return MediaImage(
      path: Endpoints.externalLinkIcon(link.id),
      width: DashSize.d40,
      height: DashSize.d40,
      borderRadius: radius,
      fit: BoxFit.contain,
      placeholder: (_) => letter(),
    );
  }
}
