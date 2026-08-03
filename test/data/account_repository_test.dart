import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/data/account_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late AccountRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = AccountRepository(dio);
  });

  test('me() parses the UserResponse from /auth/me', () async {
    adapter.onGet(
      '/api/v1/auth/me',
      (s) => s.reply(200, {
        'id': 7,
        'username': 'kacper',
        'email': null,
        'role': 'user',
        'is_active': true,
        'is_admin': false,
        'auth_source': 'ldap',
        'groups': [
          {'id': 5, 'name': 'Household'},
        ],
        'permissions': ['queue:read', 'users:read'],
        'created_at': '2025-11-02T08:00:00',
      }),
    );

    final user = await repo.me();
    expect(user.username, 'kacper');
    expect(user.email, isNull);
    expect(user.isAdmin, isFalse);
    expect(user.authSource, 'ldap');
    expect(user.groups.single.name, 'Household');
    expect(user.can(Permissions.usersRead), isTrue);
    expect(user.can(Permissions.groupsRead), isFalse);
  });

  test('an API-key session gets the synthetic admin the server answers with',
      () async {
    // `_api_key_to_user_response` (`backend/app/api/routes/auth.py:91`) — a key
    // is admin with every permission, so nothing here is gated for it.
    adapter.onGet(
      '/api/v1/auth/me',
      (s) => s.reply(200, {
        'id': 0,
        'username': 'api-key:bb_abcd',
        'email': null,
        'role': 'admin',
        'is_active': true,
        'is_admin': true,
        'groups': const <Object>[],
        'permissions': const ['users:read', 'groups:read', 'api_keys:read'],
        'created_at': '2025-06-01T00:00:00',
      }),
    );

    final user = await repo.me();
    expect(user.isAdmin, isTrue);
    expect(user.can(Permissions.apiKeysRead), isTrue);
  });

  test('a 401 comes back as an AppApiException, not a DioException', () async {
    // What a server with auth switched off answers — `/auth/me` requires
    // credentials (`auth.py:706`).
    adapter.onGet(
      '/api/v1/auth/me',
      (s) => s.reply(401, {'detail': 'Authentication required'}),
    );

    expect(repo.me(), throwsA(isA<AppApiException>()));
  });

  test('a 404 from an older server comes back mapped too', () async {
    adapter.onGet('/api/v1/auth/me', (s) => s.reply(404, {'detail': 'nope'}));

    expect(repo.me(), throwsA(isA<AppApiException>()));
  });
}
