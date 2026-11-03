import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/api/observed_capability.dart';
import 'package:bambuddy_mobile/core/models/api_key.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/group_summary.dart';
import 'package:bambuddy_mobile/core/models/group_write.dart';
import 'package:bambuddy_mobile/core/models/permission_catalog.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/user_items_count.dart';
import 'package:bambuddy_mobile/core/models/user_write.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/data/api_keys_repository.dart';
import 'package:bambuddy_mobile/data/groups_repository.dart';
import 'package:bambuddy_mobile/data/users_repository.dart';
import 'package:bambuddy_mobile/features/admin/admin_screen.dart';
import 'package:bambuddy_mobile/features/admin/api_key_form_screen.dart';
import 'package:bambuddy_mobile/features/admin/api_keys_providers.dart';
import 'package:bambuddy_mobile/features/admin/api_keys_screen.dart';
import 'package:bambuddy_mobile/features/admin/group_detail_screen.dart';
import 'package:bambuddy_mobile/features/admin/group_form_screen.dart';
import 'package:bambuddy_mobile/features/admin/groups_screen.dart';
import 'package:bambuddy_mobile/features/admin/user_form_screen.dart';
import 'package:bambuddy_mobile/features/admin/users_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets for the administration screens: the hub,
/// accounts, groups and API keys, each with its sheets, dialogs, menus and
/// editor states. The demo backend serves no groups or API keys, so these run
/// on small in-file repositories behind an admin identity. Not covered: the
/// snackbars a write ends in (a transient overlay, and the write paths are
/// proven by the screens' own tests).
void main() {
  a11ySurface(
    'admin hub',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const AdminScreen(),
    shows: find.text(pl.apiKeysTitle),
  );

  _users();
  _groups();
  _apiKeys();
}

void _users() {
  a11ySurface(
    'users list',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const UsersScreen(),
    shows: find.text(_zosia.username),
  );

  a11ySurface(
    'users list, empty',
    demo: false,
    overrides: _adminOverrides(users: _Users(users: const [])),
    home: () => const UsersScreen(),
    shows: find.text(pl.usersEmpty),
  );

  a11ySurface(
    'users list, load failed',
    demo: false,
    overrides: _adminOverrides(users: _Users(users: const [], fails: true)),
    home: () => const UsersScreen(),
    shows: find.text(pl.retry),
  );

  a11ySurface(
    'user detail sheet',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const UsersScreen(),
    arrange: (tester) async {
      await tester.tap(find.text(_zosia.username));
      await settle(tester);
    },
    shows: find.text(pl.usersOwnedTitle),
  );

  a11ySurface(
    'user delete dialog',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const UsersScreen(),
    arrange: (tester) async {
      await tester.tap(find.text(_zosia.username));
      await settle(tester);
      await tester.tap(byLogId('user_detail.delete'));
      await settle(tester);
    },
    shows: find.text(pl.usersDeleteConfirm),
  );

  a11ySurface(
    'user form, create',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const UserFormScreen(),
    shows: find.text(pl.usersFieldPassword),
  );

  // Save on an empty form raises every "required" message at once.
  a11ySurface(
    'user form, create, validation errors',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const UserFormScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('user_form.save'));
      await settle(tester);
    },
    shows: find.text(pl.usersFieldRequired),
  );

  a11ySurface(
    'user form, create, advanced authentication without SMTP',
    demo: false,
    overrides: _adminOverrides(
      users: _Users(
        users: const [_admin, _zosia],
        advanced: const AdvancedAuthStatus(
          enabled: true,
          smtpConfigured: false,
        ),
      ),
    ),
    home: () => const UserFormScreen(),
    shows: find.text(pl.usersNoSmtpWarning),
  );

  // A typed password brings in the confirmation field.
  a11ySurface(
    'user form, edit, new password',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const UserFormScreen(existing: _zosia),
    arrange: (tester) async {
      await tester.enterText(byLogId('user_form.password'), 'Hunter2hunter2');
      await settle(tester);
    },
    shows: find.text(pl.usersFieldConfirmPassword),
  );

  a11ySurface(
    'user form, edit, directory account',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const UserFormScreen(existing: _katalog),
    shows: find.text(pl.usersLdapPasswordNote),
  );
}

void _groups() {
  a11ySurface(
    'groups list',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const GroupsScreen(),
    shows: find.text(_household.name),
  );

  a11ySurface(
    'groups list, empty',
    demo: false,
    overrides: _adminOverrides(groups: _Groups(const [])),
    home: () => const GroupsScreen(),
    shows: find.text(pl.groupsEmpty),
  );

  a11ySurface(
    'group detail',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const GroupDetailScreen(groupId: 7),
    shows: find.text(pl.groupsMembersHeader),
  );

  a11ySurface(
    'group detail, system group',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const GroupDetailScreen(groupId: 1),
    shows: find.text(pl.groupsSystemNote),
  );

  a11ySurface(
    'group detail, menu',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const GroupDetailScreen(groupId: 7),
    arrange: (tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await settle(tester);
    },
    shows: find.text(pl.groupsDelete),
  );

  a11ySurface(
    'group detail, delete dialog',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const GroupDetailScreen(groupId: 7),
    arrange: (tester) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await settle(tester);
      await tester.tap(find.text(pl.groupsDelete));
      await settle(tester);
    },
    shows: find.text(pl.groupsDeleteQuestion(_household.name)),
  );

  a11ySurface(
    'group detail, remove member dialog',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const GroupDetailScreen(groupId: 7),
    arrange: (tester) async {
      await tester.tap(byLogId('group_detail.remove_member').first);
      await settle(tester);
    },
    shows: find.text(pl.groupsRemoveMemberBody),
  );

  a11ySurface(
    'group detail, add member sheet',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const GroupDetailScreen(groupId: 7),
    arrange: (tester) async {
      await tester.tap(byLogId('group_detail.add_member'));
      await settle(tester);
    },
    shows: find.text(pl.groupsAddMemberTitle(_household.name)),
  );

  a11ySurface(
    'group form, create',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const GroupFormScreen(),
    shows: find.text(pl.groupsPermissionsHeader),
  );

  // Every category open, the folded-away ones included: that is where the
  // checkbox rows and their mono subtitles are.
  a11ySurface(
    'group form, edit, categories open',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const GroupFormScreen(existing: _household),
    arrange: (tester) async {
      await tester.tap(byLogId('group_form.advanced'));
      await settle(tester);
      final categories = byLogId('group_form.category');
      for (var i = categories.evaluate().length - 1; i >= 0; i--) {
        await tester.tap(categories.at(i));
        await settle(tester);
      }
    },
    shows: find.text('View queue'),
  );

  a11ySurface(
    'group form, edit, system group locked',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const GroupFormScreen(existing: _administrators),
    shows: find.text(pl.groupsSystemFormNote),
  );

  a11ySurface(
    'group form, validation errors',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const GroupFormScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('group_form.save'));
      await settle(tester);
    },
    shows: find.text(pl.usersFieldRequired),
  );
}

void _apiKeys() {
  a11ySurface(
    'api keys list',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const ApiKeysScreen(),
    shows: find.text(_homeAssistant.name),
  );

  a11ySurface(
    'api keys list, empty',
    demo: false,
    overrides: _adminOverrides(keys: _Keys(const [])),
    home: () => const ApiKeysScreen(),
    shows: find.text(pl.apiKeysEmpty),
  );

  a11ySurface(
    'api key revoke dialog',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const ApiKeysScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('api_keys.revoke').first);
      await settle(tester);
    },
    shows: find.text(pl.apiKeysRevokeBody),
  );

  a11ySurface(
    'api key form, create',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const ApiKeyFormScreen(),
    shows: find.text(pl.apiKeysScopesHeader),
  );

  a11ySurface(
    'api key form, create, validation error',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const ApiKeyFormScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('api_key_form.save'));
      await settle(tester);
    },
    shows: find.text(pl.usersFieldRequired),
  );

  // Edit: enabled switch, printer chips of a restricted key, an expiry with its
  // clear button, and the notification scope the key already holds.
  a11ySurface(
    'api key form, edit',
    demo: false,
    overrides: _adminOverrides(),
    home: () => ApiKeyFormScreen(existing: _homeAssistant),
    shows: find.text(pl.apiKeysFieldEnabled),
  );

  a11ySurface(
    'api key form, expiry date picker',
    demo: false,
    overrides: _adminOverrides(),
    home: () => const ApiKeyFormScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('api_key_form.expiry'));
      await settle(tester);
    },
    shows: find.byType(DatePickerDialog),
  );

  // The real flow: form, name, save, then the one-time key dialog.
  a11ySurface(
    'api key created dialog',
    demo: false,
    overrides: _adminOverrides(),
    home: () => A11yLauncher(openApiKeyCreate),
    arrange: (tester) async {
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.enterText(byLogId('api_key_form.name'), 'SpoolBuddy');
      await tester.tap(byLogId('api_key_form.save'));
      await settle(tester);
    },
    shows: find.text(pl.apiKeysCreatedTitle),
  );
}

const _admin = CurrentUser(
  id: 1,
  username: 'admin',
  email: 'admin@home.lan',
  isAdmin: true,
  groups: [UserGroup(id: 1, name: 'Administrators')],
  permissions: {'users:read', 'groups:read', 'api_keys:read'},
);

const _zosia = CurrentUser(
  id: 2,
  username: 'zosia',
  email: 'zosia@home.lan',
  isAdmin: false,
  isActive: false,
  groups: [UserGroup(id: 7, name: 'Domownicy')],
  permissions: {'queue:read'},
);

const _katalog = CurrentUser(
  id: 3,
  username: 'katalog',
  isAdmin: false,
  authSource: 'ldap',
);

const _administrators = GroupSummary(
  id: 1,
  name: 'Administrators',
  description: 'Everything, always',
  permissions: ['users:read'],
  isSystem: true,
  userCount: 1,
);

const _household = GroupDetail(
  id: 7,
  name: 'Domownicy',
  description: 'Print, do not delete',
  permissions: ['queue:create', 'queue:read', 'users:read'],
  members: [
    GroupMember(id: 2, username: 'zosia'),
    GroupMember(id: 3, username: 'stary', isActive: false),
  ],
  userCount: 2,
);

const _administratorsDetail = GroupDetail(
  id: 1,
  name: 'Administrators',
  description: 'Everything, always',
  permissions: ['users:read'],
  isSystem: true,
  members: [GroupMember(id: 1, username: 'admin')],
  userCount: 1,
);

/// One everyday category and one that sits behind the "advanced" fold.
const _catalog = PermissionCatalog(
  categories: [
    PermissionCategory(
      name: 'Queue',
      permissions: [
        PermissionInfo(value: 'queue:read', label: 'View queue'),
        PermissionInfo(value: 'queue:create', label: 'Add to queue'),
      ],
    ),
    PermissionCategory(
      name: 'User Management',
      permissions: [PermissionInfo(value: 'users:read', label: 'View users')],
    ),
  ],
  all: ['queue:read', 'queue:create', 'users:read'],
);

final _homeAssistant = ApiKey(
  id: 1,
  name: 'Home Assistant',
  keyPrefix: 'bb_1a2b3c',
  userId: 4,
  scopes: const {
    ApiKeyScope.readStatus,
    ApiKeyScope.controlPrinter,
    ApiKeyScope.sendNotifications,
  },
  printerIds: const [2],
  lastUsed: DateTime(2026, 8, 1),
  expiresAt: DateTime(2036, 1, 1),
);

const _legacyKey = ApiKey(
  id: 2,
  name: 'old script',
  keyPrefix: 'bb_zzzz',
  scopes: {ApiKeyScope.readStatus},
  enabled: false,
);

/// Enabled but past its expiry: the list says so with a pill of its own.
final _expiredKey = ApiKey(
  id: 3,
  name: 'lapsed token',
  keyPrefix: 'bb_old',
  userId: 4,
  scopes: const {ApiKeyScope.queue},
  expiresAt: DateTime(2020, 1, 1),
);

/// The admin identity behind a JWT login, with the three repositories the
/// screens read swapped for in-file fakes. Each is replaceable for a surface
/// that needs a different answer (an empty list, a refusal).
List<Override> _adminOverrides({_Users? users, _Groups? groups, _Keys? keys}) =>
    [
      currentUserOverride(_admin),
      fakeServerProfileOverride(authMode: AuthMode.jwt),
      usersRepositoryProvider.overrideWithValue(users ?? _Users()),
      groupsRepositoryProvider.overrideWithValue(groups ?? _Groups()),
      apiKeysRepositoryProvider.overrideWithValue(keys ?? _Keys()),
      apiKeyPrinterOptionsProvider.overrideWith(
        (ref) async => const [
          Printer(id: 2, name: 'X1C Workshop'),
          Printer(id: 3, name: 'A1 mini'),
        ],
      ),
    ];

class _Users implements UsersRepository {
  _Users({
    this.users = const [_admin, _zosia, _katalog],
    this.fails = false,
    this.advanced = AdvancedAuthStatus.legacy,
  });

  final List<CurrentUser> users;
  final bool fails;
  final AdvancedAuthStatus advanced;

  @override
  Future<List<CurrentUser>> list() async => fails
      ? throw const NetworkException(AppErrorCode.serverUnreachable)
      : users;

  @override
  Future<UserItemsCount> itemsCount(int userId) async =>
      const UserItemsCount(archives: 12, queueItems: 3, libraryFiles: 7);

  @override
  Future<AdvancedAuthStatus> advancedAuthStatus() async => advanced;

  @override
  Future<CurrentUser> create(UserCreateInput body) async => _zosia;

  @override
  Future<CurrentUser> update(int userId, UserUpdateInput body) async => _zosia;

  @override
  Future<void> delete(int userId, {required bool deleteItems}) async {}
}

class _Groups implements GroupsRepository {
  _Groups([this._groups = const [_administrators, _household]]);

  final List<GroupSummary> _groups;

  @override
  Future<List<GroupSummary>> list() async => _groups;

  @override
  Future<GroupDetail> get(int groupId) async =>
      groupId == 1 ? _administratorsDetail : _household;

  @override
  Future<PermissionCatalog> permissions() async => _catalog;

  @override
  Future<GroupSummary> create(GroupCreateInput body) async => _household;

  @override
  Future<GroupSummary> update(int groupId, GroupUpdateInput body) async =>
      _household;

  @override
  Future<void> delete(int groupId) async {}

  @override
  Future<void> addMember(int groupId, int userId) async {}

  @override
  Future<void> removeMember(int groupId, int userId) async {}
}

class _Keys implements ApiKeysRepository {
  _Keys([List<ApiKey>? keys])
    : _keys = keys ?? [_homeAssistant, _legacyKey, _expiredKey];

  final List<ApiKey> _keys;

  @override
  final notificationScopeCapability = ObservedCapability.unversioned(
    whenUnknown: false,
  );

  @override
  Future<List<ApiKey>> list() async => _keys;

  @override
  Future<CreatedApiKey> create(ApiKeyCreateInput body) async =>
      CreatedApiKey(key: 'bb_full_key_0123456789', apiKey: _homeAssistant);

  @override
  Future<ApiKey> update(int keyId, ApiKeyUpdateInput body) async =>
      _homeAssistant;

  @override
  Future<void> delete(int keyId) async {}
}
