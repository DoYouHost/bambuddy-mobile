import 'package:bambuddy_mobile/core/notifications/outcome_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a prompt reaches a listener and waits for a shell that is not',
    () async {
      final heard = <int>[];
      final sub = outcomePrompts.stream.listen(heard.add);
      addTearDown(sub.cancel);

      outcomePrompts.post(82);
      await Future<void>.delayed(Duration.zero);

      expect(heard, [82]);
      expect(outcomePrompts.take(), 82);
      expect(outcomePrompts.take(), isNull, reason: 'one tap, one sheet');
    },
  );
}
