import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/user_items_count.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/features/admin/users_providers.dart';
import 'package:bambuddy_mobile/features/admin/users_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

const _admin = CurrentUser(
  id: 1,
  username: 'admin',
  email: 'admin@home.lan',
  role: 'admin',
  isAdmin: true,
  groups: [UserGroup(id: 1, name: 'Administrators')],
  permissions: {'users:read'},
);

const _member = CurrentUser(
  id: 2,
  username: 'zosia',
  isAdmin: false,
  isActive: false,
  authSource: 'ldap',
  groups: [UserGroup(id: 5, name: 'Domownicy')],
  permissions: {'queue:read'},
);

class _FakeUsersList extends UsersListNotifier {
  _FakeUsersList(this._users);

  final List<CurrentUser> _users;

  @override
  Future<List<CurrentUser>> build() async => _users;
}

/// How the session authenticates — the administration gate refuses an API key
/// outright, so the tests have to be able to say which it is.
class _FakeProfile extends ServerProfileNotifier {
  _FakeProfile({this.authMode = AuthMode.jwt});

  final AuthMode authMode;

  @override
  ServerProfile? build() =>
      ServerProfile(baseUrl: 'http://s.local:8000', authMode: authMode);
}

class _FakeCurrentUser extends CurrentUserNotifier {
  _FakeCurrentUser(this._user);

  final CurrentUser? _user;

  @override
  Future<CurrentUser?> build() async => _user;
}

Widget _app(
  List<CurrentUser> users, {
  CurrentUser? signedInAs,
  UserItemsCount counts =
      const UserItemsCount(archives: 12, queueItems: 3, libraryFiles: 7),
}) =>
    ProviderScope(
      overrides: [
        usersListProvider.overrideWith(() => _FakeUsersList(users)),
        currentUserProvider.overrideWith(() => _FakeCurrentUser(signedInAs)),
        serverProfileProvider.overrideWith(_FakeProfile.new),
        userItemsCountProvider.overrideWith((ref, id) async => counts),
      ],
      child: plApp(const UsersScreen()),
    );

void main() {
  testWidgets('shows each account with its role, state and groups',
      (tester) async {
    await tester.pumpWidget(_app(const [_admin, _member]));
    await tester.pumpAndSettle();

    expect(find.text('admin'), findsOneWidget);
    expect(find.text('zosia'), findsOneWidget);
    expect(find.text('Administrator'), findsOneWidget);
    expect(find.text('Użytkownik'), findsOneWidget);
    // Deactivated and directory-backed accounts are called out — both change
    // what an edit or a deletion would mean.
    expect(find.text('Nieaktywne'), findsOneWidget);
    expect(find.text('LDAP'), findsOneWidget);
    expect(find.text('Domownicy'), findsOneWidget);
  });

  testWidgets('marks the account this session belongs to', (tester) async {
    await tester.pumpWidget(
      _app(const [_admin, _member], signedInAs: _member),
    );
    await tester.pumpAndSettle();

    expect(find.text('ty'), findsOneWidget);
    // The marker sits next to the signed-in name, not the other one.
    expect(
      find.ancestor(
        of: find.text('ty'),
        matching: find.ancestor(
          of: find.text('zosia'),
          matching: find.byType(Row),
        ),
      ),
      findsWidgets,
    );
  });

  testWidgets('opening an account shows what it owns', (tester) async {
    await tester.pumpWidget(_app(const [_admin, _member]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('zosia'));
    await tester.pumpAndSettle();

    expect(find.text('UTWORZONE PRZEZ TO KONTO'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    // No e-mail on this account — the sheet says so instead of leaving a gap.
    expect(find.text('brak'), findsWidgets);
  });

  testWidgets('an empty server says so instead of showing a blank list',
      (tester) async {
    await tester.pumpWidget(_app(const []));
    await tester.pumpAndSettle();

    expect(find.text('Na tym serwerze nie ma kont.'), findsOneWidget);
  });

  testWidgets('offers no way to add or edit an account to a non-admin',
      (tester) async {
    // `users:read` opens the list, and stops there: every write carries
    // `RequireAdminIfAuthEnabled` on top of its permission.
    await tester.pumpWidget(_app(const [_admin, _member],
        signedInAs: const CurrentUser(
          id: 9,
          username: 'domownik',
          isAdmin: false,
          permissions: {'users:read'},
        )));
    await tester.pumpAndSettle();

    expect(find.text('Dodaj konto'), findsNothing);

    await tester.tap(find.text('zosia'));
    await tester.pumpAndSettle();

    expect(find.text('Edytuj'), findsNothing);
    expect(find.text('Usuń'), findsNothing);
  });

  testWidgets('gives an admin the add, edit and delete entries', (tester) async {
    await tester.pumpWidget(_app(const [_admin, _member], signedInAs: _admin));
    await tester.pumpAndSettle();

    expect(find.text('Dodaj konto'), findsOneWidget);

    await tester.tap(find.text('zosia'));
    await tester.pumpAndSettle();

    expect(find.text('Edytuj'), findsOneWidget);
    expect(find.text('Usuń'), findsOneWidget);
  });

  testWidgets('leaves out delete on the account you are signed in with',
      (tester) async {
    // The server refuses it (`users.py::delete_user`) — offering the button
    // would only buy an error message.
    await tester.pumpWidget(_app(const [_admin, _member], signedInAs: _admin));
    await tester.pumpAndSettle();

    await tester.tap(find.text('admin'));
    await tester.pumpAndSettle();

    expect(find.text('Edytuj'), findsOneWidget);
    expect(find.text('Usuń'), findsNothing);
  });

  group('canReadUsersProvider', () {
    ProviderContainer containerFor(
      CurrentUser? user, {
      AuthMode authMode = AuthMode.jwt,
    }) {
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWith(() => _FakeCurrentUser(user)),
          serverProfileProvider
              .overrideWith(() => _FakeProfile(authMode: authMode)),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('an unknown identity is shown nothing administrative', () async {
      final container = containerFor(null);
      await container.read(currentUserProvider.future);
      expect(container.read(canReadUsersProvider), isFalse);
    });

    test('a member without the permission is shown nothing either', () async {
      final container = containerFor(_member);
      await container.read(currentUserProvider.future);
      expect(container.read(canReadUsersProvider), isFalse);
    });

    test('`users:read` is enough — the admin role is not required', () async {
      final container = containerFor(const CurrentUser(
        id: 3,
        username: 'domownik',
        isAdmin: false,
        permissions: {'users:read'},
      ));
      await container.read(currentUserProvider.future);
      expect(container.read(canReadUsersProvider), isTrue);
    });

    test('reading is not managing — a non-admin gets the list only', () async {
      final container = containerFor(const CurrentUser(
        id: 3,
        username: 'domownik',
        isAdmin: false,
        permissions: {'users:read', 'users:create'},
      ));
      await container.read(currentUserProvider.future);

      // Even `users:create` is not enough: the route demands the admin role
      // as well (`users.py::list_users`).
      expect(container.read(canReadUsersProvider), isTrue);
      expect(container.read(canManageUsersProvider), isFalse);
    });

    test('an API-key session is refused, whatever /auth/me claims it is',
        () async {
      // The server hands a key the synthetic admin with every permission
      // (`routes/auth.py::_api_key_to_user_response`) and then refuses it every
      // administrative route (`core/auth.py::_resolve_apikey_scope`). Believing
      // the first is how the account list ended up 403-ing on a key session.
      final container = containerFor(
        const CurrentUser(
          id: 0,
          username: 'api-key:bb_abcd',
          role: 'admin',
          isAdmin: true,
          permissions: {'users:read', 'groups:read', 'api_keys:read'},
        ),
        authMode: AuthMode.apiKey,
      );
      await container.read(currentUserProvider.future);
      expect(container.read(canReadUsersProvider), isFalse);
    });
  });
}
