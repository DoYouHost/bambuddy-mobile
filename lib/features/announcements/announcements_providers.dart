import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/announcement.dart';
import '../../providers.dart';

final announcementsProvider =
    AsyncNotifierProvider.autoDispose<AnnouncementsNotifier, AnnouncementFeed>(
      AnnouncementsNotifier.new,
    );

/// The maintainers' inbox, kept by the dashboard for the drawer's dot and the
/// banner. Re-read as the web's query is: every 10 minutes (the server itself
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

  /// Keeps the inbox on screen while it loads; a failed re-read keeps the
  /// last one rather than dropping the entry.
  Future<void> refresh() async {
    if (ref.read(serverProfileProvider) == null) return;
    final next = await AsyncValue.guard(
      () => ref.read(announcementsRepositoryProvider).fetch(),
    );
    if (next.hasValue || !state.hasValue) state = next;
  }

  /// Read at once, here and on the server — so it is read on the web too. A
  /// refused write re-reads the inbox, as the web's does.
  Future<void> markRead(String id) async {
    final feed = state.valueOrNull;
    if (feed == null) return;
    state = AsyncData(feed.markedRead(id));
    try {
      await ref.read(announcementsRepositoryProvider).markRead(id);
    } catch (e) {
      unawaited(refresh());
      if (e is! AppApiException) rethrow;
    }
  }
}
