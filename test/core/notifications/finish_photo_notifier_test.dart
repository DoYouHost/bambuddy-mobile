import 'dart:async';

import 'package:bambuddy_mobile/core/api/ws_messages.dart';
import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/notifications/finish_alert_memory.dart';
import 'package:bambuddy_mobile/core/notifications/finish_photo_notifier.dart';
import 'package:bambuddy_mobile/core/notifications/notification_prefs.dart';
import 'package:bambuddy_mobile/core/notifications/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records alerts instead of touching the plugin.
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

Archive _archive({
  int id = 82,
  int? printerId = 3,
  List<String> photos = const [],
  DateTime? completedAt,
  DateTime? createdAt,
}) => Archive(
  id: id,
  filename: 'a.gcode',
  status: 'completed',
  printerId: printerId,
  photos: photos,
  // Same moment as the alert by default: this is the print that just finished.
  completedAt: completedAt ?? _now.subtract(const Duration(minutes: 1)),
  createdAt: createdAt,
);

PostedAlert _alert({
  NotifEvent event = NotifEvent.printFinished,
  int printerId = 3,
  DateTime? postedAt,
}) => PostedAlert(
  event: event,
  printerId: printerId,
  id: 1000 + printerId,
  title: 'Print finished',
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

  /// Fires during the picture fetch — where the test slips in whatever the user
  /// might do over those dozen-odd seconds.
  void Function()? duringPictureFetch;

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
    duringPictureFetch = null;
  });

  tearDown(() => frames.close());

  /// Starts the notifier, sends a frame and waits for handling to finish.
  Future<FinishPhotoNotifier> send(WsArchiveUpdated frame) async {
    final notifier = FinishPhotoNotifier(
      updates: frames.stream,
      fetchArchive: (id) async {
        archiveFetches++;
        return archive;
      },
      recentArchives: (printerId) async {
        newestFetches++;
        return [if (newest != null) newest!];
      },
      fetchPicture: (id, filename) async {
        pictureFetches++;
        duringPictureFetch?.call();
        return picture;
      },
      notifications: notifications,
      memory: memory,
      isEnabled: () => enabled,
      clock: () => _now,
    )..start();
    frames.add(frame);
    // Two turns of the event loop: one to deliver the frame, one for the chain of
    // async handling steps.
    await Future<void>.delayed(Duration.zero);
    await notifier.stop();
    return notifier;
  }

  const photoFrame = WsArchiveUpdated(82, photoAdded: 'finish_1.jpg');

  /// One archive polling pass — what the timer does in the background.
  Future<void> pollOnce({DateTime? now}) async {
    final notifier = FinishPhotoNotifier(
      updates: frames.stream,
      fetchArchive: (id) async {
        archiveFetches++;
        return archive;
      },
      recentArchives: (printerId) async {
        newestFetches++;
        return [if (newest != null) newest!];
      },
      fetchPicture: (id, filename) async {
        pictureFetches++;
        duringPictureFetch?.call();
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

  group('FinishPhotoNotifier.runForAlert', () {
    test('picks the print by completed_at, not by the server order', () {
      // The server sorts by created_at, and a reprint reuses the old entry without
      // touching that field — so a file uploaded after it ends up at the head of the
      // list. An uploaded file never printed yet: new entry, no completed_at.
      final justUploaded = Archive(
        id: 90,
        filename: 'new.gcode',
        status: 'uploaded',
        printerId: 3,
        createdAt: _now,
      );
      final reprint = _archive(
        id: 82,
        completedAt: _now.subtract(const Duration(seconds: 30)),
        createdAt: DateTime(2026, 1, 1),
      );

      expect(
        FinishPhotoNotifier.runForAlert([justUploaded, reprint], _alert())?.id,
        82,
      );
    });

    test('nothing matches in time → null instead of a random archive', () {
      final old = _archive(
        completedAt: _now.subtract(const Duration(hours: 3)),
      );

      expect(FinishPhotoNotifier.runForAlert([old], _alert()), isNull);
    });

    test('empty list and archives without completed_at → null', () {
      expect(FinishPhotoNotifier.runForAlert(const [], _alert()), isNull);
      const neverPrinted = Archive(
        id: 90,
        filename: 'new.gcode',
        status: 'uploaded',
        printerId: 3,
      );
      expect(
        FinishPhotoNotifier.runForAlert(const [neverPrinted], _alert()),
        isNull,
      );
    });
  });

  group('FinishPhotoNotifier.finishPhotoIn', () {
    test('takes the newest server shot, not whichever comes first', () {
      // An ordinary shot is appended, an enhanced one from the timelapse is
      // prepended, and a reprint leaves the photos of earlier runs behind.
      const photos = [
        'finish_20260814_101500_aaaa.jpg', // previous run
        'finish_20260815_115900_bbbb.jpg', // this run
      ];

      expect(
        FinishPhotoNotifier.finishPhotoIn(photos),
        'finish_20260815_115900_bbbb.jpg',
      );
    });

    test('the enhanced shot (prepended) beats the earlier one', () {
      const photos = [
        'finish_20260815_120200_cccc.jpg', // enhanced, put at the head
        'finish_20260815_115900_bbbb.jpg',
      ];

      expect(
        FinishPhotoNotifier.finishPhotoIn(photos),
        'finish_20260815_120200_cccc.jpg',
      );
    });

    test('user-uploaded photos do not pass as a printer shot', () {
      expect(FinishPhotoNotifier.finishPhotoIn(const ['ab12cd34.jpg']), isNull);
      expect(
        FinishPhotoNotifier.finishPhotoIn(const [
          'ab12cd34.jpg',
          'finish_20260815_115900_bbbb.jpg',
        ]),
        'finish_20260815_115900_bbbb.jpg',
      );
    });

    test('empty list → null', () {
      expect(FinishPhotoNotifier.finishPhotoIn(const []), isNull);
    });
  });

  group('archive polling (the server does not announce an ordinary photo)', () {
    test('a photo found by polling lands on the notification', () async {
      await memory.remember(_alert());
      newest = _archive(photos: const ['finish_20260815_115900_ab12.jpg']);

      await pollOnce();

      expect(notifications.posted, hasLength(1));
      expect(notifications.posted.single['id'], 1003);
      expect(notifications.posted.single['photo'], '/tmp/finish_photo.png');
    });

    test(
      'an archive without a photo → nothing, the entry waits for the next pass',
      () async {
        await memory.remember(_alert());
        newest = _archive();

        await pollOnce();

        expect(notifications.posted, isEmpty);
        expect(pictureFetches, 0);
        expect(await memory.recall(3, _now), isNotNull);
      },
    );

    test('once attached, the next pass does nothing', () async {
      await memory.remember(_alert());
      newest = _archive(photos: const ['finish_20260815_115900_ab12.jpg']);

      await pollOnce();
      await pollOnce();

      expect(notifications.posted, hasLength(1));
    });

    test('after 15 minutes it stops looking', () async {
      await memory.remember(_alert(postedAt: _now));
      newest = _archive(photos: const ['finish_20260815_115900_ab12.jpg']);

      await pollOnce(now: _now.add(const Duration(minutes: 16)));

      expect(
        newestFetches,
        0,
        reason: 'the server will not send anything more for this print',
      );
      expect(notifications.posted, isEmpty);
    });

    test('disabled in settings → no traffic at all', () async {
      await memory.remember(_alert());
      newest = _archive();
      enabled = false;

      await pollOnce();

      expect(newestFetches, 0);
      expect(notifications.posted, isEmpty);
    });
  });

  test('attaches the photo to an alert that is still up', () async {
    await memory.remember(_alert());

    await send(photoFrame);

    expect(notifications.posted, hasLength(1));
    final post = notifications.posted.single;
    expect(post['id'], 1003, reason: 'same id → replacement, not a new one');
    expect(post['event'], NotifEvent.printFinished);
    expect(post['title'], 'Print finished');
    expect(post['body'], 'Benchy');
    expect(post['payload'], 'printer:3');
    expect(post['photo'], '/tmp/finish_photo.png');
    expect(post['thumb'], '/tmp/finish_photo_thumb.png');
  });

  test('a failed-print alert gets the photo too', () async {
    await memory.remember(_alert(event: NotifEvent.printFailed));

    await send(photoFrame);

    expect(notifications.posted.single['event'], NotifEvent.printFailed);
  });

  test('a frame without photo_added does not even touch the archive', () async {
    await memory.remember(_alert());

    await send(const WsArchiveUpdated(82));

    expect(archiveFetches, 0);
    expect(notifications.posted, isEmpty);
  });

  test('disabled in settings → nothing happens', () async {
    await memory.remember(_alert());
    enabled = false;

    await send(photoFrame);

    expect(archiveFetches, 0);
    expect(notifications.posted, isEmpty);
  });

  test('no remembered alert → does not create a new notification', () async {
    await send(photoFrame);

    expect(notifications.posted, isEmpty);
    expect(pictureFetches, 0, reason: 'no reason to fetch the picture');
  });

  test(
    'an alert older than the window → treated as a different print',
    () async {
      await memory.remember(
        _alert(postedAt: _now.subtract(const Duration(minutes: 45))),
      );

      await send(photoFrame);

      expect(notifications.posted, isEmpty);
    },
  );

  test('a notification dismissed DURING the fetch → also not resurrected', () async {
    // The fetch can take a dozen-odd seconds (Dio timeouts plus the retry after a
    // 401), and `onlyAlertOnce` only mutes an update to an existing entry — once
    // cancelled, Android counts the post as new, so it would ring a second time.
    await memory.remember(_alert());
    duringPictureFetch = () => notifications.active = false;

    await send(photoFrame);

    expect(pictureFetches, 1, reason: 'it was still up when this started');
    expect(notifications.posted, isEmpty);
    expect(await memory.recall(3, _now), isNull);
  });

  test('a notification the user dismissed → not resurrected', () async {
    await memory.remember(_alert());
    notifications.active = false;

    await send(photoFrame);

    expect(notifications.posted, isEmpty);
    expect(pictureFetches, 0);
    expect(
      await memory.recall(3, _now),
      isNull,
      reason: 'entry deleted, so the next frame will not resurrect it either',
    );
  });

  test(
    'a second frame (enhanced shot) does not post the notification twice',
    () async {
      await memory.remember(_alert());

      await send(photoFrame);
      await send(const WsArchiveUpdated(82, photoAdded: 'finish_2.jpg'));

      expect(notifications.posted, hasLength(1));
    },
  );

  test('a failed picture fetch leaves the next frame a chance', () async {
    await memory.remember(_alert());
    picture = null;

    await send(photoFrame);
    expect(notifications.posted, isEmpty);

    picture = const AlertPicture(photoPath: '/tmp/finish_photo.png');
    await send(const WsArchiveUpdated(82, photoAdded: 'finish_2.jpg'));

    expect(notifications.posted, hasLength(1));
  });

  test('an exception on one frame does not kill handling of the rest', () async {
    await memory.remember(_alert());
    // Throws before `_handle` enters its own try — this is the case that left a
    // rejected future in the chain, so no later frame was handled at all and
    // `stop()` threw in `onDestroy` before the socket was closed.
    var explode = true;
    final notifier = FinishPhotoNotifier(
      updates: frames.stream,
      fetchArchive: (id) async => archive,
      recentArchives: (printerId) async => [if (newest != null) newest!],
      fetchPicture: (id, filename) async => picture,
      notifications: notifications,
      memory: memory,
      isEnabled: () {
        if (explode) throw StateError('prefs unavailable');
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

    expect(
      notifications.posted,
      hasLength(1),
      reason: 'the chain is still alive',
    );
    await expectLater(notifier.stop(), completes);
  });

  test(
    'an archive without a printer → does not guess which alert it matches',
    () async {
      await memory.remember(_alert());
      archive = _archive(printerId: null);

      await send(photoFrame);

      expect(notifications.posted, isEmpty);
    },
  );
}
