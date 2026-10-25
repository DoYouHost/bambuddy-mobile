import 'package:bambuddy_mobile/core/settings/appearance_prefs.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/core/theme/app_brand.dart';
import 'package:bambuddy_mobile/wear/wear_colours.dart';
import 'package:bambuddy_mobile/wear/wear_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _roleNames = [
  'primary',
  'onPrimary',
  'primaryContainer',
  'onPrimaryContainer',
  'secondary',
  'onSecondary',
  'secondaryContainer',
  'onSecondaryContainer',
  'tertiary',
  'onTertiary',
  'tertiaryContainer',
  'onTertiaryContainer',
  'error',
  'onError',
  'errorContainer',
  'onErrorContainer',
  'onSurface',
  'onSurfaceVariant',
  'outline',
  'outlineVariant',
  'surfaceContainerLow',
  'surfaceContainer',
  'surfaceContainerHigh',
];

/// Every role a distinct colour, so a role read into the wrong field shows.
/// Signed, as Kotlin's `getColor` hands them over.
Map<String, int> _roles() => {
  for (final (i, name) in _roleNames.indexed)
    name: (0xFF000000 + i + 1).toSigned(32),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(
    'page.codeberg.morganmlgman.bambuddy/watch_face_colours',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  final face = watchFaceScheme(_roles());
  const blue = (
    seed: Color(0xFF2E7DD7),
    variant: DynamicSchemeVariant.tonalSpot,
  );

  group('watchFaceScheme', () {
    test('puts each role in its own field, on black (WO-V13)', () {
      expect(face.primary, Color(_roles()['primary']!));
      expect(face.onPrimary, Color(_roles()['onPrimary']!));
      expect(
        face.surfaceContainerHigh,
        Color(_roles()['surfaceContainerHigh']!),
      );
      expect(face.onErrorContainer, Color(_roles()['onErrorContainer']!));
      expect(face.surface, Colors.black);
      expect(wearTheme(face).scaffoldBackgroundColor, Colors.black);
    });

    test('the face answering is a palette', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => _roles());
      expect((await readWatchFaceSchemes())?.dark, face);
    });

    test('dynamic theming off is no palette', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      expect(await readWatchFaceSchemes(), isNull);
    });

    test('a role missing is no palette, not a crash', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => _roles()..remove('outline'),
      );
      expect(await readWatchFaceSchemes(), isNull);
    });

    test('no handler (the phone, a host test) is no palette', () async {
      expect(await readWatchFaceSchemes(), isNull);
    });
  });

  group('wearColorScheme', () {
    test('the face, when chosen and on offer', () {
      expect(
        wearColorScheme(faceColours: true, face: face, accent: blue),
        face,
      );
    });

    test('the phone, when the face is not chosen', () {
      expect(
        wearColorScheme(faceColours: false, face: face, accent: blue),
        wearSeedScheme(blue),
      );
    });

    // Dynamic theming switched off after the choice was made.
    test('the phone, when the face is chosen but has nothing to give', () {
      expect(
        wearColorScheme(faceColours: true, accent: blue),
        wearSeedScheme(blue),
      );
    });

    test('green, with nothing from either: what the watch always drew', () {
      expect(wearColorScheme(faceColours: true), wearTheme().colorScheme);
      expect(wearSeedScheme(wearGreen), wearTheme().colorScheme);
    });

    test('graphite stays grey on the watch', () {
      final scheme = wearSeedScheme(accentPresets[AccentSource.graphite]!);
      for (final c in [scheme.primary, scheme.primaryContainer]) {
        expect(c.r == c.g && c.g == c.b, isTrue, reason: '$c');
      }
    });
  });

  group('stored', () {
    late SettingsRepository repo;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repo = SettingsRepository(await SharedPreferences.getInstance());
    });

    test('the phone accent survives, and null clears it', () async {
      await repo.saveWearPhoneAccent(blue);
      expect(repo.loadWearPhoneAccent(), blue);
      await repo.saveWearPhoneAccent(null);
      expect(repo.loadWearPhoneAccent(), isNull);
    });

    test('a damaged entry is green, not a crash', () async {
      SharedPreferences.setMockInitialValues({
        'wear_phone_accent': '{"seed":"blue"}',
      });
      repo = SettingsRepository(await SharedPreferences.getInstance());
      expect(repo.loadWearPhoneAccent(), isNull);
    });

    test('a variant this build does not know keeps the seed', () async {
      SharedPreferences.setMockInitialValues({
        'wear_phone_accent': '{"seed":4281236951,"variant":"fromTheFuture"}',
      });
      repo = SettingsRepository(await SharedPreferences.getInstance());
      expect(repo.loadWearPhoneAccent(), (
        seed: const Color(0xFF2E7DD7),
        variant: DynamicSchemeVariant.tonalSpot,
      ));
    });

    test('face colours default to off: the phone decides', () {
      expect(repo.loadWearFaceColours(), isFalse);
    });
  });
}
