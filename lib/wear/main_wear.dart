import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/notifications/hms_catalog.dart';
import '../providers.dart';
import 'wear_app.dart';

/// Entry point for the Wear OS build. Deliberately lean: no foreground service,
/// no WebSocket, no notifications, no home widget — the watch app is a thin,
/// on-demand REST client that reuses `core/` + `data/`. Build with:
///   flutter run --target lib/wear/main_wear.dart
///
/// Orientation is locked to natural via android:screenOrientation="nosensor"
/// in the wear flavor manifest. We must NOT call
/// SystemChrome.setPreferredOrientations here: it runs
/// setRequestedOrientation(PORTRAIT) at startup, and on the square watch
/// display "portrait" still lets the system rotate 90° — it overrode the
/// manifest lock and reintroduced the rotation bug.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // Without the catalog a fault has no description, and an unnamed fault is
  // hidden — so on the watch this line is the difference between the error
  // panel existing and never appearing at all. The raw platform locale is
  // enough: `load` narrows it to the two tables that exist, which is why this
  // does not reach for the phone's `systemLocale` and drag the print monitor
  // into the watch build with it.
  await HmsCatalog.instance.load(PlatformDispatcher.instance.locale);
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const WearApp(),
    ),
  );
}
