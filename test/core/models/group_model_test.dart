import 'package:bambuddy_mobile/core/models/group_summary.dart';
import 'package:bambuddy_mobile/core/models/group_write.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GroupSummary', () {
    test('fromJson parses summary fields with defensive defaults', () {
      final json = {
        'id': 1,
        'name': 'Operators',
        'description': 'Print operators',
        'permissions': ['printers:read', 'queue:create'],
        'is_system': false,
        'user_count': 5,
      };

      final summary = GroupSummary.fromJson(json);

      expect(summary.id, 1);
      expect(summary.name, 'Operators');
      expect(summary.description, 'Print operators');
      expect(summary.permissions, ['printers:read', 'queue:create']);
      expect(summary.isSystem, isFalse);
      expect(summary.userCount, 5);
    });

    test('fromJson handles null and missing fields gracefully', () {
      final summary = GroupSummary.fromJson({'id': '2', 'name': null});

      expect(summary.id, 2);
      expect(summary.name, '');
      expect(summary.description, isNull);
      expect(summary.permissions, isEmpty);
      expect(summary.isSystem, isFalse);
      expect(summary.userCount, 0);
    });
  });

  group('GroupDetail', () {
    test('fromJson parses members list alongside summary', () {
      final json = {
        'id': 10,
        'name': 'Maintainers',
        'is_system': true,
        'user_count': 2,
        'users': [
          {'id': 101, 'username': 'alice', 'is_active': true},
          {'id': 102, 'username': 'bob', 'is_active': false},
        ],
      };

      final detail = GroupDetail.fromJson(json);

      expect(detail.id, 10);
      expect(detail.name, 'Maintainers');
      expect(detail.isSystem, isTrue);
      expect(detail.members, hasLength(2));
      expect(detail.members[0].id, 101);
      expect(detail.members[0].username, 'alice');
      expect(detail.members[0].isActive, isTrue);
      expect(detail.members[1].id, 102);
      expect(detail.members[1].username, 'bob');
      expect(detail.members[1].isActive, isFalse);
    });
  });

  group('Group inputs serialization', () {
    test('GroupCreateInput converts to JSON', () {
      const input = GroupCreateInput(
        name: 'New Group',
        description: 'A description',
        permissions: ['printers:read'],
      );

      expect(input.toJson(), {
        'name': 'New Group',
        'description': 'A description',
        'permissions': ['printers:read'],
      });
    });

    test('GroupCreateInput omits description when null', () {
      const input = GroupCreateInput(
        name: 'New Group',
        permissions: [],
      );

      expect(input.toJson(), {
        'name': 'New Group',
        'permissions': [],
      });
    });

    test('GroupUpdateInput omits unset fields and tracks isEmpty', () {
      const empty = GroupUpdateInput();
      expect(empty.isEmpty, isTrue);
      expect(empty.toJson(), isEmpty);

      const partial = GroupUpdateInput(name: 'Updated Name');
      expect(partial.isEmpty, isFalse);
      expect(partial.toJson(), {'name': 'Updated Name'});

      const full = GroupUpdateInput(
        name: 'New Name',
        description: 'New desc',
        permissions: ['archive:read'],
      );
      expect(full.isEmpty, isFalse);
      expect(full.toJson(), {
        'name': 'New Name',
        'description': 'New desc',
        'permissions': ['archive:read'],
      });
    });
  });
}
