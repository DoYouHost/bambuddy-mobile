import 'dart:async';

import 'package:bambuddy_mobile/core/api/ws_messages.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/notifications/finish_alert_memory.dart';
import 'package:bambuddy_mobile/core/notifications/finish_photo_notifier.dart';
import 'package:bambuddy_mobile/core/notifications/notification_prefs.dart';
import 'package:bambuddy_mobile/core/notifications/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Nagrywa alerty zamiast dotykać pluginu.
class _FakeNotifications implements NotificationService {
  final posted = <Map<String, Object?>>[];
  bool active = true;

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
  }) async {
    posted.add({
      'event': event,
      'printerId': printerId,
      'id': id,
      'title': title,
      'body': body,
      'payload': payload,
      'photo': picture?.photoPath,
      'thumb': picture?.thumbnailPath,
    });
  }

  @override
  Future<bool> isAlertActive(int id) async => active;

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

Archive _archive({int id = 82, int? printerId = 3}) =>
    Archive(id: id, filename: 'a.gcode', status: 'completed', printerId: printerId);

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
  postedAt: postedAt ?? _now.subtract(const Duration(minutes: 1)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late FinishAlertMemory memory;
  late _FakeNotifications notifications;
  late StreamController<WsArchiveUpdated> frames;

  int archiveFetches = 0;
  int newestFetches = 0;
  int pictureFetches = 0;
  Archive? archive;
  Archive? newest;
  AlertPicture? picture;
  bool enabled = true;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    memory = FinishAlertMemory(prefs);
    notifications = _FakeNotifications();
    frames = StreamController<WsArchiveUpdated>.broadcast();
    archiveFetches = 0;
    newestFetches = 0;
    pictureFetches = 0;
    archive = _archive();
    newest = null;
    picture = const AlertPicture(
      photoPath: '/tmp/finish_photo.png',
      thumbnailPath: '/tmp/finish_photo_thumb.png',
    );
    enabled = true;
  });

  tearDown(() => frames.close());

  /// Startuje notifier, wysyła ramkę i czeka aż obsługa się zakończy.
  Future<FinishPhotoNotifier> send(WsArchiveUpdated frame) async {
    final notifier = FinishPhotoNotifier(
      updates: frames.stream,
      fetchArchive: (id) async {
        archiveFetches++;
        return archive;
      },
      newestArchive: (printerId) async {
        newestFetches++;
        return newest;
      },
      fetchPicture: (id, filename) async {
        pictureFetches++;
        return picture;
      },
      notifications: notifications,
      memory: memory,
      isEnabled: () => enabled,
      clock: () => _now,
    )..start();
    frames.add(frame);
    // Dwa obroty pętli zdarzeń: jeden na dostarczenie ramki, drugi na łańcuch
    // asynchronicznych kroków obsługi.
    await Future<void>.delayed(Duration.zero);
    await notifier.stop();
    return notifier;
  }

  const photoFrame = WsArchiveUpdated(82, photoAdded: 'finish_1.jpg');

  /// Jeden przebieg odpytywania archiwum — to, co w tle robi timer.
  Future<void> pollOnce({DateTime? now}) async {
    final notifier = FinishPhotoNotifier(
      updates: frames.stream,
      fetchArchive: (id) async {
        archiveFetches++;
        return archive;
      },
      newestArchive: (printerId) async {
        newestFetches++;
        return newest;
      },
      fetchPicture: (id, filename) async {
        pictureFetches++;
        return picture;
      },
      notifications: notifications,
      memory: memory,
      isEnabled: () => enabled,
      clock: () => now ?? _now,
    );
    await notifier.poll();
    await notifier.stop();
  }

  group('odpytywanie archiwum (serwer nie ogłasza zwykłego zdjęcia)', () {
    test('zdjęcie znalezione przy odpytywaniu trafia na powiadomienie',
        () async {
      await memory.remember(_alert());
      newest = Archive(
        id: 82,
        filename: 'a.gcode',
        status: 'completed',
        printerId: 3,
        photos: const ['finish_1.jpg'],
      );

      await pollOnce();

      expect(notifications.posted, hasLength(1));
      expect(notifications.posted.single['id'], 1003);
      expect(notifications.posted.single['photo'], '/tmp/finish_photo.png');
    });

    test('archiwum bez zdjęcia → nic, wpis zostaje na kolejny przebieg',
        () async {
      await memory.remember(_alert());
      newest = _archive();

      await pollOnce();

      expect(notifications.posted, isEmpty);
      expect(pictureFetches, 0);
      expect(await memory.recall(3, _now), isNotNull);
    });

    test('po doklejeniu kolejny przebieg już nic nie robi', () async {
      await memory.remember(_alert());
      newest = Archive(
        id: 82,
        filename: 'a.gcode',
        status: 'completed',
        printerId: 3,
        photos: const ['finish_1.jpg'],
      );

      await pollOnce();
      await pollOnce();

      expect(notifications.posted, hasLength(1));
    });

    test('po 15 minutach przestaje szukać', () async {
      await memory.remember(_alert(postedAt: _now));
      newest = Archive(
        id: 82,
        filename: 'a.gcode',
        status: 'completed',
        printerId: 3,
        photos: const ['finish_1.jpg'],
      );

      await pollOnce(now: _now.add(const Duration(minutes: 16)));

      expect(newestFetches, 0, reason: 'serwer nie dośle już nic dla tego druku');
      expect(notifications.posted, isEmpty);
    });

    test('wyłączone w ustawieniach → zero ruchu', () async {
      await memory.remember(_alert());
      newest = _archive();
      enabled = false;

      await pollOnce();

      expect(newestFetches, 0);
      expect(notifications.posted, isEmpty);
    });
  });

  test('dokłada zdjęcie do alertu, który wciąż wisi', () async {
    await memory.remember(_alert());

    await send(photoFrame);

    expect(notifications.posted, hasLength(1));
    final post = notifications.posted.single;
    expect(post['id'], 1003, reason: 'to samo id → podmiana, nie nowe');
    expect(post['event'], NotifEvent.printFinished);
    expect(post['title'], 'Wydruk zakończony');
    expect(post['body'], 'Benchy');
    expect(post['payload'], 'printer:3');
    expect(post['photo'], '/tmp/finish_photo.png');
    expect(post['thumb'], '/tmp/finish_photo_thumb.png');
  });

  test('alert o nieudanym wydruku też dostaje zdjęcie', () async {
    await memory.remember(_alert(event: NotifEvent.printFailed));

    await send(photoFrame);

    expect(notifications.posted.single['event'], NotifEvent.printFailed);
  });

  test('ramka bez photo_added nie rusza nawet archiwum', () async {
    await memory.remember(_alert());

    await send(const WsArchiveUpdated(82));

    expect(archiveFetches, 0);
    expect(notifications.posted, isEmpty);
  });

  test('wyłączone w ustawieniach → nic się nie dzieje', () async {
    await memory.remember(_alert());
    enabled = false;

    await send(photoFrame);

    expect(archiveFetches, 0);
    expect(notifications.posted, isEmpty);
  });

  test('brak zapamiętanego alertu → nie tworzy nowego powiadomienia', () async {
    await send(photoFrame);

    expect(notifications.posted, isEmpty);
    expect(pictureFetches, 0, reason: 'nie ma po co pobierać zdjęcia');
  });

  test('alert starszy niż okno → wydruk uznany za inny', () async {
    await memory.remember(
      _alert(postedAt: _now.subtract(const Duration(minutes: 45))),
    );

    await send(photoFrame);

    expect(notifications.posted, isEmpty);
  });

  test('powiadomienie zsunięte przez usera → nie wskrzesza go', () async {
    await memory.remember(_alert());
    notifications.active = false;

    await send(photoFrame);

    expect(notifications.posted, isEmpty);
    expect(pictureFetches, 0);
    expect(
      await memory.recall(3, _now),
      isNull,
      reason: 'wpis skasowany, więc kolejna ramka też go nie wskrzesi',
    );
  });

  test('druga ramka (ulepszone ujęcie) nie wystawia powiadomienia dwa razy',
      () async {
    await memory.remember(_alert());

    await send(photoFrame);
    await send(const WsArchiveUpdated(82, photoAdded: 'finish_2.jpg'));

    expect(notifications.posted, hasLength(1));
  });

  test('nieudane pobranie zdjęcia zostawia szansę kolejnej ramce', () async {
    await memory.remember(_alert());
    picture = null;

    await send(photoFrame);
    expect(notifications.posted, isEmpty);

    picture = const AlertPicture(photoPath: '/tmp/finish_photo.png');
    await send(const WsArchiveUpdated(82, photoAdded: 'finish_2.jpg'));

    expect(notifications.posted, hasLength(1));
  });

  test('wyjątek przy jednej ramce nie zabija obsługi kolejnych', () async {
    await memory.remember(_alert());
    // Rzuca zanim `_handle` wejdzie w swój try — to ten przypadek zostawiał
    // odrzucony future w łańcuchu, przez co żadna następna ramka nie była już
    // obsłużona, a `stop()` rzucał w `onDestroy` przed zamknięciem gniazda.
    var explode = true;
    final notifier = FinishPhotoNotifier(
      updates: frames.stream,
      fetchArchive: (id) async => archive,
      newestArchive: (printerId) async => newest,
      fetchPicture: (id, filename) async => picture,
      notifications: notifications,
      memory: memory,
      isEnabled: () {
        if (explode) throw StateError('prefs niedostępne');
        return true;
      },
      clock: () => _now,
    )..start();

    frames.add(photoFrame);
    await Future<void>.delayed(Duration.zero);
    expect(notifications.posted, isEmpty);

    explode = false;
    frames.add(photoFrame);
    await Future<void>.delayed(Duration.zero);

    expect(notifications.posted, hasLength(1), reason: 'łańcuch dalej żyje');
    await expectLater(notifier.stop(), completes);
  });

  test('archiwum bez drukarki → nie zgaduje, do którego alertu to pasuje',
      () async {
    await memory.remember(_alert());
    archive = _archive(printerId: null);

    await send(photoFrame);

    expect(notifications.posted, isEmpty);
  });
}
