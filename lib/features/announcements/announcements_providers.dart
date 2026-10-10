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

  /// Writes started so far, and those still waiting for the server. A re-read
  /// that overlapped one may carry the server's state from before it
  /// committed, so its answer is dropped.
  int _writes = 0;
  int _writesInFlight = 0;

  /// Keeps the inbox on screen while it loads; a failed re-read keeps the
  /// last one rather than dropping the entry.
  Future<void> refresh() async {
    if (ref.read(serverProfileProvider) == null) return;
    final writesBefore = _writes;
    final overlapped = _writesInFlight > 0;
    final next = await AsyncValue.guard(
      () => ref.read(announcementsRepositoryProvider).fetch(),
    );
    if (overlapped || _writes != writesBefore) return;
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
    final recorded = <String>{};
    _writes++;
    _writesInFlight++;
    state = AsyncData(optimistic);
    try {
      for (final id in ids) {
        await ref.read(announcementsRepositoryProvider).markRead(id);
        recorded.add(id);
      }
    } catch (e) {
      _writesInFlight--;
      // Back to what it was, less what the server already took, unless
      // something newer replaced it meanwhile.
      if (identical(state.valueOrNull, optimistic)) {
        state = AsyncData(feed.markedRead(recorded));
      }
      unawaited(refresh());
      if (e is! AppApiException) rethrow;
      return;
    }
    _writesInFlight--;
  }
}
