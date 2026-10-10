import 'dart:async';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/announcement.dart';
import 'package:bambuddy_mobile/data/announcements_repository.dart';
import 'package:bambuddy_mobile/features/announcements/announcements_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Answers each call with whatever the test completes it with, in order.
class _ScriptedRepo implements AnnouncementsRepository {
  final fetches = <Completer<AnnouncementFeed>>[];
  final writes = <Completer<void>>[];

  @override
  Future<AnnouncementFeed> fetch() {
    final c = Completer<AnnouncementFeed>();
    fetches.add(c);
    return c.future;
  }

  @override
  Future<void> markRead(String id) {
    final c = Completer<void>();
    writes.add(c);
    return c.future;
  }
}

AnnouncementFeed _feed({List<String> ids = const ['a']}) =>
    AnnouncementFeed.fromJson({
      'visible': true,
      'announcements': [
        for (final id in ids)
          {
            'id': id,
            'level': 'info',
            'texts': {
              'en': {'title': 'T', 'body': 'B'},
            },
          },
      ],
    });

void main() {
  late _ScriptedRepo repo;
  late ProviderContainer container;

  setUp(() async {
    repo = _ScriptedRepo();
    container = ProviderContainer(
      overrides: [
        fakeServerProfileOverride(),
        announcementsRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    container.listen(announcementsProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    repo.fetches.single.complete(_feed(ids: ['a', 'b']));
    await container.read(announcementsProvider.future);
  });

  AnnouncementsNotifier notifier() =>
      container.read(announcementsProvider.notifier);
  Set<String> unreadIds() => {
    for (final a in container.read(announcementsProvider).requireValue.items)
      if (a.unread) a.id,
  };
  bool unread() => unreadIds().contains('a');

  test('a re-read sent before a read cannot bring it back', () async {
    final refreshing = notifier().refresh();
    final reading = notifier().markRead('a');
    expect(unread(), isFalse);

    // The server answers the older GET with the row still unread.
    repo.fetches.last.complete(_feed());
    await refreshing;
    expect(unread(), isFalse);

    repo.writes.single.complete();
    await reading;
    expect(unread(), isFalse);
  });

  test('a re-read sent during a write cannot land after it either', () async {
    final reading = notifier().markRead('a');
    final refreshing = notifier().refresh();
    repo.writes.single.complete();
    await reading;

    // Answered before the write committed, delivered after it finished.
    repo.fetches.last.complete(_feed(ids: ['a', 'b']));
    await refreshing;
    expect(unread(), isFalse);
  });

  test('mark all keeps what the server took before one failed', () async {
    final reading = notifier().markAllRead();
    expect(unreadIds(), isEmpty);
    repo.writes[0].complete();
    await Future<void>.delayed(Duration.zero);
    repo.writes[1].completeError(
      const NetworkException(AppErrorCode.serverUnreachable),
    );
    await reading;
    expect(unreadIds(), {'b'});
  });

  test('a failed read is rolled back, then re-read', () async {
    final reading = notifier().markRead('a');
    expect(unread(), isFalse);

    repo.writes.single.completeError(
      const NetworkException(AppErrorCode.serverUnreachable),
    );
    await reading;
    expect(unread(), isTrue);

    // The re-read failing too leaves the rolled-back inbox in place.
    await Future<void>.delayed(Duration.zero);
    repo.fetches.last.completeError(
      const NetworkException(AppErrorCode.serverUnreachable),
    );
    await Future<void>.delayed(Duration.zero);
    expect(unread(), isTrue);
  });
}
