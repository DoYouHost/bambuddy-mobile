import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';

/// Public source URL — app is AGPL-3.0, so code link is license requirement
/// (see 02 §license hygiene).
const String _sourceUrl = 'https://codeberg.org/DoYouHost/bambuddy-mobile';
const String _licenseUrl = 'https://www.gnu.org/licenses/agpl-3.0.html';

/// "About" screen: name/version, AGPL-3.0 license notice, source link, and entry
/// to `showLicensePage` with dependency licenses. Full screen outside shell
/// (pushed from Dashboard drawer).
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);

    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.aboutTitle),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/icon/icon.png',
                    width: 88,
                    height: 88,
                    errorBuilder: (_, _, _) =>
                        Icon(Icons.print, size: 88, color: t.textPrimary),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Bambuddy',
                  style: TextStyle(
                    fontFamily: DashTokens.fontUi,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const _VersionLabel(),
                const SizedBox(height: 12),
                Text(
                  l10n.aboutTagline,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: DashTokens.fontUi,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: t.textSecondary,
                  ),
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
                  subtitle: 'codeberg.org/DoYouHost/bambuddy-mobile',
                  onTap: () => _open(context, _sourceUrl, l10n),
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
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(
      BuildContext context, String url, AppLocalizations l10n) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.aboutOpenLinkError)));
    }
  }

  Future<void> _showLicenses(BuildContext context) async {
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    showLicensePage(
      context: context,
      applicationName: 'Bambuddy',
      applicationVersion: '${info.version}+${info.buildNumber}',
      applicationLegalese: '© DoYouHost · AGPL-3.0',
    );
  }
}

/// Version read from package metadata (pubspec → buildName+buildNumber).
class _VersionLabel extends StatefulWidget {
  const _VersionLabel();

  @override
  State<_VersionLabel> createState() => _VersionLabelState();
}

class _VersionLabelState extends State<_VersionLabel> {
  // Created once in initState — a plain call in build() would kick off a
  // brand-new platform-channel future (and a "…" flash) on every rebuild.
  late final Future<PackageInfo> _future = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = DashTokens.of(context);
    return FutureBuilder<PackageInfo>(
      future: _future,
      builder: (context, snap) {
        final v = snap.hasData
            ? '${snap.data!.version}+${snap.data!.buildNumber}'
            : '…';
        return Text(
          l10n.aboutVersion(v),
          style: TextStyle(
            fontFamily: DashTokens.fontMono,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: t.textTertiary,
          ),
        );
      },
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
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: t.accentGreenInk,
              ),
            ),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(
              body!,
              style: TextStyle(
                fontFamily: DashTokens.fontUi,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: t.textSecondary,
              ),
            ),
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
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
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
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: DashTokens.fontUi,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontFamily: DashTokens.fontUi,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: t.textTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: t.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
