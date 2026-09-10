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
    expect(controlOffer([yes, yes]), ControlOffer.offered);
  });

  test('nothing to wait for when there is nothing to ask', () {
    expect(controlOffer(const []), ControlOffer.offered);
  });

  test('a control still waiting is disabled, not withdrawn', () {
    // The cold start this exists for: `/settings` has not answered, and hiding
    // the button leaves the user looking for one the server does offer.
    expect(controlOffer([waiting]), ControlOffer.pending);
    expect(controlOffer([yes, waiting]), ControlOffer.pending);
  });

  test('a settled no wins over an answer still on its way', () {
    // Otherwise the button flashes up disabled on every screen that shows it,
    // on a server that will never enable it.
    expect(controlOffer([no, waiting]), ControlOffer.hidden);
    expect(controlOffer([waiting, no]), ControlOffer.hidden);
  });

  test('a failed read is a settled no, not a wait', () {
    // A control left greyed for the rest of the session says nothing about why
    // and offers no way to retry it.
    expect(controlOffer([failed]), ControlOffer.hidden);
    expect(controlOffer([yes, failed]), ControlOffer.hidden);
  });
}
