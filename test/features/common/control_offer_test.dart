import 'package:bambuddy_mobile/features/common/dash_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rule two screens share for a control gated on answers from the server:
/// the archive's slice button and the dashboard's plate-clear acknowledgement.
void main() {
  const yes = AsyncValue.data(true);
  const no = AsyncValue.data(false);
  const waiting = AsyncValue<bool>.loading();
  final failed = AsyncValue<bool>.error(
    StateError('unreadable'),
    StackTrace.empty,
  );

  test('every answer in and every one of them yes', () {
    expect(controlOffer([() => yes, () => yes]), ControlOffer.offered);
  });

  test('nothing to wait for when there is nothing to ask', () {
    expect(controlOffer(const []), ControlOffer.offered);
  });

  test('a control still waiting is disabled, not withdrawn', () {
    // The cold start this exists for: `/settings` has not answered, and hiding
    // the button leaves the user looking for one the server does offer.
    expect(controlOffer([() => waiting]), ControlOffer.pending);
    expect(controlOffer([() => yes, () => waiting]), ControlOffer.pending);
  });

  test('a settled no hides it', () {
    expect(controlOffer([() => no]), ControlOffer.hidden);
    expect(controlOffer([() => yes, () => no]), ControlOffer.hidden);
  });

  test('a failed read is a settled no, not a wait', () {
    // A control left greyed for the rest of the session says nothing about why
    // and offers no way to retry it.
    expect(controlOffer([() => failed]), ControlOffer.hidden);
    expect(controlOffer([() => yes, () => failed]), ControlOffer.hidden);
  });

  test('an answer already ruled out is never read', () {
    // The point of the callbacks. Reading the second answer means watching the
    // provider behind it, and in the archive that provider is an HTTP request
    // per entry the user opens — one a server with no slicer must never send.
    var read = 0;
    controlOffer([
      () => no,
      () {
        read++;
        return yes;
      },
    ]);
    expect(read, 0);
  });

  test('a question still open holds the ones behind it back too', () {
    // Same reason, one step earlier: nothing is decided yet, so the request
    // behind the next answer would be sent on a guess.
    var read = 0;
    final offer = controlOffer([
      () => waiting,
      () {
        read++;
        return no;
      },
    ]);
    expect(offer, ControlOffer.pending);
    expect(read, 0);
  });
}
