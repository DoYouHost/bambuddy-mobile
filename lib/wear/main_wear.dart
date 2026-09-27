import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/notifications/hms_catalog.dart';
import '../l10n/app_locale.dart';
import '../providers.dart';
import 'wear_app.dart';

/// Entry point for the Wear OS build: no foreground service, no WebSocket, no
/// notifications, no home widget — a thin on-demand REST client over `core/` and
/// `data/`. Run with `--target lib/wear/main_wear.dart`.
///
/// **Never call `SystemChrome.setPreferredOrientations` here.** Orientation is
/// locked by `android:screenOrientation="nosensor"` in the wear manifest, and
/// the Dart call issues `setRequestedOrientation(PORTRAIT)`, which on a square
/// display still allows a 90° rotation — it overrode the manifest lock.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Started before the preferences are awaited, not after: both block the first
  // frame, one is a platform round trip and the other reads ~100 KB out of the
  // bundle and decodes it, and neither needs the other's answer. Overlapping
  // them costs a line and buys back whichever is shorter.
  //
  // Still awaited, rather than left running: an unnamed fault is hidden, so
  // without the catalogue the watch's error panel never appears at all.
  final catalog = HmsCatalog.instance.load(systemLocale());
  final prefs = await SharedPreferences.getInstance();
  await catalog;
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const WearApp(),
    ),
  );
}
