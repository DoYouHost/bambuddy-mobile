import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import '../makerworld/makerworld_tab.dart';
import '../manyfold/manyfold_providers.dart';
import '../manyfold/manyfold_tab.dart';

/// Where models come into the library from, one tab each — the web's Model
/// Sources page (`ModelSourcesPage.tsx`, #1471). The tab bar appears only
/// once there is a second source to switch to.
class ModelSourcesScreen extends ConsumerWidget {
  const ModelSourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(manyfoldStatusProvider).valueOrNull;
    final manyfold = ref.watch(manyfoldTabShownProvider) && status != null;
    final title = dashAppBar(context, title: l10n.modelSourcesTitle);
    if (!manyfold) {
      return DashBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: title,
          body: const MakerWorldTab(),
        ),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) {
          final tabs = DefaultTabController.of(context);
          return DashBackground(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: dashAppBar(
                context,
                title: l10n.modelSourcesTitle,
                bottom: TabBar(
                  tabs: [
                    ListenableBuilder(
                      listenable: tabs,
                      builder: (_, _) => Tab(text: l10n.makerworldTitle).tagged(
                        'model_sources.tab_makerworld',
                        selected: tabs.index == 0,
                      ),
                    ),
                    ListenableBuilder(
                      listenable: tabs,
                      builder: (_, _) => Tab(text: l10n.manyfoldTitle).tagged(
                        'model_sources.tab_manyfold',
                        selected: tabs.index == 1,
                      ),
                    ),
                  ],
                ),
              ),
              body: TabBarView(
                children: [
                  const MakerWorldTab(),
                  ManyfoldTab(status: status),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
