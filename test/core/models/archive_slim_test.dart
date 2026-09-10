import 'package:bambuddy_mobile/core/models/archive_slim.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the row the statistics aggregate', () {
    final slim = ArchiveSlim.fromJson(const {
      'status': 'completed',
      'created_at': '2026-03-12T13:00:00',
      'started_at': '2026-03-12T14:00:00',
      'printer_id': 3,
      'print_name': 'benchy',
      'print_time_seconds': 1200,
      'actual_time_seconds': 900,
      'filament_used_grams': 12.5,
      'filament_type': 'PLA',
      'filament_color': '#AABBCC',
      'quantity': 2,
    });

    expect(slim.status, 'completed');
    expect(slim.printerId, 3);
    expect(slim.printName, 'benchy');
    expect(slim.runSeconds, 900);
    expect(slim.effectiveSeconds, 900);
    expect(slim.quantity, 2);
    // The server sends UTC without the `Z`; reading it as local time would
    // move the run into the wrong day on every heatmap.
    expect(slim.createdAt.toUtc(), DateTime.utc(2026, 3, 12, 13));
    expect(slim.startedAt?.toUtc(), DateTime.utc(2026, 3, 12, 14));
  });

  test('falls back to the slicer estimate when nothing was measured', () {
    final slim = ArchiveSlim.fromJson(const {
      'status': 'failed',
      'created_at': '2026-03-12T13:00:00',
      'print_time_seconds': 1200,
    });

    expect(slim.runSeconds, isNull);
    expect(slim.effectiveSeconds, 1200);
  });

  test('an empty row parses instead of throwing', () {
    final slim = ArchiveSlim.fromJson(const {});

    expect(slim.status, 'unknown');
    expect(slim.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
    expect(slim.quantity, 1);
    expect(slim.isSuccess, isFalse);
  });

  test('an odd value costs its own field, not the listing', () {
    // The payload is assembled per row from a query, so one column arriving as
    // a number must cost that field alone — the raw cast this model used threw
    // instead, taking the whole statistics screen down with it.
    final slim = ArchiveSlim.fromJson(const {
      'status': 42,
      'created_at': '2026-03-12T13:00:00',
      'print_name': 7,
      'filament_type': 1.5,
      'filament_color': 0,
      'printer_id': '3',
      'quantity': '2',
    });

    expect(slim.status, 'unknown');
    expect(slim.printName, isNull);
    expect(slim.filamentType, isNull);
    expect(slim.filamentColor, isNull);
    expect(slim.primaryColor, isNull);
    expect(slim.printerId, 3);
    expect(slim.quantity, 2);
  });
}
