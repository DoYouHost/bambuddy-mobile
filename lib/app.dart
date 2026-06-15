import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/app_localizations.dart';
import 'router.dart';

class BambuBuddyApp extends ConsumerWidget {
  const BambuBuddyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
