import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../settings/appearance_prefs.dart';
import 'app_brand.dart';
import 'dash_theme.dart';

/// The accent and light/dark choice, read synchronously from the preferences
/// `main()` loaded, so the first frame already wears it.
final appearanceProvider =
    NotifierProvider<AppearanceNotifier, AppearancePrefs>(
      AppearanceNotifier.new,
    );

class AppearanceNotifier extends Notifier<AppearancePrefs> {
  var _latest = 0;

  @override
  AppearancePrefs build() =>
      ref.watch(settingsRepositoryProvider).loadAppearancePrefs();

  /// Applied before the write, so a second choice made while the first is
  /// still saving starts from it instead of undoing it. A failed write falls
  /// back to what is stored, unless a later choice has already replaced it.
  Future<void> set(AppearancePrefs prefs) async {
    if (prefs == state) return;
    state = prefs;
    final call = ++_latest;
    try {
      await ref.read(settingsRepositoryProvider).saveAppearancePrefs(prefs);
    } catch (_) {
      if (call == _latest) {
        state = ref.read(settingsRepositoryProvider).loadAppearancePrefs();
      }
      rethrow;
    }
  }
}

/// The system's Material You schemes; null below Android 12 or wherever the
/// platform has none.
typedef SystemSchemes = ({ColorScheme light, ColorScheme dark});

/// Never throws: a platform that cannot answer is one without a palette, and a
/// failure here must not stop the app before `runApp`.
Future<SystemSchemes?> readSystemSchemes() async {
  try {
    final palette = await DynamicColorPlugin.getCorePalette();
    if (palette == null) return null;
    return (
      light: palette.toColorScheme(),
      dark: palette.toColorScheme(brightness: Brightness.dark),
    );
  } on Object {
    return null;
  }
}

/// What `main()` read before `runApp`; overridden there.
final initialSystemSchemesProvider = Provider<SystemSchemes?>((_) => null);

/// How the palette is read again; a seam for tests.
final systemSchemesReaderProvider = Provider<Future<SystemSchemes?> Function()>(
  (_) => readSystemSchemes,
);

/// The system schemes, re-read on every resume.
///
/// On the API 35 emulator a wallpaper change recreates the activity, and this
/// phone flavor's engine with it, so `main()` reads the new palette anyway
/// (docs/appearance.md). The resume read covers a build that delivers the
/// change without recreating the activity. Not overridden itself: an override
/// would replace this notifier and its listener.
final systemSchemesProvider =
    NotifierProvider<SystemSchemesNotifier, SystemSchemes?>(
      SystemSchemesNotifier.new,
    );

class SystemSchemesNotifier extends Notifier<SystemSchemes?> {
  var _disposed = false;

  @override
  SystemSchemes? build() {
    _disposed = false;
    final listener = AppLifecycleListener(onResume: _reread);
    ref.onDispose(() {
      _disposed = true;
      listener.dispose();
    });
    return ref.watch(initialSystemSchemesProvider);
  }

  // A palette does not go away while the app runs, so a null here is a
  // failed read; keeping the last palette keeps a chosen "System" accent.
  Future<void> _reread() async {
    final schemes = await ref.read(systemSchemesReaderProvider)();
    if (!_disposed && schemes != null) state = schemes;
  }
}

/// The brand the app paints with, rebuilt only when the accent or the system
/// schemes change — not on every rebuild of the app widget.
final appBrandProvider = Provider<DashBrand>(
  (ref) => resolveBrand(
    ref.watch(appearanceProvider.select((p) => p.accent)),
    ref.watch(systemSchemesProvider),
  ),
);
