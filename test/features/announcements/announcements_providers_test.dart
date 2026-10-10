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

AnnouncementFeed _feed({bool read = false}) => AnnouncementFeed.fromJson({
  'visible': true,
  'announcements': [
    {
      'id': 'a',
      'level': 'info',
      'texts': {
        'en': {'title': 'T', 'body': 'B'},
      },
      'read': read,
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
    repo.fetches.single.complete(_feed());
    await container.read(announcementsProvider.future);
  });

  AnnouncementsNotifier notifier() =>
      container.read(announcementsProvider.notifier);
  bool unread() =>
      container.read(announcementsProvider).requireValue.unreadCount > 0;

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

  test('a failed read is rolled back, then re-read', () async {
    final reading = notifier().markRead('a');
    expect(unread(), isFalse);

    repo.writes.single.completeError(
      const NetworkException(AppErrorCode.serverUnreachable),
    );
    await reading;
    expect(unread(), isTrue);

    // The re-read failing too leaves the rolled-back inbox in place.
    repo.fetches.last.completeError(
      const NetworkException(AppErrorCode.serverUnreachable),
    );
    await Future<void>.delayed(Duration.zero);
    expect(unread(), isTrue);
  });
}
