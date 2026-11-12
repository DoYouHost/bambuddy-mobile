import 'package:bambuddy_mobile/core/api/action_outcome.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/features/queue/queue_removal.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers.dart';

void main() {
  Future<ScaffoldMessengerState> pumpMessenger(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    return tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger));
  }

  ActionOutcome refused(String? detail) => ActionOutcome.failed(
    ApiException(AppErrorCode.badResponse, statusCode: 400, detail: detail),
  );

  testWidgets('success snacks the ok text', (tester) async {
    final messenger = await pumpMessenger(tester);
    snackQueueOutcome(messenger, ActionOutcome.ok, en, ok: en.queueResumed(0));
    await tester.pump();
    expect(find.text(en.queueResumed(0)), findsOneWidget);
  });

  testWidgets('success without an ok text says nothing', (tester) async {
    final messenger = await pumpMessenger(tester);
    snackQueueOutcome(messenger, ActionOutcome.ok, en);
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a known refusal replaces the ok text', (tester) async {
    final messenger = await pumpMessenger(tester);
    snackQueueOutcome(
      messenger,
      refused('Can only update pending items'),
      en,
      ok: en.queueEditSaved,
    );
    await tester.pump();
    expect(find.text(en.queueRemovalStatusChanged), findsOneWidget);
    expect(find.text(en.queueEditSaved), findsNothing);
  });

  testWidgets('an unexplained failure still says something without ok', (
    tester,
  ) async {
    final messenger = await pumpMessenger(tester);
    snackQueueOutcome(messenger, refused(null), en);
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('an unknown refusal is quoted', (tester) async {
    final messenger = await pumpMessenger(tester);
    snackQueueOutcome(messenger, refused('Something odd happened'), en);
    await tester.pump();
    expect(find.text('Something odd happened'), findsOneWidget);
  });
}
