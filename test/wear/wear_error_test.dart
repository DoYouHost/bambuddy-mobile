import 'package:bambuddy_mobile/wear/wear_error.dart';
import 'package:flutter_test/flutter_test.dart';

/// The trimming both watch screens now share. It runs on messages the user is
/// about to read, so the edges matter: an off-by-one here either eats a
/// character of a fitting message or lets one through that wraps.
void main() {
  group('wearShortText', () {
    test('leaves a message that fits exactly as it is', () {
      expect(
        wearShortText('Printer not connected', max: 60),
        'Printer not connected',
      );
    });

    test('leaves a message of exactly the budget alone', () {
      final exact = 'x' * 60;
      expect(wearShortText(exact, max: 60), exact);
    });

    test('cuts one character past the budget, and says so', () {
      final tooLong = 'x' * 61;
      final result = wearShortText(tooLong, max: 60);

      expect(result, '${'x' * 60}…');
      expect(result.length, 61, reason: 'the ellipsis replaces nothing');
    });

    test('what a message already contains is none of its business', () {
      // No special case for an ellipsis, a newline or anything else: inside the
      // budget the text comes back byte for byte.
      expect(wearShortText('Loading…', max: 60), 'Loading…');
      expect(wearShortText('one\ntwo', max: 60), 'one\ntwo');
    });

    test('a long message keeps exactly one ellipsis, its own', () {
      // The cut lands before the text's own trailing one, so nothing ever
      // arrives with two.
      final result = wearShortText('${'x' * 70}…', max: 60);

      expect(result, '${'x' * 60}…');
      expect('…'.allMatches(result), hasLength(1));
    });

    test('handles an empty message', () {
      expect(wearShortText('', max: 60), '');
    });

    test('the toast budget is the larger of the two', () {
      // Named rather than inlined so the difference stays an argument, and the
      // argument is room rather than time: the passing message is given the
      // whole face, while the one that stays has to share a screen with the
      // button that caused it.
      expect(wearToastMaxChars, greaterThan(wearErrorMaxChars));
    });
  });
}
