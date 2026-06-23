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
  // Strażnik przed wielokrotnym wyzwoleniem skanera z jednego tapnięcia widgetu
  // (cold start może dostać URI i z initiallyLaunched, i ze strumienia).
  bool _scanInFlight = false;

  @override
  void initState() {
    super.initState();
    // Tapnięcia w widget ekranu głównego: cold start (initiallyLaunched) oraz
    // gdy apka już żyje (strumień). Oba niosą deep-link `bambuddy://widget?...`.
    _widgetClickSub = HomeWidget.widgetClicked.listen(_onWidgetUri);
    unawaited(HomeWidget.initiallyLaunchedFromHomeWidget().then(_onWidgetUri));
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

  /// Otwiera skaner szpuli wyzwolony z widgetu. Wymaga skonfigurowanego profilu
  /// (bez niego router i tak trzyma /setup). Czeka na gotowy nawigator — przy
  /// zimnym starcie pierwsza klatka może jeszcze nie istnieć.
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
      // Ląduj na zakładce Filamentów, potem otwórz skaner.
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
    // Powiadomieniami zajmuje się WYŁĄCZNIE isolate tła (foreground service);
    // na pierwszym planie status pokazuje sam UI, więc nie ma tu monitora.
    return MaterialApp.router(
      title: 'BambuBuddy',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      // Apka idzie za ustawieniem systemu; ciemny motyw jak w PWA.
      themeMode: ThemeMode.system,
      // Locale czytany automatycznie z systemu; en = fallback.
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
