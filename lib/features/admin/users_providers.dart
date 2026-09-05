import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/models/current_user.dart';
import '../../core/models/group_summary.dart';
import '../../core/models/user_items_count.dart';
import '../../core/models/user_write.dart';
import '../../providers.dart';

/// The account list behind the administration screen. Rebuilt on a profile
/// change like every other server-backed list.
final usersListProvider =
    AutoDisposeAsyncNotifierProvider<UsersListNotifier, List<CurrentUser>>(
  UsersListNotifier.new,
);

class UsersListNotifier extends AutoDisposeAsyncNotifier<List<CurrentUser>> {
  @override
  Future<List<CurrentUser>> build() async {
    ref.watch(serverProfileProvider);
    return ref.read(usersRepositoryProvider).list();
  }

  Future<void> refresh() async {
    state =
        const AsyncValue<List<CurrentUser>>.loading().copyWithPrevious(state);
    state =
        await AsyncValue.guard(() => ref.read(usersRepositoryProvider).list());
  }
}

/// What one account owns. Asked per account rather than for the whole list —
/// it is one request each, and only the account someone opened needs it.
final userItemsCountProvider =
    FutureProvider.autoDispose.family<UserItemsCount, int>(
  (ref, userId) => ref.watch(usersRepositoryProvider).itemsCount(userId),
);

/// Whether the signed-in identity may see the account list at all.
final canReadUsersProvider = Provider<bool>(
  (ref) => ref.watch(identifiedPermissionProvider(Permissions.usersRead)),
);

/// Whether this identity may create, edit and delete accounts.
///
/// Every write carries `RequireAdminIfAuthEnabled` *on top of* its `users:*`
/// permission (`backend/app/api/routes/users.py::list_users`, `:212`, `:363`),
/// so the admin flag is the deciding one — a custom group granting
/// `users:create` without the role still gets a 403. Reading is a lower bar and
/// stays separate ([canReadUsersProvider]).
final canManageUsersProvider = Provider<bool>((ref) {
  if (!ref.watch(canReadUsersProvider)) return false;
  return ref.watch(currentUserProvider).valueOrNull?.isAdmin ?? false;
});

/// The groups an account can be put in. Failure degrades to an empty list:
/// the membership picker disappears and the rest of the form still saves,
/// which beats blocking an edit because `groups:read` was refused.
final groupOptionsProvider = FutureProvider.autoDispose<List<GroupSummary>>(
  (ref) async {
    ref.watch(serverProfileProvider);
    try {
      return await ref.read(groupsRepositoryProvider).list();
    } on AppApiException {
      return const [];
    }
  },
);

/// Whether the server generates and mails the password — what decides the
/// shape of the account form. Never fails: the repository falls back to the
/// classic shape.
final advancedAuthStatusProvider =
    FutureProvider.autoDispose<AdvancedAuthStatus>((ref) {
  ref.watch(serverProfileProvider);
  return ref.read(usersRepositoryProvider).advancedAuthStatus();
});

