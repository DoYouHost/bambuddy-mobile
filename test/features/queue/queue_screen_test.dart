import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:bambuddy_mobile/features/queue/queue_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Fake notifier — zwraca podaną listę bez dotykania repozytorium/sieci.
class _FakeQueueNotifier extends QueueNotifier {
  _FakeQueueNotifier(this._items);

  final List<QueueItem> _items;

  @override
  Future<List<QueueItem>> build() async => _items;
}

Widget _screen(List<QueueItem> items) => ProviderScope(
      overrides: [
        queueProvider.overrideWith(() => _FakeQueueNotifier(items)),
        noServerProfileOverride,
      ],
      child: plApp(const QueueScreen()),
    );

void main() {
  testWidgets('renderuje kartę kolejki: nazwa, status i drukarka z fixture\'a',
      (tester) async {
    final item = QueueItem.fromJson(
        readFixture('queue_item.json') as Map<String, dynamic>);

    await tester.pumpWidget(_screen([item]));
    await tester.pumpAndSettle();

    expect(find.text('Multi-material drawer fronts - Plate 4'), findsOneWidget);
    expect(find.text('Drukuje'), findsOneWidget, reason: 'status printing → pl');
    expect(find.textContaining('X2D-3DP'), findsOneWidget);
  });

  testWidgets('pusta kolejka pokazuje komunikat', (tester) async {
    await tester.pumpWidget(_screen(const []));
    await tester.pumpAndSettle();

    expect(find.text('Kolejka jest pusta'), findsOneWidget);
  });

  testWidgets('brak FAB gdy w kolejce są tylko wydruki drukowane',
      (tester) async {
    final json = readFixture('queue_item.json') as Map<String, dynamic>;
    final printing = QueueItem.fromJson({...json, 'status': 'printing'});

    await tester.pumpWidget(_screen([printing]));
    await tester.pumpAndSettle();

    expect(find.text('Uruchom następny'), findsNothing);
  });

  testWidgets('FAB „Uruchom następny" widoczny gdy są oczekujące wydruki',
      (tester) async {
    final json = readFixture('queue_item.json') as Map<String, dynamic>;
    final pending = QueueItem.fromJson({...json, 'status': 'pending'});

    await tester.pumpWidget(_screen([pending]));
    await tester.pumpAndSettle();

    expect(find.text('Uruchom następny'), findsOneWidget);
  });

  testWidgets('swipe na elemencie oczekującym ujawnia potwierdzenie usunięcia',
      (tester) async {
    // Element drukujący jest przypięty (bez Dismissible) — do swipe potrzebny
    // element reorderowalny, więc nadpisujemy status na „pending".
    final json = readFixture('queue_item.json') as Map<String, dynamic>;
    final item = QueueItem.fromJson({...json, 'status': 'pending'});

    await tester.pumpWidget(_screen([item]));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Usunąć z kolejki?'), findsOneWidget);
  });
}
