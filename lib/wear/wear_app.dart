import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/watch/watch_config_sync.dart';
import '../providers.dart';
import 'screens/wear_home.dart';
import 'screens/wear_setup_screen.dart';

/// Root of the Wear app. Dark, black-background theme (OLED-friendly) with
/// larger tap targets. Routes purely on whether a server profile exists —
/// no bottom nav, no drawer; drill-down uses a plain [Navigator].
///
/// Also the receiver end of the phone→watch config handoff: on launch it reads
/// any latched config and listens for live pushes, applying them into local
/// storage so the user never has to type the server details on the watch.
class WearApp extends ConsumerStatefulWidget {
  const WearApp({super.key});

  @override
  ConsumerState<WearApp> createState() => _WearAppState();
}

class _WearAppState extends ConsumerState<WearApp> {
  StreamSubscription<WatchConfig>? _configSub;

  @override
  void initState() {
    super.initState();
    _ingestPendingConfig();
    _configSub = ref
        .read(watchConfigSyncProvider)
        .configStream()
        .listen(_applyConfig);
  }

  @override
  void dispose() {
    _configSub?.cancel();
    super.dispose();
  }

  /// Cold start: the phone may have pushed while the watch app was closed —
  /// pick up the latest latched context. Only adopt it when we have no profile
  /// yet, so a locally-completed setup isn't clobbered.
  Future<void> _ingestPendingConfig() async {
    if (ref.read(serverProfileProvider) != null) return;
    final configs = await ref.read(watchConfigSyncProvider).pendingConfigs();
    if (configs.isNotEmpty) await _applyConfig(configs.last);
  }

  Future<void> _applyConfig(WatchConfig config) async {
    await ref.read(watchConfigSyncProvider).apply(config);
    if (!mounted) return;
    // Re-read the freshly persisted profile → re-routes to WearHome.
    ref.invalidate(serverProfileProvider);
  }

  @override
  Widget build(BuildContext context) {
    final hasProfile =
        ref.watch(serverProfileProvider.select((p) => p != null));
    return MaterialApp(
      title: 'BambuBuddy Watch',
      debugShowCheckedModeBanner: false,
      theme: _wearTheme(),
      home: hasProfile ? const WearHome() : const WearSetupScreen(),
    );
  }
}

ThemeData _wearTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Colors.green,
    brightness: Brightness.dark,
  ).copyWith(surface: Colors.black);
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.black,
    useMaterial3: true,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
