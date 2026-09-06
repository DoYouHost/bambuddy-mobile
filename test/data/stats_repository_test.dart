import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/data/stats_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

/// The "filter by user" picker is answered by whichever user listing the
/// server has: `/users/slim` from 1.2.6, the full `/users/` before it. Both
/// generations stay supported, so what these pin is the probe — which route is
/// asked, when the fallback happens, and that it is not paid for twice.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late StatsRepository repo;
  late List<String> requested;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = StatsRepository(dio);
    requested = [];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requested.add(options.path);
          handler.next(options);
        },
      ),
    );
  });

  const slim = '/api/v1/users/slim';
  const full = '/api/v1/users/';

  /// A row as `/users/slim` sends it — the whole `UserSlim` shape.
  List<Map<String, Object>> slimRows() => [
    {'id': 2, 'username': 'zosia'},
    {'id': 1, 'username': 'admin'},
  ];

  /// The same two people as the full listing sends them: `UserResponse`, with
  /// everything the slim shape deliberately withholds.
  List<Map<String, Object?>> fullRows() => [
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
      'permissions': ['users:read'],
      'created_at': '2025-06-01T10:00:00',
    },
    {
      'id': 2,
      'username': 'zosia',
      'email': null,
      'role': 'user',
      'is_active': true,
      'is_admin': false,
      'auth_source': 'local',
      'groups': const <Object>[],
      'permissions': const <String>[],
      'created_at': '2026-01-15T09:30:00',
    },
  ];

  group('fetchUsers', () {
    test(
      'a 1.2.6 server answers the slim route and nothing else is asked',
      () async {
        adapter.onGet(slim, (s) => s.reply(200, slimRows()));

        final users = await repo.fetchUsers();

        expect(users.map((u) => u.username), ['admin', 'zosia']);
        expect(users.map((u) => u.id), [1, 2]);
        expect(requested, [slim]);
      },
    );

    test(
      'an older server answers 422 and the full listing takes over',
      () async {
        // What a pre-1.2.6 server really does with this path: `/{user_id}` is
        // declared `int`, so "slim" fails validation rather than 404ing.
        adapter
          ..onGet(
            slim,
            (s) => s.reply(422, {'detail': 'value is not a valid integer'}),
          )
          ..onGet(full, (s) => s.reply(200, fullRows()));

        final users = await repo.fetchUsers();

        expect(users.map((u) => u.username), ['admin', 'zosia']);
        expect(requested, [slim, full]);
      },
    );

    test(
      'an API key on an older server is refused the slim route with 403',
      () async {
        adapter
          ..onGet(slim, (s) => s.reply(403, {'detail': 'administrative'}))
          ..onGet(full, (s) => s.reply(200, fullRows()));

        final users = await repo.fetchUsers();

        expect(users.map((u) => u.username), ['admin', 'zosia']);
        expect(requested, [slim, full]);
      },
    );

    test('the probe is paid for once, not on every refresh', () async {
      adapter
        ..onGet(slim, (s) => s.reply(422, {'detail': 'nope'}))
        ..onGet(full, (s) => s.reply(200, fullRows()));

      await repo.fetchUsers();
      await repo.fetchUsers();

      expect(requested, [slim, full, full]);
    });

    test('a server known to have the slim route is never re-probed', () async {
      adapter.onGet(slim, (s) => s.reply(200, slimRows()));

      await repo.fetchUsers();
      await repo.fetchUsers();

      expect(requested, [slim, slim]);
    });

    test('refused both listings → the exception the picker swallows', () async {
      adapter
        ..onGet(slim, (s) => s.reply(403, {'detail': 'nope'}))
        ..onGet(full, (s) => s.reply(403, {'detail': 'nope'}));

      await expectLater(repo.fetchUsers(), throwsA(isA<AuthException>()));
      expect(requested, [slim, full]);
    });

    test('a transport failure does not pin the fallback', () async {
      // No response means no evidence about the route. Concluding "no slim
      // listing" from an unreachable server would strand the session on the
      // full listing, which an API key can never read.
      adapter.onGet(
        slim,
        (s) => s.throws(
          408,
          DioException(
            requestOptions: RequestOptions(path: slim),
            type: DioExceptionType.connectionTimeout,
          ),
        ),
      );

      await expectLater(repo.fetchUsers(), throwsA(isA<NetworkException>()));
      expect(requested, [slim], reason: 'the full listing must not be tried');
    });

    test('a 401 is propagated rather than treated as a missing route', () async {
      // The session needs refreshing; both listings would answer the same way,
      // and pinning the fallback here would outlive the expired token.
      adapter.onGet(slim, (s) => s.reply(401, {'detail': 'Unauthorized'}));

      await expectLater(repo.fetchUsers(), throwsA(isA<AuthException>()));
      expect(requested, [slim]);
    });

    test('the full listing is sorted like the slim one', () async {
      // The server orders the full listing by created_at, so without sorting
      // the same people would come out in a different order depending on which
      // route answered.
      adapter
        ..onGet(slim, (s) => s.reply(422, {'detail': 'nope'}))
        ..onGet(full, (s) => s.reply(200, fullRows().reversed.toList()));

      final users = await repo.fetchUsers();

      expect(users.map((u) => u.username), ['admin', 'zosia']);
    });
  });
}
