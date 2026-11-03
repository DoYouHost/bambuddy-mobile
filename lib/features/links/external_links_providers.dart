import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/current_user.dart';
import '../../core/models/external_link.dart';
import '../../providers.dart';

/// The server's sidebar links with the counts their apps report, kept by the
/// shell so the drawer knows whether to show its tile before it is opened
/// (`warmServerAnswers`).
///
/// Empty — and so no tile — for a session `/auth/me` says may not read them,
/// without a request, and for a server that has no such route or refuses this
/// session (`ExternalLinksRepository.fetch`). Re-read on every regained contact;
/// the drawer and the screen re-read it when they open, since a count is the
/// kind of thing that changes while the app stays in the foreground.
final externalLinksProvider = FutureProvider<List<ExternalLink>>((ref) {
  if (ref.watch(serverProfileProvider) == null) return const [];
  if (!ref.watch(permissionProvider(Permissions.externalLinksRead))) {
    return const [];
  }
  ref.watch(serverContactEpochProvider);
  return ref.watch(externalLinksRepositoryProvider).fetch();
});
