import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:flutter_test/flutter_test.dart';

/// A full `UserResponse` as the server builds it in `_user_to_response`
/// (`backend/app/api/routes/auth.py:75`).
Map<String, dynamic> _response({
  bool isAdmin = false,
  Object? permissions = const ['users:read', 'queue:read'],
  bool withPermissionsKey = true,
}) =>
    {
      'id': 4,
      'username': 'household',
      'email': 'h@example.org',
      'role': 'user',
      'is_active': true,
      'is_admin': isAdmin,
      'auth_source': 'local',
      'groups': [
        {'id': 2, 'name': 'Operators'},
      ],
      if (withPermissionsKey) 'permissions': permissions,
      'created_at': '2026-01-04T10:11:12.131415',
    };

void main() {
  group('CurrentUser.fromJson', () {
    test('reads the whole UserResponse', () {
      final user = CurrentUser.fromJson(_response());

      expect(user.id, 4);
      expect(user.username, 'household');
      expect(user.email, 'h@example.org');
      expect(user.role, 'user');
      expect(user.isActive, isTrue);
      expect(user.isAdmin, isFalse);
      expect(user.authSource, 'local');
      expect(user.groups.single.id, 2);
      expect(user.groups.single.name, 'Operators');
      expect(user.permissions, {'users:read', 'queue:read'});
      expect(user.permissionsKnown, isTrue);
    });

    test('created_at without a zone marker is read as UTC', () {
      // The column is naive UTC and this schema sends it through `isoformat()`
      // with no `Z` — taking Dart's default (local) would shift it.
      final user = CurrentUser.fromJson(_response());
      expect(
        user.createdAt,
        DateTime.utc(2026, 1, 4, 10, 11, 12, 131, 415).toLocal(),
      );
    });

    test('an empty list is an answer: the user was granted nothing', () {
      // `permissions: list[str] = []` is what a member of a group that grants
      // nothing gets. Reading that as "unknown" would show them every screen
      // and let the server answer 403.
      final user = CurrentUser.fromJson(_response(permissions: const []));

      expect(user.permissionsKnown, isTrue);
      expect(user.can(Permissions.usersRead), isFalse);
      expect(user.can(Permissions.groupsRead), isFalse);
    });

    test('a response without the field grants everything', () {
      final user = CurrentUser.fromJson(_response(withPermissionsKey: false));

      expect(user.permissionsKnown, isFalse);
      expect(user.can(Permissions.usersRead), isTrue);
      expect(user.can('anything:at:all'), isTrue);
    });

    test('a permissions value that is not a list is not an answer either', () {
      final user = CurrentUser.fromJson(_response(permissions: 'users:read'));

      expect(user.permissionsKnown, isFalse);
      expect(user.permissions, isEmpty);
      expect(user.can(Permissions.usersRead), isTrue);
    });

    test('non-string entries are dropped, the rest still counts', () {
      final user = CurrentUser.fromJson(
        _response(permissions: const ['users:read', 42, null]),
      );

      expect(user.permissions, {'users:read'});
      expect(user.permissionsKnown, isTrue);
      expect(user.can(Permissions.usersRead), isTrue);
      expect(user.can(Permissions.groupsRead), isFalse);
    });

    test('an empty body parses instead of throwing', () {
      final user = CurrentUser.fromJson(const {});

      expect(user.id, 0);
      expect(user.username, '');
      expect(user.isAdmin, isFalse);
      expect(user.groups, isEmpty);
      expect(user.permissionsKnown, isFalse);
      expect(user.createdAt, isNull);
    });

    test('a group record missing its name does not drop the rest', () {
      final user = CurrentUser.fromJson({
        ..._response(),
        'groups': [
          {'id': 2},
          {'id': 3, 'name': 'Guests'},
        ],
      });

      expect(user.groups.map((g) => g.name), ['', 'Guests']);
    });
  });

  group('can', () {
    test('an admin passes every check, whatever the list says', () {
      // Mirrors `User.has_permission` — admins bypass server-side too, so an
      // account whose groups grant nothing still passes on the flag alone.
      final user = CurrentUser.fromJson(
        _response(isAdmin: true, permissions: const []),
      );

      expect(user.isAdmin, isTrue);
      expect(user.can(Permissions.usersRead), isTrue);
      expect(user.can(Permissions.apiKeysRead), isTrue);
    });

    test('matching is exact — the server knows no wildcard form', () {
      final user = CurrentUser.fromJson(
        _response(permissions: const ['users:*', '*']),
      );

      expect(user.can(Permissions.usersRead), isFalse);
      expect(user.can('users:*'), isTrue);
    });

    test('a granted permission passes, a neighbouring one does not', () {
      final user = CurrentUser.fromJson(
        _response(permissions: const ['users:read']),
      );

      expect(user.can(Permissions.usersRead), isTrue);
      expect(user.can('users:create'), isFalse);
      expect(user.can(Permissions.groupsRead), isFalse);
    });
  });

  /// `/auth/me` describes an API-key session differently on either side of
  /// server 1.2.6 (issue #1894), and the app talks to both. Neither shape may
  /// stop parsing — see `docs/plans/13-users-slim-and-api-key-identity.md`.
  group('an API-key session, both server generations', () {
    test('≤ 1.2.5.x: the synthetic admin still parses', () {
      final user = CurrentUser.fromJson(const {
        'id': 0,
        'username': 'api-key:bb_1a2b3c',
        'email': null,
        'role': 'admin',
        'is_active': true,
        'is_admin': true,
        'auth_source': 'local',
        'groups': <Object>[],
        // The real thing sent every permission in the enum; three stand in.
        'permissions': ['users:create', 'printers:read', 'queue:create'],
        'created_at': '2026-02-01T08:00:00',
      });

      expect(user.id, 0);
      expect(user.username, 'api-key:bb_1a2b3c');
      expect(user.isAdmin, isTrue);
      expect(user.can('anything:at:all'), isTrue,
          reason: 'the admin flag short-circuits, as it does server-side');
    });

    test('1.2.6+: the key owner, and only the permissions the key admits', () {
      final user = CurrentUser.fromJson(const {
        'id': 7,
        'username': 'household',
        // Withheld on purpose even though the owner has both.
        'email': null,
        'role': 'user',
        'is_active': true,
        'is_admin': false,
        'auth_source': 'local',
        'groups': <Object>[],
        // What `can_read_status` alone maps to; nothing administrative.
        'permissions': ['printers:read', 'stats:read', 'users:read_slim'],
        'created_at': '2026-02-01T08:00:00',
      });

      expect(user.id, 7, reason: 'this is what created_by_id filters on');
      expect(user.username, 'household');
      expect(user.isAdmin, isFalse);
      expect(user.permissionsKnown, isTrue);
      expect(user.can('printers:read'), isTrue);
      expect(user.can('users:read'), isFalse);
      expect(user.can('printers:control'), isFalse);
    });

    test('1.2.6+: a key predating owners keeps id 0 but drops the admin claim',
        () {
      final user = CurrentUser.fromJson(const {
        'id': 0,
        'username': 'api-key:bb_1a2b3c',
        'email': null,
        'role': 'user',
        'is_active': true,
        'is_admin': false,
        'auth_source': 'local',
        'groups': <Object>[],
        'permissions': ['printers:read'],
        'created_at': '2026-02-01T08:00:00',
      });

      // 0 is a placeholder for "no owner to name", not account number zero —
      // it must never be sent back as a `created_by_id`.
      expect(user.id, 0);
      expect(user.isAdmin, isFalse);
      expect(user.can('users:read'), isFalse);
    });
  });

  test('Permissions holds the strings the server declares', () {
    // `backend/app/core/permissions.py:164,170,176`.
    expect(Permissions.usersRead, 'users:read');
    expect(Permissions.groupsRead, 'groups:read');
    expect(Permissions.apiKeysRead, 'api_keys:read');
  });
}
