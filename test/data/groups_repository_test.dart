import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/group_write.dart';
import 'package:bambuddy_mobile/data/groups_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late GroupsRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://s.local:8000'));
    adapter = DioAdapter(dio: dio);
    repo = GroupsRepository(dio);
  });

  test('list() parses what each group is and holds', () async {
    adapter.onGet(
      '/api/v1/groups/',
      (s) => s.reply(200, [
        {
          'id': 1,
          'name': 'Administrators',
          'description': 'Full access',
          'permissions': ['users:read', 'users:create'],
          'is_system': true,
          'user_count': 2,
          'created_at': '2025-06-01T10:00:00',
          'updated_at': '2025-06-01T10:00:00',
        },
        {
          'id': 7,
          'name': 'Domownicy',
          'description': null,
          'permissions': const <String>[],
          'is_system': false,
          'user_count': 0,
          'created_at': '2026-02-01T10:00:00',
          'updated_at': '2026-02-01T10:00:00',
        },
      ]),
    );

    final groups = await repo.list();
    expect(groups, hasLength(2));
    expect(groups.first.name, 'Administrators');
    expect(groups.first.isSystem, isTrue);
    expect(groups.first.permissions, hasLength(2));
    expect(groups.first.userCount, 2);
    expect(groups.last.description, isNull);
    expect(groups.last.isSystem, isFalse);
  });

  test('get() carries the member list the list view has no room for',
      () async {
    adapter.onGet(
      '/api/v1/groups/7',
      (s) => s.reply(200, {
        'id': 7,
        'name': 'Domownicy',
        'description': 'Drukują, nie kasują',
        'permissions': ['queue:create'],
        'is_system': false,
        'user_count': 2,
        'created_at': '2026-02-01T10:00:00',
        'updated_at': '2026-02-01T10:00:00',
        'users': [
          {'id': 2, 'username': 'zosia', 'is_active': true},
          {'id': 3, 'username': 'stary', 'is_active': false},
        ],
      }),
    );

    final group = await repo.get(7);
    expect(group.name, 'Domownicy');
    expect(group.members.map((m) => m.username), ['zosia', 'stary']);
    expect(group.members.last.isActive, isFalse);
  });

  test('a group from a server that sends no member list is simply empty',
      () async {
    adapter.onGet(
      '/api/v1/groups/7',
      (s) => s.reply(200, {
        'id': 7,
        'name': 'Domownicy',
        'permissions': const <String>[],
        'is_system': false,
        'user_count': 0,
        'created_at': '2026-02-01T10:00:00',
        'updated_at': '2026-02-01T10:00:00',
      }),
    );

    expect((await repo.get(7)).members, isEmpty);
  });

  test('adding a member hits the membership route', () async {
    adapter.onPost('/api/v1/groups/7/users/2', (s) => s.reply(204, null));
    final sent = captureRequests(dio);

    await repo.addMember(7, 2);

    expect(sent.calls, ['POST /api/v1/groups/7/users/2']);
  });

  test('removing a member hits the same route with DELETE', () async {
    adapter.onDelete('/api/v1/groups/7/users/2', (s) => s.reply(204, null));
    final sent = captureRequests(dio);

    await repo.removeMember(7, 2);

    expect(sent.calls, ['DELETE /api/v1/groups/7/users/2']);
  });

  test('a refused membership change keeps the reason', () async {
    adapter.onPost(
      '/api/v1/groups/7/users/2',
      (s) => s.reply(400, {'detail': 'User is already in this group'}),
    );

    await expectLater(
      repo.addMember(7, 2),
      throwsA(isA<ApiException>().having(
          (e) => e.detail, 'detail', 'User is already in this group')),
    );
  });

  test('permissions() reads the catalog the editor is built from', () async {
    adapter.onGet(
      '/api/v1/groups/permissions',
      (s) => s.reply(200, {
        'categories': [
          {
            'name': 'Queue',
            'permissions': [
              {'value': 'queue:read', 'label': 'View queue'},
              {'value': 'queue:create', 'label': 'Add to queue'},
            ],
          },
          {
            'name': 'User Management',
            'permissions': [
              {'value': 'users:read', 'label': 'View users'},
            ],
          },
        ],
        'all_permissions': ['queue:read', 'queue:create', 'users:read'],
      }),
    );

    final catalog = await repo.permissions();
    expect(catalog.all, hasLength(3));
    // Queue is one of the app's own; user administration goes behind the fold,
    // and so does any category name this app does not know.
    expect(catalog.everyday.map((c) => c.name), ['Queue']);
    expect(catalog.advanced.map((c) => c.name), ['User Management']);
    expect(catalog.everyday.single.permissions.first.label, 'View queue');
  });

  test('a permission with no label falls back to its own string', () async {
    adapter.onGet(
      '/api/v1/groups/permissions',
      (s) => s.reply(200, {
        'categories': [
          {
            'name': 'Queue',
            'permissions': [
              {'value': 'queue:read'},
            ],
          },
        ],
        'all_permissions': ['queue:read'],
      }),
    );

    final catalog = await repo.permissions();
    expect(catalog.categories.single.permissions.single.label, 'queue:read');
  });

  test('create sends the whole permission set', () async {
    Map<String, dynamic>? sent;
    adapter.onPost(
      '/api/v1/groups/',
      (s) => s.reply(201, {
        'id': 9,
        'name': 'Domownicy',
        'description': null,
        'permissions': ['queue:create'],
        'is_system': false,
        'user_count': 0,
        'created_at': '2026-08-04T10:00:00',
        'updated_at': '2026-08-04T10:00:00',
      }),
      data: Matchers.any,
    );
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (options.method == 'POST') sent = options.data as Map<String, dynamic>;
      handler.next(options);
    }));

    final created = await repo.create(const GroupCreateInput(
      name: 'Domownicy',
      permissions: ['queue:create'],
    ));

    expect(created.id, 9);
    expect(sent, {
      'name': 'Domownicy',
      'permissions': ['queue:create'],
    });
  });

  test('update sends only the fields it was given', () async {
    Map<String, dynamic>? sent;
    adapter.onPatch(
      '/api/v1/groups/9',
      (s) => s.reply(200, {
        'id': 9,
        'name': 'Domownicy',
        'description': 'Drukują',
        'permissions': const <String>[],
        'is_system': false,
        'user_count': 0,
        'created_at': '2026-08-04T10:00:00',
        'updated_at': '2026-08-04T10:00:00',
      }),
      data: Matchers.any,
    );
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (options.method == 'PATCH') sent = options.data as Map<String, dynamic>;
      handler.next(options);
    }));

    await repo.update(9, const GroupUpdateInput(description: 'Drukują'));

    expect(sent, {'description': 'Drukują'});
  });

  test('a system group refused by name keeps the reason', () async {
    adapter.onPatch(
      '/api/v1/groups/1',
      (s) => s.reply(400, {'detail': 'Cannot rename system groups'}),
      data: Matchers.any,
    );

    await expectLater(
      repo.update(1, const GroupUpdateInput(name: 'Admini')),
      throwsA(isA<ApiException>()
          .having((e) => e.detail, 'detail', 'Cannot rename system groups')),
    );
  });

  test('deleting a group hits its own path', () async {
    adapter.onDelete('/api/v1/groups/9', (s) => s.reply(204, null));
    final sent = captureRequests(dio);

    await repo.delete(9);

    expect(sent.calls, ['DELETE /api/v1/groups/9']);
  });

  test('an identity without groups:read gets a mapped 403', () async {
    adapter.onGet(
      '/api/v1/groups/',
      (s) => s.reply(403, {'detail': 'Not enough permissions'}),
    );

    expect(repo.list(), throwsA(isA<AppApiException>()));
  });
}
