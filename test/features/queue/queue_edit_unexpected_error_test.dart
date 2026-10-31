import 'package:bambuddy_mobile/core/api/action_outcome.dart';
import 'package:bambuddy_mobile/data/queue_repository.dart';
import 'package:bambuddy_mobile/features/queue/queue_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';
import 'queue_form_harness.dart';

/// The queue's write fails with something that is not an `AppApiException`: a
/// server answer the app cannot read. The app reports it rather than wording it,
/// and the form is not left locked behind it.
class _UnreadableQueue extends QueueNotifier {
  @override
  Future<ActionOutcome> runOnRepository(
    Future<void> Function(QueueRepository repo) action,
    String logId,
  ) async => throw StateError('unreadable answer');
}

void main() {
  setUp(setUpQueueForm);

  testWidgets('a create that fails with an unexpected error unlocks the form, '
      'and still reports it', (tester) async {
    await tester.pumpWidget(
      queueFormScreen(
        archiveDraft(),
        extra: [queueProvider.overrideWith(_UnreadableQueue.new)],
      ),
    );
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(FilledButton, pl.queueCreateSubmit);
    final errors = await tapCapturingErrors(tester, submit);

    expect(errors.single, isA<StateError>());
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
  });
}
