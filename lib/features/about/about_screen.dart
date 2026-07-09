import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/icon/icon.png',
                    width: 88,
                    height: 88,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.print, size: 88),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Bambuddy', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 4),
                const _VersionLabel(),
                const SizedBox(height: 12),
                Text(
                  l10n.aboutTagline,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.hintColor),
                ),
              ],
            ),
          ),
          const Divider(height: 24),

          _SectionHeader(l10n.aboutLicenseHeader),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(l10n.aboutLicenseBody, style: theme.textTheme.bodyMedium),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: Text(l10n.aboutViewLicense),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(context, _licenseUrl, l10n),
          ),

          const Divider(height: 24),

          _SectionHeader(l10n.aboutSourceHeader),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(l10n.aboutSourceBody, style: theme.textTheme.bodyMedium),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(l10n.aboutSourceLink),
            subtitle: const Text('codeberg.org/DoYouHost/bambuddy-mobile'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open(context, _sourceUrl, l10n),
          ),

          const Divider(height: 24),

          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(l10n.aboutThirdParty),
            subtitle: Text(l10n.aboutThirdPartySubtitle),
            onTap: () => _showLicenses(context),
          ),
        ],
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
    final theme = Theme.of(context);
    return FutureBuilder<PackageInfo>(
      future: _future,
      builder: (context, snap) {
        final v = snap.hasData
            ? '${snap.data!.version}+${snap.data!.buildNumber}'
            : '…';
        return Text(
          l10n.aboutVersion(v),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        label,
        style: theme.textTheme.titleSmall
            ?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}
