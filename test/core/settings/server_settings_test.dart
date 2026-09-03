import 'package:bambuddy_mobile/core/settings/server_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('settingBool', () {
    test('reads a flag the server typed', () {
      expect(const {'on': true}.settingBool('on'), isTrue);
      expect(const {'on': false}.settingBool('on'), isFalse);
    });

    /// The disagreement this reader exists to end: two call sites compared
    /// `== true`, which reads a stringified flag as off.
    test('a flag written as a string counts', () {
      expect(const {'on': 'true'}.settingBool('on'), isTrue);
      expect(const {'on': '1'}.settingBool('on'), isTrue);
      expect(const {'on': 'false'}.settingBool('on'), isFalse);
    });

    test('an absent key takes the fallback', () {
      expect(const <String, dynamic>{}.settingBool('on'), isFalse);
      expect(
        const <String, dynamic>{}.settingBool('on', fallback: true),
        isTrue,
      );
    });

    /// Present but unreadable is an answer — the server said something — so the
    /// fallback does not apply.
    test('an unreadable value is off, not the fallback', () {
      expect(const {'on': null}.settingBool('on', fallback: true), isFalse);
    });
  });

  group('settingDouble', () {
    test('accepts a number or a string', () {
      expect(const {'v': 40}.settingDouble('v', 1), 40.0);
      expect(const {'v': 40.5}.settingDouble('v', 1), 40.5);
      expect(const {'v': '40.5'}.settingDouble('v', 1), 40.5);
    });

    test('falls back on anything else', () {
      expect(const {'v': 'x'}.settingDouble('v', 60), 60.0);
      expect(const <String, dynamic>{}.settingDouble('v', 60), 60.0);
    });
  });

  test('settingString drops blanks and non-strings', () {
    expect(const {'c': ' PLN '}.settingString('c'), 'PLN');
    expect(const {'c': '  '}.settingString('c'), isNull);
    expect(const {'c': 7}.settingString('c'), isNull);
  });

  group('settingBlob', () {
    test('decodes JSON held in a string', () {
      expect(const {'b': '{"a":1}'}.settingBlob('b'), {'a': 1});
    });

    test('takes an object as it stands', () {
      expect(const {'b': {'a': 1}}.settingBlob('b'), {'a': 1});
    });

    /// The stricter of the two decoders this replaced required exactly
    /// `Map<String, dynamic>`, so a map relayed over a platform channel was
    /// dropped as if the setting were empty.
    test('a map that did not come from jsonDecode is still an object', () {
      final relayed = <Object?, Object?>{'a': 1};
      expect({'b': relayed}.settingBlob('b'), {'a': 1});
    });

    test('nothing configured reads as nothing', () {
      expect(const {'b': ''}.settingBlob('b'), isNull);
      expect(const {'b': '   '}.settingBlob('b'), isNull);
      expect(const {'b': '{}'}.settingBlob('b'), isNull);
      expect(const <String, dynamic>{}.settingBlob('b'), isNull);
    });

    test('malformed or wrong-shaped JSON reads as nothing', () {
      expect(const {'b': '{oops'}.settingBlob('b'), isNull);
      expect(const {'b': '[1,2]'}.settingBlob('b'), isNull);
      expect(const {'b': 7}.settingBlob('b'), isNull);
    });
  });
}
