import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/current_user.dart';
import '../../core/models/group_summary.dart';
import '../../core/models/permission_catalog.dart';
import '../../providers.dart';

/// The groups on the server. Shares [GroupsRepository] with the account form's
/// membership picker, but keeps its own error state: this screen is *about*
/// the groups, so a refusal belongs on screen rather than degrading to an
/// empty list the way the picker does.
final groupsListProvider =
    AutoDisposeAsyncNotifierProvider<GroupsListNotifier, List<GroupSummary>>(
  GroupsListNotifier.new,
);

class GroupsListNotifier extends AutoDisposeAsyncNotifier<List<GroupSummary>> {
  @override
  Future<List<GroupSummary>> build() async {
    ref.watch(serverProfileProvider);
    return ref.read(groupsRepositoryProvider).list();
  }

  Future<void> refresh() async {
    state =
        const AsyncValue<List<GroupSummary>>.loading().copyWithPrevious(state);
    state =
        await AsyncValue.guard(() => ref.read(groupsRepositoryProvider).list());
  }
}

final groupDetailProvider = AutoDisposeAsyncNotifierProviderFamily<
    GroupDetailNotifier, GroupDetail, int>(GroupDetailNotifier.new);

/// One group with its members, keyed by id. Membership changes refresh this
/// and the list (which carries `user_count`), and the account list too — the
/// same membership is what its group chips show.
class GroupDetailNotifier
    extends AutoDisposeFamilyAsyncNotifier<GroupDetail, int> {
  @override
  Future<GroupDetail> build(int arg) async {
    ref.watch(serverProfileProvider);
    return ref.read(groupsRepositoryProvider).get(arg);
  }

  Future<void> refresh() async {
    state = const AsyncValue<GroupDetail>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(
      () => ref.read(groupsRepositoryProvider).get(arg),
    );
  }
}

/// Every permission the server knows, for the editor to build itself from.
/// Kept alive per screen rather than cached forever: the catalog grows with
/// the server, and this is read once per form.
final permissionCatalogProvider =
    FutureProvider.autoDispose<PermissionCatalog>((ref) {
  ref.watch(serverProfileProvider);
  return ref.read(groupsRepositoryProvider).permissions();
});

/// Whether the signed-in identity may see the groups at all.
final canReadGroupsProvider = Provider<bool>(
  (ref) => ref.watch(identifiedPermissionProvider(Permissions.groupsRead)),
);

/// Whether it may change who is in a group. Adding and removing a member
/// carries `RequireAdminIfAuthEnabled` on top of `groups:update`
/// (`backend/app/api/routes/groups.py:263`), so the admin flag decides.
final canManageGroupsProvider = Provider<bool>((ref) {
  if (!ref.watch(canReadGroupsProvider)) return false;
  return ref.watch(currentUserProvider).valueOrNull?.isAdmin ?? false;
});
