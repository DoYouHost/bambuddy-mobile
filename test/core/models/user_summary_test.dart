import 'package:bambuddy_mobile/core/models/user_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserSummary.fromJson', () {
    test('parses full record', () {
      final user = UserSummary.fromJson(const {'id': 3, 'username': 'kacper'});
      expect(user.id, 3);
      expect(user.username, 'kacper');
    });

    test('id as string (type tolerance)', () {
      final user = UserSummary.fromJson(const {'id': '7', 'username': 'ala'});
      expect(user.id, 7);
    });

    test('empty / missing fields → safe defaults', () {
      final user = UserSummary.fromJson(const {});
      expect(user.id, 0);
      expect(user.username, '?');
    });
  });
}
