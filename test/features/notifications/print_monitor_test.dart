import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/notifications/notification_service.dart';
import 'package:bambuddy_mobile/features/notifications/print_monitor.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Nagrywa wywołania zamiast dotykać pluginu — sprawdzamy same przejścia.
class _FakeNotifications implements NotificationService {
  int ongoingCount = 0;
  int clearCount = 0;
  String? lastTitle;
  String? lastBody;
  int? lastProgress;
  final List<Map<String, Object?>> alerts = [];

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> showOngoing({
    required String title,
    required String body,
    required int progress,
  }) async {
    ongoingCount++;
    lastTitle = title;
    lastBody = body;
    lastProgress = progress;
  }

  @override
  Future<void> clearOngoing() async => clearCount++;

  @override
  Future<void> showAlert({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    alerts.add({'id': id, 'title': title, 'body': body, 'payload': payload});
  }
}

PrinterStatus _status({
  int id = 1,
  String? state,
  double? progress,
  int? remaining,
  String? job,
  String? name,
}) =>
    PrinterStatus(
      id: id,
      name: name,
      state: state,
      progress: progress,
      remainingTime: remaining,
      currentPrint: job,
    );

void main() {
  // lookupAppLocalizations w monitorze wymaga zainicjowanego bindingu.
  TestWidgetsFlutterBinding.ensureInitialized();

  // Stały zegar → deterministyczna godzina ETA w asercjach.
  PrintMonitor monitor(_FakeNotifications fake) => PrintMonitor(
        fake,
        l10n: () => lookupAppLocalizations(const Locale('en')),
        clock: () => DateTime(2026, 6, 12, 20, 0),
      );

  test('wejście w druk pokazuje wiszące powiadomienie raz; powtórka throttluje',
      () {
    final fake = _FakeNotifications();
    final m = monitor(fake);

    final frame = {
      1: _status(state: 'RUNNING', progress: 42, remaining: 80, job: 'cube.3mf'),
    };
    m.update(frame);
    expect(fake.ongoingCount, 1);
    expect(fake.lastTitle, 'cube.3mf');
    expect(fake.lastProgress, 42);
    // 20:00 + 80 min → godzina zakończenia 21:20 (nie „za X").
    expect(fake.lastBody, contains('ETA 21:20'));

    // Ta sama ramka (bez zmiany %/ETA) → bez dodatkowej aktualizacji.
    m.update(Map.of(frame));
    expect(fake.ongoingCount, 1);
  });

  test('zmiana postępu aktualizuje powiadomienie', () {
    final fake = _FakeNotifications();
    final m = monitor(fake);
    m.update({1: _status(state: 'RUNNING', progress: 42, remaining: 80)});
    m.update({1: _status(state: 'RUNNING', progress: 43, remaining: 79)});
    expect(fake.ongoingCount, 2);
    expect(fake.lastProgress, 43);
  });

  test('RUNNING → FINISH: jeden alert „skończone" i sprzątnięcie', () {
    final fake = _FakeNotifications();
    final m = monitor(fake);
    m.update({1: _status(state: 'RUNNING', progress: 99, remaining: 1, job: 'x')});
    m.update({1: _status(state: 'FINISH', progress: 100, remaining: 0, job: 'x')});

    expect(fake.alerts.length, 1);
    expect(fake.alerts.single['title'], 'Print finished');
    expect(fake.alerts.single['body'], 'x is done');
    expect(fake.clearCount, greaterThanOrEqualTo(1));

    // Kolejne ramki FINISH nie odpalają alertu ponownie.
    m.update({1: _status(state: 'FINISH', progress: 100, remaining: 0, job: 'x')});
    expect(fake.alerts.length, 1);
  });

  test('RUNNING → FAILED: alert „nieudane"', () {
    final fake = _FakeNotifications();
    final m = monitor(fake);
    m.update({1: _status(state: 'RUNNING', progress: 30, remaining: 50, job: 'y')});
    m.update({1: _status(state: 'FAILED', progress: 30, remaining: 0, job: 'y')});
    expect(fake.alerts.single['title'], 'Print failed');
    expect(fake.alerts.single['body'], 'y failed');
  });

  test('dwie drukarki: wiszące dla najbliższego ETA, z dopiskiem +1', () {
    final fake = _FakeNotifications();
    final m = monitor(fake);
    m.update({
      1: _status(id: 1, state: 'RUNNING', progress: 10, remaining: 200, job: 'long'),
      2: _status(id: 2, state: 'RUNNING', progress: 80, remaining: 15, job: 'soon'),
    });
    expect(fake.lastTitle, 'soon'); // kończy się najwcześniej
    expect(fake.lastProgress, 80);
    expect(fake.lastBody, contains('+1'));
  });

  test('koniec wszystkich wydruków sprząta wiszące powiadomienie', () {
    final fake = _FakeNotifications();
    final m = monitor(fake);
    m.update({1: _status(state: 'RUNNING', progress: 50, remaining: 30)});
    expect(fake.clearCount, 0);
    m.update({1: _status(state: 'IDLE', progress: 0, remaining: 0)});
    expect(fake.clearCount, 1);
  });
}
