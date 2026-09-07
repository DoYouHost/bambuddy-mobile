import 'package:bambuddy_mobile/core/models/scheduled_drying.dart';
import 'package:bambuddy_mobile/features/dashboard/scheduled_drying_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ScheduledDrying row({
    required int id,
    int printerId = 3,
    int amsId = 1,
    String status = 'pending',
  }) => ScheduledDrying(
    id: id,
    printerId: printerId,
    amsId: amsId,
    temp: 65,
    durationHours: 8,
    filament: 'PETG',
    rotateTray: false,
    status: status,
  );

  test('a card sees its own printer and its own AMS unit', () {
    final all = [row(id: 1), row(id: 2, printerId: 4), row(id: 3, amsId: 0)];

    final mine = scheduledDryingsFor(all, printerId: 3, amsId: 1);

    expect(mine.map((r) => r.id), [1]);
  });

  /// A live run already has the AMS's own countdown beside it on the card; a
  /// banner repeating it would say the same thing twice.
  test('a run that is already going is not banner material', () {
    final all = [row(id: 1, status: 'running'), row(id: 2)];

    expect(scheduledDryingsFor(all, printerId: 3, amsId: 1).map((r) => r.id), [
      2,
    ]);
  });

  /// Dispatch is the only place a run can fail, and the row is the only thing
  /// that says so — without it the schedule just disappears.
  test('a failed run stays until it is dismissed', () {
    final all = [row(id: 1, status: 'failed')];

    expect(scheduledDryingsFor(all, printerId: 3, amsId: 1).map((r) => r.id), [
      1,
    ]);
  });

  test('nothing scheduled is nothing shown', () {
    expect(scheduledDryingsFor(const [], printerId: 3, amsId: 1), isEmpty);
  });
}
