import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// The Google Play requirements a source file can answer, so a change that
/// breaks one fails here instead of in a Play review. The whole list, and the
/// rows only a person can check, is docs/play-compliance.md.
void main() {
  const doc = 'docs/play-compliance.md';
  const phoneManifest = 'android/app/src/main/AndroidManifest.xml';
  const wearManifest = 'android/app/src/wear/AndroidManifest.xml';
  const gradle = 'android/app/build.gradle.kts';

  String read(String path) => File(path).readAsStringSync();

  /// `android.permission.X` names in the source manifest, as bare names.
  /// The whole tag first: XML puts no order on attributes.
  Set<String> permissions(String manifest, {required bool removed}) => {
    for (final tag in RegExp(r'<uses-permission\b[^>]*>').allMatches(manifest))
      if (RegExp(
            r'android:name="android\.permission\.(\w+)"',
          ).firstMatch(tag.group(0)!)
          case final m?)
        if (tag.group(0)!.contains('tools:node="remove"') == removed)
          m.group(1)!,
  };

  group('permissions match the table in $doc', () {
    // | `NAME` | source | phone | watch | why |
    final rows = {
      for (final m in RegExp(
        r'^\| `(\w+)` \| (manifest|plugin) \| (yes|no) \| (yes|no) \|',
        multiLine: true,
      ).allMatches(read(doc)))
        m.group(1)!: (source: m.group(2)!, watch: m.group(4) == 'yes'),
    };
    final declared = permissions(read(phoneManifest), removed: false);
    final stripped = permissions(read(wearManifest), removed: true);

    test('the table was found', () => expect(rows, isNotEmpty));

    test('every permission the manifest declares has a manifest row', () {
      final documented = {
        for (final e in rows.entries)
          if (e.value.source == 'manifest') e.key,
      };
      expect(
        declared,
        documented,
        reason:
            'a new permission needs a row and a reason in $doc before it '
            'ships (and an explicit yes, AGENTS.md "Stop and ask: security")',
      );
    });

    test('no battery-optimisation exemption request (Play policy, #53)', () {
      expect(declared, isNot(contains('REQUEST_IGNORE_BATTERY_OPTIMIZATIONS')));
    });

    test('the watch column is what the watch manifest leaves in', () {
      for (final name in declared) {
        expect(
          !stripped.contains(name),
          rows[name]!.watch,
          reason: '$name: watch column in $doc',
        );
      }
    });
  });

  test('every component sets android:exported (Component_Export)', () {
    for (final path in [phoneManifest, wearManifest]) {
      final tags = RegExp(
        r'<(activity|service|receiver|provider)\b[^>]*>',
      ).allMatches(read(path)).map((m) => m.group(0)!);
      for (final tag in tags) {
        if (tag.contains('tools:node="remove"') ||
            tag.contains('tools:node="merge"')) {
          continue;
        }
        expect(tag, contains('android:exported='), reason: '$path: $tag');
      }
    }
  });

  group('SDK levels', () {
    final source = read(gradle);

    /// Flutter's own default, which `flutter.targetSdkVersion` resolves to.
    int flutterDefault(String name) {
      final root = Platform.environment['FLUTTER_ROOT'];
      if (root == null) fail('FLUTTER_ROOT is not set; run under flutter test');
      final ext = File(
        '$root/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt',
      ).readAsStringSync();
      return int.parse(
        RegExp('val $name: Int = (\\d+)').firstMatch(ext)!.group(1)!,
      );
    }

    int targetSdk() {
      final m = RegExp(r'targetSdk = (\S+)').firstMatch(source)!.group(1)!;
      return m == 'flutter.targetSdkVersion'
          ? flutterDefault('targetSdkVersion')
          : int.parse(m);
    }

    test('targets what Play requires of a phone app (API 35+), which also '
        'covers Wear (34+)', () {
      expect(targetSdk(), greaterThanOrEqualTo(35));
    });

    test('compiles against at least what it targets', () {
      final compile = int.parse(
        RegExp(r'compileSdk = (\d+)').firstMatch(source)!.group(1)!,
      );
      expect(compile, greaterThanOrEqualTo(targetSdk()));
    });

    test('no ABI filter can drop 64-bit (Wear: required from 2026-09-15)', () {
      expect(source, isNot(contains('abiFilters')));
    });
  });

  test('the watch splash is the app icon on black (WO-V15)', () {
    final styles = read('android/app/src/wear/res/values/styles.xml');
    final launch = RegExp(
      r'<style name="WearLaunchTheme"[\s\S]*?</style>',
    ).firstMatch(styles)!.group(0)!;
    expect(
      launch,
      contains(
        '<item name="windowSplashScreenBackground">@android:color/black</item>',
      ),
    );
    expect(launch, contains('windowSplashScreenAnimatedIcon'));
    expect(
      read(wearManifest),
      contains('android:theme="@style/WearLaunchTheme"'),
    );
  });

  test('the watch app needs the phone app, and the phone says it has it', () {
    // No typing on the watch (WO-P6) means setup only comes from the phone.
    expect(
      read(wearManifest),
      matches(
        RegExp(
          r'android:name="com\.google\.android\.wearable\.standalone"\s*'
          r'android:value="false"',
        ),
      ),
    );
    // The watch asks for this capability before offering an install; nothing
    // in the code reads the array, so only the keep rule saves it from the
    // release shrinker.
    expect(
      read('android/app/src/mobile/res/values/wear.xml'),
      contains('<item>bambuddy_phone_app</item>'),
    );
    expect(
      read('android/app/src/mobile/res/raw/keep.xml'),
      contains('@array/android_wear_capabilities'),
    );
  });

  group('the Play listing (WO-G2)', () {
    final listing = read('docs/play-store-listing.md');

    test('never says Android Wear', () {
      expect(listing.toLowerCase(), isNot(contains('android wear')));
    });

    test('has a translation for every language the app ships', () {
      final locales = Directory('lib/l10n')
          .listSync()
          .map((f) => RegExp(r'app_(\w+)\.arb$').firstMatch(f.path)?.group(1))
          .nonNulls
          .where((l) => l != 'en');
      expect(locales, isNotEmpty);
      for (final lang in locales) {
        expect(listing, contains('($lang-'), reason: 'no $lang section');
      }
    });
  });

  /// Width and height of every PNG under the screenshots folder [dir].
  List<(String, int, int)> sizes(String dir) => [
    for (final f in Directory(
      'docs/store-assets/screenshots/$dir',
    ).listSync(recursive: true))
      if (f is File && f.path.endsWith('.png'))
        // PNG: width and height are the two big-endian words at byte 16.
        switch (ByteData.sublistView(f.readAsBytesSync(), 16, 24)) {
          final h => (f.path, h.getUint32(0), h.getUint32(4)),
        },
  ];

  test('the Wear screenshots are square (WO-G5)', () {
    final shots = sizes('wear');
    expect(shots, isNotEmpty, reason: 'Play needs at least one');
    for (final (path, w, h) in shots) {
      expect(w, h, reason: '$path is not 1:1');
    }
  });

  test('no screenshot is longer than twice its width, as Play requires', () {
    // "Add preview assets": 320-3840 px, the long side at most twice the short.
    final shots = sizes('');
    expect(shots, isNotEmpty);
    for (final (path, w, h) in shots) {
      final (short, long) = w < h ? (w, h) : (h, w);
      expect(long, lessThanOrEqualTo(2 * short), reason: '$path is $w x $h');
      expect(short, greaterThanOrEqualTo(320), reason: path);
      expect(long, lessThanOrEqualTo(3840), reason: path);
    }
  });
}
