import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  WidgetController.hitTestWarningShouldBeFatal = true;
  TestWidgetsFlutterBinding.ensureInitialized();
  await _loadAppFonts();
  await testMain();
}

/// The app's own fonts, Manrope and JetBrains Mono, for every test. Without them
/// every glyph is a square as wide as it is tall, about twice what the real
/// fonts take, so a label that fits on a phone looks too wide and a check on how
/// text sits proves nothing — and a test that forgot to load them measured a
/// layout the app never draws.
Future<void> _loadAppFonts() async {
  for (final (family, files) in [
    (
      'JetBrainsMono',
      [
        'JetBrainsMono-400.ttf',
        'JetBrainsMono-600.ttf',
        'JetBrainsMono-700.ttf',
      ],
    ),
    (
      'Manrope',
      [
        'Manrope-400.ttf',
        'Manrope-500.ttf',
        'Manrope-600.ttf',
        'Manrope-700.ttf',
      ],
    ),
  ]) {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(rootBundle.load('assets/fonts/$file'));
    }
    await loader.load();
  }
}
