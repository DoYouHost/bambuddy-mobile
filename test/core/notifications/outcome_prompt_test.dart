import 'package:bambuddy_mobile/core/notifications/outcome_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a prompt reaches a listener and waits for a shell that is not',
    () async {
      final heard = <int>[];
      final sub = outcomePrompts.listen(heard.add);
      addTearDown(sub.cancel);

      postOutcomePrompt(82);
      await Future<void>.delayed(Duration.zero);

      expect(heard, [82]);
      expect(takeOutcomePrompt(), 82);
      expect(takeOutcomePrompt(), isNull, reason: 'one tap, one sheet');
    },
  );
}
