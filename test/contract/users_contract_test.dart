import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/group_summary.dart';
import 'package:bambuddy_mobile/core/models/group_write.dart';
import 'package:bambuddy_mobile/core/models/permission_catalog.dart';
import 'package:bambuddy_mobile/core/models/user_items_count.dart';
import 'package:bambuddy_mobile/data/groups_repository.dart';
import 'package:bambuddy_mobile/data/users_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_harness.dart';

void main() {
  group('users and groups contract', skip: contractSkipReason, () {
    late Dio dio;
    late UsersRepository users;
    late GroupsRepository groups;
    final createdGroupIds = <int>[];

    setUpAll(() async {
      dio = await authenticatedDio();
      users = UsersRepository(dio);
      groups = GroupsRepository(dio);
    });

    tearDownAll(() async {
      for (final id in createdGroupIds) {
        try {
          await dio.delete<dynamic>(Endpoints.groupById(id));
        } catch (_) {}
      }
    });

    test('GET /users/ decodes user list into CurrentUser', () async {
      final list = await users.list();

      expect(list, isNotEmpty, reason: 'seed creates at least the admin account');
      final admin = list.first;
      expect(admin.id, greaterThanOrEqualTo(1));
      expect(admin.username, isNotEmpty);
      expect(admin.isAdmin, isTrue);
    });

    test('GET /users/{id}/items-count decodes counts into UserItemsCount', () async {
      final list = await users.list();
      final admin = list.first;

      final count = await users.itemsCount(admin.id);
      expect(count, isA<UserItemsCount>());
      expect(count.archives, greaterThanOrEqualTo(0));
      expect(count.queueItems, greaterThanOrEqualTo(0));
      expect(count.libraryFiles, greaterThanOrEqualTo(0));
    });

    test('GET /groups/ decodes system and user groups into GroupSummary', () async {
      final groupList = await groups.list();

      expect(groupList, isA<List<GroupSummary>>());
      for (final g in groupList) {
        expect(g.id, greaterThan(0));
        expect(g.name, isNotEmpty);
      }
    });

    test('GET /groups/permissions decodes full PermissionCatalog', () async {
      final catalog = await groups.permissions();

      expect(catalog, isA<PermissionCatalog>());
      expect(catalog.categories, isNotEmpty);
    });

    test('group lifecycle: create, detail, and delete round-trip', () async {
      final groupName = 'contract-grp-${DateTime.now().millisecondsSinceEpoch}';
      final created = await groups.create(
        GroupCreateInput(
          name: groupName,
          description: 'Created by contract test',
          permissions: const ['printers:read'],
        ),
      );
      createdGroupIds.add(created.id);

      expect(created.id, greaterThan(0));
      expect(created.name, groupName);

      final detail = await groups.get(created.id);
      expect(detail, isA<GroupDetail>());
      expect(detail.id, created.id);
      expect(detail.name, groupName);
      expect(detail.permissions, contains('printers:read'));

      await groups.delete(created.id);
      createdGroupIds.remove(created.id);

      final list = await groups.list();
      expect(list.any((g) => g.id == created.id), isFalse);
    });
  });
}
