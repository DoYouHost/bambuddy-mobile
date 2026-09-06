import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/user_write.dart';
import 'package:bambuddy_mobile/data/users_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late UsersRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = UsersRepository(dio);
  });

  test('list() parses the accounts /users/ answers with', () async {
    adapter.onGet(
      '/api/v1/users/',
      (s) => s.reply(200, [
        {
          'id': 1,
          'username': 'admin',
          'email': 'admin@home.lan',
          'role': 'admin',
          'is_active': true,
          'is_admin': true,
          'auth_source': 'local',
          'groups': [
            {'id': 1, 'name': 'Administrators'},
          ],
          'permissions': ['users:read', 'users:create'],
          'created_at': '2025-06-01T10:00:00',
        },
        {
          'id': 2,
          'username': 'zosia',
          'email': null,
          'role': 'user',
          'is_active': false,
          'is_admin': false,
          'auth_source': 'ldap',
          'groups': const <Object>[],
          'permissions': const <String>[],
          'created_at': '2026-01-15T09:30:00',
        },
      ]),
    );

    final users = await repo.list();
    expect(users, hasLength(2));
    expect(users.first.username, 'admin');
    expect(users.first.isAdmin, isTrue);
    expect(users.first.groups.single.name, 'Administrators');
    expect(users.last.isActive, isFalse);
    expect(users.last.email, isNull);
    expect(users.last.authSource, 'ldap');
    // An empty list is a real answer — a member of a group that grants
    // nothing — and stays distinguishable from "the server didn't say".
    expect(users.last.permissions, isEmpty);
    expect(users.last.permissionsKnown, isTrue);
  });

  test(
    'an account from a server that omits `permissions` stays unknown',
    () async {
      adapter.onGet(
        '/api/v1/users/',
        (s) => s.reply(200, [
          {
            'id': 3,
            'username': 'stary-serwer',
            'role': 'user',
            'is_active': true,
            'is_admin': false,
            'created_at': '2025-01-01T00:00:00',
          },
        ]),
      );

      final user = (await repo.list()).single;
      expect(user.permissionsKnown, isFalse);
      expect(user.groups, isEmpty);
    },
  );

  test('itemsCount() parses what the account owns', () async {
    adapter.onGet(
      '/api/v1/users/2/items-count',
      (s) =>
          s.reply(200, {'archives': 12, 'queue_items': 3, 'library_files': 7}),
    );

    final counts = await repo.itemsCount(2);
    expect(counts.archives, 12);
    expect(counts.queueItems, 3);
    expect(counts.libraryFiles, 7);
    expect(counts.total, 22);
  });

  test('a 403 comes back as an AppApiException, not a DioException', () async {
    // What an identity without `users:read` gets
    // (`routes/users.py::_user_to_response`).
    adapter.onGet(
      '/api/v1/users/',
      (s) => s.reply(403, {'detail': 'Not enough permissions'}),
    );

    expect(repo.list(), throwsA(isA<AppApiException>()));
  });

  test('a 404 for an account that is gone is mapped too', () async {
    adapter.onGet(
      '/api/v1/users/9/items-count',
      (s) => s.reply(404, {'detail': 'User not found'}),
    );

    expect(repo.itemsCount(9), throwsA(isA<AppApiException>()));
  });

  group('writes', () {
    test('create sends what the server asks for and nothing else', () async {
      Map<String, dynamic>? sent;
      adapter.onPost(
        '/api/v1/users/',
        (s) => s.reply(201, {
          'id': 4,
          'username': 'zosia',
          'role': 'user',
          'is_active': true,
          'is_admin': false,
          'groups': const <Object>[],
          'permissions': const <String>[],
          'created_at': '2026-08-03T12:00:00',
        }),
        data: Matchers.any,
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.method == 'POST') {
              sent = options.data as Map<String, dynamic>;
            }
            handler.next(options);
          },
        ),
      );

      final created = await repo.create(
        const UserCreateInput(
          username: 'zosia',
          password: 'Sekret!23',
          role: UserRoles.user,
          groupIds: [5],
        ),
      );

      expect(created.id, 4);
      expect(sent, {
        'username': 'zosia',
        'password': 'Sekret!23',
        'role': 'user',
        'group_ids': [5],
      });
      // No e-mail was typed, so none is sent — a null would be a value the
      // server stores, not an omission.
      expect(sent!.containsKey('email'), isFalse);
    });

    test('update sends only the fields it was given', () async {
      Map<String, dynamic>? sent;
      adapter.onPatch(
        '/api/v1/users/2',
        (s) => s.reply(200, {
          'id': 2,
          'username': 'zosia',
          'role': 'user',
          'is_active': false,
          'is_admin': false,
          'groups': const <Object>[],
          'permissions': const <String>[],
          'created_at': '2026-01-15T09:30:00',
        }),
        data: Matchers.any,
      );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.method == 'PATCH') {
              sent = options.data as Map<String, dynamic>;
            }
            handler.next(options);
          },
        ),
      );

      await repo.update(2, const UserUpdateInput(isActive: false));

      expect(sent, {'is_active': false});
    });

    test('delete carries the choice about the account\'s items', () async {
      Map<String, dynamic>? query;
      adapter.onDelete('/api/v1/users/2', (s) => s.reply(204, null));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.method == 'DELETE') query = options.queryParameters;
            handler.next(options);
          },
        ),
      );

      await repo.delete(2, deleteItems: true);

      expect(query, {'delete_items': true});
    });

    test('a refused write keeps the rule the server named', () async {
      adapter.onDelete(
        '/api/v1/users/1',
        (s) => s.reply(400, {'detail': 'Cannot delete the last admin user'}),
      );

      // Without this the 400 arrives as a bare "bad response" and the reason —
      // which lives only server-side — is lost.
      await expectLater(
        repo.delete(1, deleteItems: false),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having(
                (e) => e.detail,
                'detail',
                'Cannot delete the last admin user',
              ),
        ),
      );
    });

    test(
      'a 422 from the password validator is unwrapped to its message',
      () async {
        adapter.onPost(
          '/api/v1/users/',
          (s) => s.reply(422, {
            'detail': [
              {
                'loc': ['body', 'password'],
                'msg': 'Value error, Password must contain at least one digit',
                'type': 'value_error',
              },
            ],
          }),
          data: Matchers.any,
        );

        await expectLater(
          repo.create(
            const UserCreateInput(username: 'x', password: 'nodigits'),
          ),
          throwsA(
            isA<ApiException>().having(
              (e) => e.detail,
              'detail',
              'Password must contain at least one digit',
            ),
          ),
        );
      },
    );

    test(
      'advanced-auth status falls back on a server without the route',
      () async {
        adapter.onGet(
          '/api/v1/auth/advanced-auth/status',
          (s) => s.reply(404, {'detail': 'Not Found'}),
        );

        final status = await repo.advancedAuthStatus();
        expect(status.enabled, isFalse);
        expect(status.smtpConfigured, isFalse);
      },
    );

    test('advanced-auth status reads both flags the form needs', () async {
      adapter.onGet(
        '/api/v1/auth/advanced-auth/status',
        (s) => s.reply(200, {
          'advanced_auth_enabled': true,
          'smtp_configured': false,
          'local_login_enabled': true,
          'autologin_provider_id': null,
        }),
      );

      final status = await repo.advancedAuthStatus();
      expect(status.enabled, isTrue);
      expect(status.smtpConfigured, isFalse);
    });
  });
}
