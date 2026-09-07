import 'package:bambuddy_mobile/core/models/json_utils.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// The scheduled print time must round-trip fully without drift.
///
/// Regression from 2026-07-30, found in an emulator log on `Europe/Warsaw`:
/// saving was correct (local `DateTime(...)` → `.toUtc()`), but reading gave
/// back a DateTime **in UTC**, and the form read `d.hour` off it directly. The
/// effect: an item saved at 18:00 showed as 16:00, and saving without touching
/// anything drifted to 14:00Z — i.e. every time you opened the edit screen the
/// print shifted by the zone offset. Not a display typo, but data corruption
/// in the loop.
///
/// **Note on the test machine's timezone.** The hour assertions only have
/// power with a nonzero offset — on a host in UTC, local time and UTC are the
/// same number, so there is no way to catch a bug like this. Verified: on
/// `Europe/Warsaw` this whole file fails on the pre-fix code
/// (`Expected: <18> Actual: <16>`). The zone-independent assertion is
/// `isUtc, isFalse` in `json_utils_test.dart` — that one catches half of "we
/// hand back UTC" everywhere, because `toLocal()` always clears that flag.
void main() {
  /// What the edit screen sends: `_scheduledTimeIso`.
  String outbound(DateTime picked) => picked.toUtc().toIso8601String();

  /// What the edit screen reads from an item from the server.
  DateTime inbound(String fromServer) => QueueItem.fromJson({
    'id': 1,
    'position': 1,
    'status': 'pending',
    'scheduled_time': fromServer,
  }).scheduledTime!;

  test('a chosen hour comes back as the same hour', () {
    // 18:00 local time, however the device's zone is set.
    final picked = DateTime(2026, 7, 30, 18);

    final stored = outbound(picked);
    final reopened = inbound(stored);

    expect(reopened.hour, 18, reason: 'the form reads .hour directly');
    expect(reopened.minute, 0);
    expect(reopened, picked);
  });

  test('editing and saving without changes does not shift the time', () {
    // This is the loop: every turn kept adding the zone offset.
    var wire = outbound(DateTime(2026, 7, 30, 18));

    for (var round = 0; round < 3; round++) {
      final shown = inbound(wire);
      expect(shown.hour, 18, reason: 'round $round');
      // The form rebuilds the value from the picker's fields — the same as
      // after tapping "Save" without touching the hour.
      wire = outbound(
        DateTime(shown.year, shown.month, shown.day, shown.hour, shown.minute),
      );
    }

    expect(inbound(wire), DateTime(2026, 7, 30, 18));
  });

  test('a naive value from the server is the same instant as one with Z', () {
    // ArchiveResponse doesn't append Z, PrintQueueItemResponse does. The same
    // moment in two encodings must not give two different hours on screen.
    expect(
      dateTimeFromJson('2026-07-30T16:00:00'),
      dateTimeFromJson('2026-07-30T16:00:00Z'),
    );
  });

  test('a broken PATCH response does not drop the schedule', () {
    // The server answers `+00:00Z` on PATCH; if something started reading that
    // body instead of doing a refetch, the schedule would go null and the
    // print would look like ASAP.
    final item = QueueItem.fromJson({
      'id': 182,
      'position': 1,
      'status': 'pending',
      'scheduled_time': '2026-07-30T16:00:00+00:00Z',
    });

    expect(item.scheduledTime, isNotNull);
    expect(item.scheduledTime, dateTimeFromJson('2026-07-30T16:00:00Z'));
  });
}
