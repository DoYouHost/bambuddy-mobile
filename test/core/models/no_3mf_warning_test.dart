import 'package:bambuddy_mobile/core/models/no_3mf_warning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('No3mfWarning.fromJson', () {
    test('reads the flag and each known reason slug', () {
      expect(
        No3mfWarning.fromJson(const {
          'has_fallback': true,
          'reason': 'internal_storage',
        }).reason,
        No3mfReason.internalStorage,
      );
      expect(
        No3mfWarning.fromJson(const {
          'has_fallback': true,
          'reason': 'no_external_storage',
        }).reason,
        No3mfReason.noExternalStorage,
      );
      expect(
        No3mfWarning.fromJson(const {'has_fallback': true}).hasFallback,
        isTrue,
      );
    });

    // The reason key is newer than the route: an older server answers
    // `{has_fallback: true}` alone, and that has to keep showing the original
    // slicer-setting wording rather than nothing.
    test('a missing or null reason is the slicer-setting case', () {
      expect(
        No3mfWarning.fromJson(const {'has_fallback': true}).reason,
        No3mfReason.slicerSetting,
      );
      expect(
        No3mfWarning.fromJson(const {'has_fallback': true, 'reason': null})
            .reason,
        No3mfReason.slicerSetting,
      );
    });

    test('an unknown future slug degrades to the original wording', () {
      expect(
        No3mfWarning.fromJson(const {
          'has_fallback': true,
          'reason': 'ftps_login_refused',
        }).reason,
        No3mfReason.slicerSetting,
      );
    });

    test('nothing to nudge about', () {
      final quiet = No3mfWarning.fromJson(
          const {'has_fallback': false, 'reason': null});

      expect(quiet.hasFallback, isFalse);
      expect(No3mfWarning.none.hasFallback, isFalse);
    });

    test('a garbled payload does not throw', () {
      expect(No3mfWarning.fromJson(const {}).hasFallback, isFalse);
      expect(
        No3mfWarning.fromJson(const {'has_fallback': 'yes'}).hasFallback,
        isFalse,
        reason: 'only a real boolean counts — a truthy string is not an answer',
      );
    });
  });
}
