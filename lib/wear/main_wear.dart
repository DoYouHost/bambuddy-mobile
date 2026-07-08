import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers.dart';
import 'wear_app.dart';

/// Entry point for the Wear OS build. Deliberately lean: no foreground service,
/// no WebSocket, no notifications, no home widget — the watch app is a thin,
/// on-demand REST client that reuses `core/` + `data/`. Build with:
///   flutter run --target lib/wear/main_wear.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The manifest is shared with the phone app, so lock rotation here (wear
  // entry point only) instead of via android:screenOrientation. Watches have no
  // sensible landscape mode; keep the UI pinned upright.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const WearApp(),
    ),
  );
}
