import 'package:flutter/material.dart';

import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../makerworld/makerworld_tab.dart';

/// Where models come into the library from, one tab each — the web's Model
/// Sources page (`ModelSourcesPage.tsx`, #1471).
class ModelSourcesScreen extends StatelessWidget {
  const ModelSourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DashBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: dashAppBar(context, title: l10n.modelSourcesTitle),
        body: const MakerWorldTab(),
      ),
    );
  }
}
