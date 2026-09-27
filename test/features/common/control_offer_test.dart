import 'package:bambuddy_mobile/features/common/dash_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rule two screens share for a control gated on an answer from the
/// server: the archive's slice button and the dashboard's plate-clear
/// acknowledgement.
void main() {
  test('the answer is in and it is yes', () {
    expect(const AsyncValue.data(true).offer, ControlOffer.offered);
  });

  test('a control still waiting is disabled, not withdrawn', () {
    // The cold start this exists for: `/settings` has not answered, and hiding
    // the button leaves the user looking for one the server does offer.
    expect(const AsyncValue<bool>.loading().offer, ControlOffer.pending);
  });

  test('a settled no hides it', () {
    expect(const AsyncValue.data(false).offer, ControlOffer.hidden);
  });

  test('a failed read is a settled no, not a wait', () {
    // A control left greyed for the rest of the session with nothing beside it
    // says neither why nor what to do about it.
    final failed = AsyncValue<bool>.error(
      StateError('unreadable'),
      StackTrace.empty,
    );

    expect(failed.offer, ControlOffer.hidden);
    expect(failed.isUnanswered, isFalse);
  });

  test('a refresh keeps the answer it already had', () {
    // Riverpod reports a reload as data carrying `isLoading`. Reading that as
    // "not answered" would disable a working control on every settings write.
    final refreshing = const AsyncValue<bool>.loading().copyWithPrevious(
      const AsyncValue.data(true),
    );

    expect(refreshing.isLoading, isTrue, reason: 'it really is a reload');
    expect(refreshing.offer, ControlOffer.offered);
  });
}
