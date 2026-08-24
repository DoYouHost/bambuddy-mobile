import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/features/admin/admin_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

class _FakeCurrentUser extends CurrentUserNotifier {
  _FakeCurrentUser(this._user);

  final CurrentUser? _user;

  @override
  Future<CurrentUser?> build() async => _user;
}

ProviderContainer _containerFor(
  CurrentUser? user, {
  AuthMode authMode = AuthMode.jwt,
}) {
  final container = ProviderContainer(overrides: [
    currentUserProvider.overrideWith(() => _FakeCurrentUser(user)),
    fakeServerProfileOverride(authMode: authMode),
  ]);
  addTearDown(container.dispose);
  return container;
}

Widget _app(CurrentUser? user) => UncontrolledProviderScope(
      container: _containerFor(user),
      child: plApp(const AdminScreen()),
    );

void main() {
  testWidgets('an admin is offered all three', (tester) async {
    await tester.pumpWidget(
      _app(const CurrentUser(id: 1, username: 'admin', isAdmin: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Użytkownicy'), findsOneWidget);
    expect(find.text('Grupy'), findsOneWidget);
    expect(find.text('Klucze API'), findsOneWidget);
    expect(find.textContaining('Zalogowany jako admin'), findsOneWidget);
  });

  testWidgets('each entry stands on its own permission', (tester) async {
    // The household account from the backlog: it may see who has an account,
    // and nothing beyond that.
    await tester.pumpWidget(_app(const CurrentUser(
      id: 5,
      username: 'domownik',
      isAdmin: false,
      permissions: {'users:read'},
    )));
    await tester.pumpAndSettle();

    expect(find.text('Użytkownicy'), findsOneWidget);
    expect(find.text('Grupy'), findsNothing);
    expect(find.text('Klucze API'), findsNothing);
  });

  group('canOpenAdminProvider', () {
    test('one read permission is enough to offer the entry', () async {
      final container = _containerFor(const CurrentUser(
        id: 5,
        username: 'domownik',
        isAdmin: false,
        permissions: {'api_keys:read'},
      ));
      await container.read(currentUserProvider.future);

      expect(container.read(canOpenAdminProvider), isTrue);
    });

    test('an account granted none of the three is offered nothing', () async {
      final container = _containerFor(const CurrentUser(
        id: 5,
        username: 'domownik',
        isAdmin: false,
        permissions: {'queue:read'},
      ));
      await container.read(currentUserProvider.future);

      expect(container.read(canOpenAdminProvider), isFalse);
    });

    test('a server with authentication off has nobody to show it to',
        () async {
      final container = _containerFor(null);
      await container.read(currentUserProvider.future);

      expect(container.read(canOpenAdminProvider), isFalse);
    });

    test('an API-key session is refused the whole section', () async {
      // `/auth/me` calls a key session an admin with every permission; the
      // routes refuse it all three (`core/auth.py::_required_apikey_scopes`).
      final container = _containerFor(
        const CurrentUser(
          id: 0,
          username: 'api-key:bb_abcd',
          isAdmin: true,
          permissions: {'users:read', 'groups:read', 'api_keys:read'},
        ),
        authMode: AuthMode.apiKey,
      );
      await container.read(currentUserProvider.future);

      expect(container.read(canOpenAdminProvider), isFalse);
    });
  });
}
