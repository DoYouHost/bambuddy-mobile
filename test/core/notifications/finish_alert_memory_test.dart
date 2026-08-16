import 'package:bambuddy_mobile/core/notifications/finish_alert_memory.dart';
import 'package:bambuddy_mobile/core/notifications/notification_prefs.dart';
import 'package:bambuddy_mobile/core/notifications/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNotifications implements NotificationService {
  final posted = <int>[];

  @override
  Future<void> showAlert({
    required NotifEvent event,
    required int printerId,
    required int id,
    required String title,
    required String body,
    String? payload,
    List<NotificationAction>? actions,
    AlertPicture? picture,
  }) async => posted.add(id);

  @override
  Future<bool> isAlertActive(int id) async => true;
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> showOngoing({
    required String title,
    required String body,
    required int progress,
  }) async {}
  @override
  Future<void> clearOngoing() async {}
}

final _now = DateTime(2026, 8, 15, 12);

PostedAlert _alert({
  NotifEvent event = NotifEvent.printFinished,
  int printerId = 3,
  DateTime? postedAt,
}) => PostedAlert(
  event: event,
  printerId: printerId,
  id: 1000 + printerId,
  title: 'Wydruk zakończony',
  body: 'Benchy',
  payload: 'printer:$printerId',
  postedAt: postedAt ?? _now,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late FinishAlertMemory memory;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    memory = FinishAlertMemory(prefs);
  });

  group('FinishAlertMemory', () {
    test('zapamiętuje alert i oddaje go z kompletem pól', () async {
      await memory.remember(_alert());

      final recalled = await memory.recall(3, _now);
      expect(recalled, isNotNull);
      expect(recalled!.id, 1003);
      expect(recalled.event, NotifEvent.printFinished);
      expect(recalled.title, 'Wydruk zakończony');
      expect(recalled.body, 'Benchy');
      expect(recalled.payload, 'printer:3');
      expect(recalled.postedAt, _now);
    });

    test('trzyma osobny wpis na drukarkę', () async {
      await memory.remember(_alert(printerId: 1));
      await memory.remember(_alert(printerId: 2));

      expect((await memory.recall(1, _now))!.id, 1001);
      expect((await memory.recall(2, _now))!.id, 1002);
    });

    test('zdarzenia inne niż koniec wydruku nie są zapamiętywane', () async {
      await memory.remember(_alert(event: NotifEvent.printStarted));
      await memory.remember(_alert(event: NotifEvent.maintenanceDue));

      expect(await memory.recall(3, _now), isNull);
    });

    test('wpis starszy niż okno nie jest oddawany', () async {
      await memory.remember(_alert());

      expect(await memory.recall(3, _now.add(const Duration(minutes: 19))),
          isNotNull);
      expect(await memory.recall(3, _now.add(const Duration(minutes: 21))),
          isNull);
    });

    test('nowy alert sprząta przeterminowane wpisy innych drukarek', () async {
      await memory.remember(_alert(printerId: 1));
      await memory.remember(
        _alert(printerId: 2, postedAt: _now.add(const Duration(hours: 1))),
      );

      // Wpis drukarki 1 wypadł przy zapisie drugiego, więc nie odżyje nawet
      // w oknie liczonym od własnego czasu.
      expect(await memory.recall(1, _now), isNull);
      expect(
        await memory.recall(2, _now.add(const Duration(hours: 1))),
        isNotNull,
      );
    });

    test('forget usuwa tylko wskazaną drukarkę', () async {
      await memory.remember(_alert(printerId: 1));
      await memory.remember(_alert(printerId: 2));

      await memory.forget(1);

      expect(await memory.recall(1, _now), isNull);
      expect(await memory.recall(2, _now), isNotNull);
    });

    test('uszkodzony wpis w prefs nie wywraca odczytu', () async {
      SharedPreferences.setMockInitialValues({
        'finish_alert_last': 'to nie jest JSON',
      });
      final broken = FinishAlertMemory(await SharedPreferences.getInstance());

      expect(await broken.recall(3, _now), isNull);
    });

    test('wpis o nieznanym zdarzeniu jest pomijany, reszta zostaje', () async {
      SharedPreferences.setMockInitialValues({
        'finish_alert_last':
            '{"1":{"event":"nowyTypZPrzyszlosci","printerId":1,"id":1,'
            '"postedAt":1},'
            '"3":{"event":"printFinished","printerId":3,"id":1003,'
            '"title":"t","body":"b","postedAt":${_now.millisecondsSinceEpoch}}}',
      });
      final mixed = FinishAlertMemory(await SharedPreferences.getInstance());

      expect(await mixed.recall(1, _now), isNull);
      expect((await mixed.recall(3, _now))!.id, 1003);
    });
  });

  group('RememberingNotifications', () {
    test('zapisuje alert końca wydruku i przepuszcza go dalej', () async {
      final inner = _FakeNotifications();
      final service = RememberingNotifications(inner, memory, () => _now);

      await service.showAlert(
        event: NotifEvent.printFinished,
        printerId: 3,
        id: 1003,
        title: 'Wydruk zakończony',
        body: 'Benchy',
        payload: 'printer:3',
      );

      expect(inner.posted, [1003]);
      expect((await memory.recall(3, _now))!.id, 1003);
    });

    test('alert innego typu przechodzi, ale nie jest zapamiętywany', () async {
      final service = RememberingNotifications(
        _FakeNotifications(),
        memory,
        () => _now,
      );

      await service.showAlert(
        event: NotifEvent.printStarted,
        printerId: 3,
        id: 7,
        title: 't',
        body: 'b',
      );

      expect(await memory.recall(3, _now), isNull);
    });

    test('post ze zdjęciem to już aktualizacja — nie uzbraja się ponownie',
        () async {
      final service = RememberingNotifications(
        _FakeNotifications(),
        memory,
        () => _now,
      );

      await service.showAlert(
        event: NotifEvent.printFinished,
        printerId: 3,
        id: 1003,
        title: 't',
        body: 'b',
        picture: const AlertPicture(photoPath: '/tmp/x.png'),
      );

      expect(await memory.recall(3, _now), isNull);
    });
  });
}
