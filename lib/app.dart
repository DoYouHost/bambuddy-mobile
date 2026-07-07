import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';

import 'features/inventory/inventory_screen.dart' show scanSpoolFlow;
import 'l10n/app_localizations.dart';
import 'providers.dart';
import 'router.dart';

class BambuBuddyApp extends ConsumerStatefulWidget {
  const BambuBuddyApp({super.key});

  @override
  ConsumerState<BambuBuddyApp> createState() => _BambuBuddyAppState();
}

class _BambuBuddyAppState extends ConsumerState<BambuBuddyApp> {
  StreamSubscription<Uri?>? _widgetClickSub;
  // Guard against multiple scanner triggers from one widget tap (cold start may
  // get URI from both initiallyLaunched and stream).
  bool _scanInFlight = false;

  @override
  void initState() {
    super.initState();
    // Home screen widget taps: cold start (initiallyLaunched) and when app alive
    // (stream). Both carry deep-link `bambuddy://widget?...`.
    _widgetClickSub = HomeWidget.widgetClicked.listen(_onWidgetUri);
    unawaited(HomeWidget.initiallyLaunchedFromHomeWidget().then(_onWidgetUri));
    // Hand the current profile to a paired Wear OS watch on launch so it can
    // configure itself without the user typing anything. No-ops without a watch.
    final profile = ref.read(serverProfileProvider);
    if (profile != null) {
      unawaited(ref.read(watchConfigSyncProvider).push(profile));
    }
  }

  @override
  void dispose() {
    _widgetClickSub?.cancel();
    super.dispose();
  }

  void _onWidgetUri(Uri? uri) {
    if (uri == null) return;
    if (uri.queryParameters['action'] == 'scan') {
      _triggerSpoolScan();
    }
  }

  /// Open spool scanner triggered from widget. Requires configured profile
  /// (without it router keeps /setup anyway). Wait for ready navigator — on cold
  /// start first frame may not exist yet.
  void _triggerSpoolScan() {
    if (_scanInFlight) return;
    if (ref.read(serverProfileProvider) == null) return;
    _scanInFlight = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final context = rootNavigatorKey.currentContext;
      if (context == null) {
        _scanInFlight = false;
        return;
      }
      // Land on Filaments tab, then open scanner.
      context.go('/inventory');
      try {
        await scanSpoolFlow(context, ref);
      } finally {
        _scanInFlight = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Re-push to the watch whenever the profile changes (new server, login,
    // "change server"). Best-effort; silently no-ops when no watch is paired.
    ref.listen(serverProfileProvider, (_, next) {
      if (next != null) {
        unawaited(ref.read(watchConfigSyncProvider).push(next));
      }
    });
    // Notifications handled ONLY by background isolate (foreground service);
    // foreground status shown by UI itself, so no monitor here.
    return MaterialApp.router(
      title: 'BambuBuddy',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      // App follows system setting; dark theme like PWA.
      themeMode: ThemeMode.system,
      // Locale auto-detected from system; en = fallback.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

ThemeData _theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.green,
        brightness: brightness,
      ),
    );
