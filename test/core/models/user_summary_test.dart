import 'package:bambuddy_mobile/core/models/user_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserSummary.fromJson', () {
    test('parsuje pełny rekord', () {
      final user =
          UserSummary.fromJson(const {'id': 3, 'username': 'kacper'});
      expect(user.id, 3);
      expect(user.username, 'kacper');
    });

    test('id jako string (tolerancja typu)', () {
      final user = UserSummary.fromJson(const {'id': '7', 'username': 'ala'});
      expect(user.id, 7);
    });

    test('puste / brakujące pola → bezpieczne defaulty', () {
      final user = UserSummary.fromJson(const {});
      expect(user.id, 0);
      expect(user.username, '?');
    });
  });
}
