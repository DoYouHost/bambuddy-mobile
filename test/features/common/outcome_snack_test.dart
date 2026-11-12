import 'package:bambuddy_mobile/core/api/action_outcome.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/features/common/outcome_snack.dart';
import 'package:bambuddy_mobile/l10n/error_messages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';

void main() {
  const failed = ActionFailed(ApiException(AppErrorCode.serverUnreachable));

  Future<ScaffoldMessengerState> harness(WidgetTester tester) async {
    late ScaffoldMessengerState messenger;
    await tester.pumpWidget(
      plApp(
        Builder(
          builder: (context) {
            messenger = ScaffoldMessenger.of(context);
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    );
    return messenger;
  }

  testWidgets('a failure shows the failure wording', (tester) async {
    final messenger = await harness(tester);

    snackOutcome(messenger, failed, pl);
    await tester.pump();

    expect(find.text(failed.messageFor(pl)!), findsOneWidget);
  });

  testWidgets('a failure beats the fallback', (tester) async {
    final messenger = await harness(tester);

    snackOutcome(messenger, failed, pl, fallback: pl.cancel);
    await tester.pump();

    expect(find.text(failed.messageFor(pl)!), findsOneWidget);
    expect(find.text(pl.cancel), findsNothing);
  });

  testWidgets('a success shows the fallback', (tester) async {
    final messenger = await harness(tester);

    snackOutcome(messenger, ActionOutcome.ok, pl, fallback: pl.cancel);
    await tester.pump();

    expect(find.text(pl.cancel), findsOneWidget);
  });

  testWidgets('a success without a fallback stays silent', (tester) async {
    final messenger = await harness(tester);

    snackOutcome(messenger, ActionOutcome.ok, pl);
    await tester.pump();

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a new message replaces the one on screen instead of queueing', (
    tester,
  ) async {
    final messenger = await harness(tester);

    snackOutcome(messenger, ActionOutcome.ok, pl, fallback: pl.cancel);
    snackOutcome(messenger, failed, pl);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(failed.messageFor(pl)!), findsOneWidget);
    expect(find.text(pl.cancel), findsNothing);
  });
}
