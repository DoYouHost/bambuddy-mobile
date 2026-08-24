import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/watch/watch_config_sync.dart';
import '../l10n/app_localizations.dart';
import '../providers.dart';
import 'screens/wear_home.dart';
import 'screens/wear_setup_screen.dart';
import 'wear_providers.dart';
import 'wear_theme.dart';

/// Root of the Wear app. Routes purely on whether a server profile exists —
/// no bottom nav, no drawer; drill-down uses a plain [Navigator]. The look lives
/// in [wearTheme].
///
/// Also the receiver end of the phone→watch config handoff: on launch it reads
/// any latched config and listens for live pushes, so the user never has to type
/// the server details on the watch. What arrives is adopted straight away only
/// when it names the server already in use; a different one is offered through
/// [pendingWatchConfigProvider] and waits for a tap — see [_routeConfig].
class WearApp extends ConsumerStatefulWidget {
  const WearApp({super.key});

  @override
  ConsumerState<WearApp> createState() => _WearAppState();
}

class _WearAppState extends ConsumerState<WearApp>
    with WidgetsBindingObserver {
  StreamSubscription<WatchConfig>? _configSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ingestPendingConfig();
    _configSub = ref
        .read(watchConfigSyncProvider)
        .configStream()
        .listen(_routeConfig);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _configSub?.cancel();
    super.dispose();
  }

  /// Coming back to the foreground → fetch immediately: the OS freezes the
  /// app (and its poll timer) in the background, so the last data can be
  /// minutes old. Guarded by `exists` so it never *creates* the fleet
  /// provider (e.g. while still on the setup screen).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.exists(wearFleetProvider)) {
      unawaited(ref.read(wearFleetProvider.notifier).refresh());
    }
  }

  /// Cold start: the phone may have pushed while the watch app was closed, so
  /// read the latest latched context and route it the same way a live push goes.
  Future<void> _ingestPendingConfig() async {
    final config = await ref.read(watchConfigSyncProvider).latestPending();
    if (config != null) await _routeConfig(config);
  }

  /// Decides what an incoming config is allowed to do on its own.
  ///
  /// Only a push naming the server already running is adopted silently — that
  /// one carries a refreshed secret for a server the user has already chosen.
  /// Anything else is a switch, so it is offered rather than applied: the phone
  /// pushes on every launch, and this app used to let those overwrite a watch
  /// that was working, with nothing on screen to say so.
  Future<void> _routeConfig(WatchConfig config) async {
    if (config.isSameServerAs(ref.read(serverProfileProvider))) {
      await _applyConfig(config);
      return;
    }
    if (!mounted) return;
    ref.read(pendingWatchConfigProvider.notifier).offer(config);
  }

  Future<void> _applyConfig(WatchConfig config) async {
    try {
      await ref.read(pendingWatchConfigProvider.notifier).adopt(config);
    } catch (_) {
      // Nothing on screen to tell: this runs without anyone having asked for it.
      // A failed write leaves the profile as it was and the config on the Data
      // Layer latch, so the setup screen can offer it again.
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasProfile =
        ref.watch(serverProfileProvider.select((p) => p != null));
    return MaterialApp(
      title: 'Bambuddy Watch',
      debugShowCheckedModeBanner: false,
      theme: wearTheme(),
      // Follow the watch's system language (same l10n set as the phone app).
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: hasProfile ? const WearHome() : const WearSetupScreen(),
    );
  }
}
