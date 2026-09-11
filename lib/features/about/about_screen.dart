import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:app_diagnostics/app_diagnostics.dart';
import '../../core/platform/app_version.dart';
import '../../core/theme/dash_text.dart';
import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../common/dash_snack.dart';
import '../common/server_version_text.dart';
import '../common/system_insets.dart';

/// Public source URL — app is AGPL-3.0, so code link is license requirement
/// (see 02 §license hygiene).
const String _sourceUrl = 'https://github.com/DoYouHost/bambuddy-mobile';
const String _licenseUrl = 'https://www.gnu.org/licenses/agpl-3.0.html';

/// "About" screen: name/version, AGPL-3.0 license notice, source link, and entry
/// to `showLicensePage` with dependency licenses. Full screen outside shell
/// (pushed from Dashboard drawer).
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  /// Side of the app icon at the top.
  static const _iconSize = 88.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.aboutTitle),
        body: ListView(
          padding: withSystemNavInset(
            context,
            const EdgeInsets.fromLTRB(16, 8, 16, 24),
          ),
          children: [
            Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/icon/icon.png',
                    width: _iconSize,
                    height: _iconSize,
                    // Same 1024x1024 launcher source as the drawer header —
                    // and a second cache entry, since the resized provider is
                    // keyed apart from the plain one.
                    cacheWidth:
                        (_iconSize * MediaQuery.devicePixelRatioOf(context))
                            .round(),
                    errorBuilder: (_, _, _) => Icon(
                      Icons.print,
                      size: _iconSize,
                      color: t.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Bambuddy', style: t.display),
                const SizedBox(height: 4),
                const _VersionLabel(),
                const SizedBox(height: 12),
                Text(
                  l10n.aboutTagline,
                  textAlign: TextAlign.center,
                  style: t.bodySoft,
                ),
              ],
            ),
            const SizedBox(height: 24),
            _AboutSection(
              title: l10n.aboutLicenseHeader,
              body: l10n.aboutLicenseBody,
              rows: [
                _AboutRow(
                  icon: Icons.gavel_outlined,
                  title: l10n.aboutViewLicense,
                  onTap: () => _open(context, _licenseUrl, l10n),
                  id: 'about.license',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _AboutSection(
              title: l10n.aboutSourceHeader,
              body: l10n.aboutSourceBody,
              rows: [
                _AboutRow(
                  icon: Icons.code,
                  title: l10n.aboutSourceLink,
                  subtitle: 'github.com/DoYouHost/bambuddy-mobile',
                  onTap: () => _open(context, _sourceUrl, l10n),
                  id: 'about.source',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _AboutSection(
              rows: [
                _AboutRow(
                  icon: Icons.description_outlined,
                  title: l10n.aboutThirdParty,
                  subtitle: l10n.aboutThirdPartySubtitle,
                  onTap: () => _showLicenses(context),
                  id: 'about.licenses',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    String url,
    AppLocalizations l10n,
  ) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).snack(l10n.aboutOpenLinkError);
    }
  }

  Future<void> _showLicenses(BuildContext context) async {
    final version = await readAppVersion();
    if (!context.mounted) return;
    showLicensePage(
      context: context,
      applicationName: 'Bambuddy',
      applicationVersion: version,
      applicationLegalese: '© DoYouHost · AGPL-3.0',
    );
  }
}

/// This build over the connected server's, in the wording the drawer footer and
/// the watch use — this is the screen someone opens *to read a version off*, and
/// it was the only one of the three that never named the server at all.
class _VersionLabel extends ConsumerWidget {
  const _VersionLabel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return Column(
      children: [
        Text(
          l10n.appVersionLabel(ref.watch(appVersionProvider).value ?? '…'),
          style: t.monoLabel,
        ),
        // Nothing at all rather than "server version unknown" when no server
        // has been added yet: on a fresh install that line reads as a failed
        // connection to a server the user has not named. The drawer needs no
        // such guard — it is the dashboard's, and the dashboard is behind a
        // profile by construction.
        if (ref.watch(serverProfileProvider) != null)
          Text(
            serverVersionText(l10n, ref.watch(serverVersionLabelProvider)),
            style: t.monoLabel,
          ),
      ],
    );
  }
}

/// Card section grouping related [_AboutRow]s, with an optional header + body
/// text above the rows (mirrors the maintenance screen's printer-card layout).
class _AboutSection extends StatelessWidget {
  const _AboutSection({this.title, this.body, required this.rows});

  final String? title;
  final String? body;
  final List<_AboutRow> rows;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: t.cardGradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Text(
              title!,
              style: t.bodyBold.copyWith(
                color: t.accentGreenInk,
                letterSpacing: 0.2,
              ),
            ),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(body!, style: t.bodySoft),
          ],
          if (title != null || body != null) const SizedBox(height: 12),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// Tappable settings-style row (icon tile + title/subtitle + chevron), styled
/// like the maintenance screen's sub-card tiles.
class _AboutRow extends StatelessWidget {
  const _AboutRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    required this.id,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  /// Name for the diagnostic log; the visible title is localized and is not
  /// recorded.
  final String id;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Material(
      type: MaterialType.transparency,
      child: logTag(
        id,
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.subCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.subCardBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: t.accentGreen.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 17, color: t.accentGreenInk),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: t.titleSm),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(subtitle!, style: t.label),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: t.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
