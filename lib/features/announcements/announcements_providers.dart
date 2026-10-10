import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/announcement.dart';
import '../../providers.dart';

final announcementsProvider =
    AsyncNotifierProvider.autoDispose<AnnouncementsNotifier, AnnouncementFeed>(
      AnnouncementsNotifier.new,
    );

/// The maintainers' inbox, kept by the dashboard for the drawer's dot and
/// count. Re-read as the web's query is: every 10 minutes (the server itself
/// only goes to GitHub every few hours), when the server announces a change,
/// and on every regained contact — the web's refetch on window focus.
class AnnouncementsNotifier extends AutoDisposeAsyncNotifier<AnnouncementFeed> {
  static const pollEvery = Duration(minutes: 10);

  @override
  Future<AnnouncementFeed> build() async {
    if (ref.watch(serverProfileProvider) == null) {
      return AnnouncementFeed.hidden;
    }
    ref.listen(announcementsChangedProvider, (_, _) => unawaited(refresh()));
    ref.listen(serverContactEpochProvider, (_, _) => unawaited(refresh()));
    final timer = Timer.periodic(pollEvery, (_) => unawaited(refresh()));
    ref.onDispose(timer.cancel);
    return ref.read(announcementsRepositoryProvider).fetch();
  }

  /// Bumped by every local write, so a re-read sent before it cannot land
  /// after it and bring back what the user just read.
  int _writes = 0;

  /// Keeps the inbox on screen while it loads; a failed re-read keeps the
  /// last one rather than dropping the entry.
  Future<void> refresh() async {
    if (ref.read(serverProfileProvider) == null) return;
    final writesBefore = _writes;
    final next = await AsyncValue.guard(
      () => ref.read(announcementsRepositoryProvider).fetch(),
    );
    if (_writes != writesBefore) return;
    if (next.hasValue || !state.hasValue) state = next;
  }

  /// Read at once, here and on the server — so it is read on the web too. A
  /// failed write is rolled back and the inbox re-read, as the web's is.
  Future<void> markRead(String id) => _markRead({id});

  /// The server has no bulk route, so one write per unread message, in turn.
  Future<void> markAllRead() async {
    final feed = state.valueOrNull;
    if (feed == null) return;
    await _markRead({
      for (final a in feed.items)
        if (a.unread) a.id,
    });
  }

  Future<void> _markRead(Set<String> ids) async {
    final feed = state.valueOrNull;
    if (feed == null || ids.isEmpty) return;
    final optimistic = feed.markedRead(ids);
    _writes++;
    state = AsyncData(optimistic);
    try {
      for (final id in ids) {
        await ref.read(announcementsRepositoryProvider).markRead(id);
      }
    } catch (e) {
      // Back to what it was unless something newer replaced it meanwhile; the
      // re-read then settles which of [ids] the server did record.
      if (identical(state.valueOrNull, optimistic)) state = AsyncData(feed);
      _writes++;
      unawaited(refresh());
      if (e is! AppApiException) rethrow;
    }
  }
}
