import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/group_summary.dart';
import 'package:bambuddy_mobile/core/models/group_write.dart';
import 'package:bambuddy_mobile/core/models/permission_catalog.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/data/groups_repository.dart';
import 'package:bambuddy_mobile/features/admin/group_detail_screen.dart';
import 'package:bambuddy_mobile/features/admin/group_form_screen.dart';
import 'package:bambuddy_mobile/features/admin/groups_providers.dart';
import 'package:bambuddy_mobile/features/admin/groups_screen.dart';
import 'package:bambuddy_mobile/features/admin/users_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

const _admin = CurrentUser(id: 1, username: 'admin', isAdmin: true);

const _member = CurrentUser(
  id: 2,
  username: 'zosia',
  isAdmin: false,
  permissions: {'groups:read'},
);

const _household = GroupDetail(
  id: 7,
  name: 'Domownicy',
  description: 'Drukują, nie kasują',
  permissions: ['queue:create', 'queue:read'],
  members: [
    GroupMember(id: 2, username: 'zosia'),
    GroupMember(id: 3, username: 'stary', isActive: false),
  ],
  userCount: 2,
);

const _administrators = GroupSummary(
  id: 1,
  name: 'Administrators',
  permissions: ['users:read'],
  isSystem: true,
  userCount: 1,
);

/// Records what was asked of the server; reading is served from the fixtures
/// above.
class _FakeGroups implements GroupsRepository {
  (int, int)? added;
  (int, int)? removed;
  GroupCreateInput? created;
  (int, GroupUpdateInput)? updated;
  int? deleted;

  @override
  Future<List<GroupSummary>> list() async => const [
    _administrators,
    _household,
  ];

  @override
  Future<GroupDetail> get(int groupId) async => _household;

  @override
  Future<PermissionCatalog> permissions() async => _catalog;

  @override
  Future<GroupSummary> create(GroupCreateInput body) async {
    created = body;
    return _household;
  }

  @override
  Future<GroupSummary> update(int groupId, GroupUpdateInput body) async {
    updated = (groupId, body);
    return _household;
  }

  @override
  Future<void> delete(int groupId) async => deleted = groupId;

  @override
  Future<void> addMember(int groupId, int userId) async =>
      added = (groupId, userId);

  @override
  Future<void> removeMember(int groupId, int userId) async =>
      removed = (groupId, userId);
}

/// A catalog with one everyday category and one that belongs behind the fold.
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

class _FakeCurrentUser extends CurrentUserNotifier {
  _FakeCurrentUser(this._user);

  final CurrentUser? _user;

  @override
  Future<CurrentUser?> build() async => _user;

  @override
  Future<void> refresh() async {}
}

class _FakeUsersList extends UsersListNotifier {
  @override
  Future<List<CurrentUser>> build() async => const [
    CurrentUser(id: 1, username: 'admin', isAdmin: true),
    CurrentUser(id: 2, username: 'zosia', isAdmin: false),
    CurrentUser(id: 9, username: 'nowy', isAdmin: false),
  ];
}

Widget _app(
  Widget child, {
  required _FakeGroups repo,
  CurrentUser? signedInAs,
}) => ProviderScope(
  overrides: [
    groupsRepositoryProvider.overrideWithValue(repo),
    currentUserProvider.overrideWith(() => _FakeCurrentUser(signedInAs)),
    fakeServerProfileOverride(authMode: AuthMode.jwt),
    usersListProvider.overrideWith(_FakeUsersList.new),
  ],
  child: plApp(child),
);

void main() {
  late _FakeGroups repo;

  setUp(() => repo = _FakeGroups());

  group('the list', () {
    testWidgets('shows what each group is for and how much it holds', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const GroupsScreen(), repo: repo, signedInAs: _admin),
      );
      await tester.pumpAndSettle();

      expect(find.text('Administrators'), findsOneWidget);
      expect(find.text('Domownicy'), findsOneWidget);
      expect(find.text('(wbudowana)'), findsOneWidget);
      expect(find.text('Bez opisu'), findsOneWidget);
      expect(find.textContaining('2 konta'), findsOneWidget);
      expect(find.textContaining('2 uprawnienia'), findsOneWidget);
    });
  });

  group('one group', () {
    testWidgets('lists its members and marks the switched-off ones', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const GroupDetailScreen(groupId: 7),
          repo: repo,
          signedInAs: _admin,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('zosia'), findsOneWidget);
      expect(find.text('stary'), findsOneWidget);
      expect(find.text('Nieaktywne'), findsOneWidget);
      expect(find.text('CZŁONKOWIE'), findsOneWidget);
    });

    testWidgets('offers no membership change to a non-admin', (tester) async {
      // `groups:read` opens the group; moving people in and out of it is
      // admin-only server-side.
      await tester.pumpWidget(
        _app(
          const GroupDetailScreen(groupId: 7),
          repo: repo,
          signedInAs: _member,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dodaj konto'), findsNothing);
      expect(find.byTooltip('Usuń z grupy'), findsNothing);
    });

    testWidgets('adds an account that is not in the group yet', (tester) async {
      await tester.pumpWidget(
        _app(
          const GroupDetailScreen(groupId: 7),
          repo: repo,
          signedInAs: _admin,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dodaj konto'));
      await tester.pumpAndSettle();

      // zosia is already a member, so the picker leaves her out.
      expect(find.text('nowy'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'zosia'), findsNothing);

      await tester.tap(find.text('nowy'));
      await tester.pumpAndSettle();

      expect(repo.added, (7, 9));
    });

    testWidgets('asks before taking someone out of the group', (tester) async {
      await tester.pumpWidget(
        _app(
          const GroupDetailScreen(groupId: 7),
          repo: repo,
          signedInAs: _admin,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Usuń z grupy').first);
      await tester.pumpAndSettle();

      expect(find.text('Usunąć zosia z grupy Domownicy?'), findsOneWidget);

      await tester.tap(find.text('Anuluj'));
      await tester.pumpAndSettle();
      expect(repo.removed, isNull);

      await tester.tap(find.byTooltip('Usuń z grupy').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Usuń z grupy').last);
      await tester.pumpAndSettle();

      expect(repo.removed, (7, 2));
    });

    testWidgets('says a built-in group only takes membership changes', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const GroupDetailScreen(groupId: 1),
          repo: _SystemGroup(),
          signedInAs: _admin,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Wbudowana'), findsOneWidget);
      expect(find.textContaining('nie zmienisz z nazwy'), findsOneWidget);
    });
  });

  group('the permission editor', () {
    testWidgets('shows the everyday categories and folds the rest away', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const GroupFormScreen(), repo: repo, signedInAs: _admin),
      );
      await tester.pumpAndSettle();

      expect(find.text('Queue'), findsOneWidget);
      expect(find.text('Administracja serwerem'), findsOneWidget);
      expect(find.text('User Management'), findsNothing);

      await tester.tap(find.text('Administracja serwerem'));
      await tester.pumpAndSettle();

      expect(find.text('User Management'), findsOneWidget);
    });

    testWidgets('creates a group out of the ticked permissions', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const GroupFormScreen(), repo: repo, signedInAs: _admin),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nazwa'),
        'Domownicy',
      );
      await tester.tap(find.text('Queue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to queue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();

      expect(repo.created?.name, 'Domownicy');
      expect(repo.created?.permissions, ['queue:create']);
    });

    testWidgets('keeps the permissions it never showed', (tester) async {
      // The group holds `users:read`, which lives behind the fold. Saving
      // sends the whole set — dropping it here would silently revoke it.
      const group = GroupSummary(
        id: 7,
        name: 'Domownicy',
        permissions: ['queue:read', 'users:read'],
      );
      await tester.pumpWidget(
        _app(
          const GroupFormScreen(existing: group),
          repo: repo,
          signedInAs: _admin,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Queue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to queue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();

      expect(repo.updated?.$2.permissions, [
        'queue:create',
        'queue:read',
        'users:read',
      ]);
    });

    testWidgets('counts what is hidden so nobody edits a group blind', (
      tester,
    ) async {
      const group = GroupSummary(
        id: 7,
        name: 'Domownicy',
        permissions: ['users:read'],
      );
      await tester.pumpWidget(
        _app(
          const GroupFormScreen(existing: group),
          repo: repo,
          signedInAs: _admin,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('zaznaczono 1'), findsOneWidget);
      // The fold itself carries the count of what is selected inside it.
      expect(find.widgetWithText(DashPill, '1'), findsOneWidget);
    });

    testWidgets('opens a built-in group read-only apart from its description', (
      tester,
    ) async {
      const system = GroupSummary(
        id: 1,
        name: 'Administrators',
        permissions: ['users:read'],
        isSystem: true,
      );
      await tester.pumpWidget(
        _app(
          const GroupFormScreen(existing: system),
          repo: repo,
          signedInAs: _admin,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Grupa wbudowana'), findsOneWidget);
      final name = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Nazwa'),
      );
      expect(name.enabled, isFalse);

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox).first);
      expect(checkbox.onChanged, isNull);
    });

    testWidgets('a built-in group still saves its description', (tester) async {
      const system = GroupSummary(
        id: 1,
        name: 'Administrators',
        description: 'Full access',
        permissions: ['users:read'],
        isSystem: true,
      );
      await tester.pumpWidget(
        _app(
          const GroupFormScreen(existing: system),
          repo: repo,
          signedInAs: _admin,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Do czego służy'),
        'Pełen dostęp',
      );
      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();

      // Name and permissions are refused for a system group, so neither is
      // sent — only the one field the server accepts.
      expect(repo.updated?.$2.description, 'Pełen dostęp');
      expect(repo.updated?.$2.name, isNull);
      expect(repo.updated?.$2.permissions, isNull);
    });
  });

  group('deleting a group', () {
    testWidgets('is not offered for a built-in one', (tester) async {
      await tester.pumpWidget(
        _app(
          const GroupDetailScreen(groupId: 1),
          repo: _SystemGroup(),
          signedInAs: _admin,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Edytuj'), findsOneWidget);
      expect(find.text('Usuń grupę'), findsNothing);
    });

    testWidgets('says what happens to the accounts in it', (tester) async {
      await tester.pumpWidget(
        _app(
          const GroupDetailScreen(groupId: 7),
          repo: repo,
          signedInAs: _admin,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Usuń grupę'));
      await tester.pumpAndSettle();

      expect(find.text('Usunąć grupę Domownicy?'), findsOneWidget);
      expect(find.textContaining('2 konta i zostają'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Usuń grupę'));
      await tester.pumpAndSettle();

      expect(repo.deleted, 7);
    });
  });

  group('the gate', () {
    ProviderContainer containerFor(
      CurrentUser? user, {
      AuthMode mode = AuthMode.jwt,
    }) {
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWith(() => _FakeCurrentUser(user)),
          fakeServerProfileOverride(authMode: AuthMode.jwt),
          if (mode == AuthMode.apiKey)
            fakeServerProfileOverride(authMode: AuthMode.apiKey),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a member with groups:read may look but not move anyone', () async {
      final container = containerFor(_member);
      await container.read(currentUserProvider.future);

      expect(container.read(canReadGroupsProvider), isTrue);
      expect(container.read(canManageGroupsProvider), isFalse);
    });

    test('an API-key session is refused the groups too', () async {
      final container = containerFor(
        const CurrentUser(
          id: 0,
          username: 'api-key:bb_abcd',
          isAdmin: true,
          permissions: {'groups:read'},
        ),
        mode: AuthMode.apiKey,
      );
      await container.read(currentUserProvider.future);

      expect(container.read(canReadGroupsProvider), isFalse);
    });
  });
}

class _SystemGroup extends _FakeGroups {
  @override
  Future<GroupDetail> get(int groupId) async => const GroupDetail(
    id: 1,
    name: 'Administrators',
    permissions: ['users:read'],
    isSystem: true,
    userCount: 1,
    members: [GroupMember(id: 1, username: 'admin')],
  );
}
