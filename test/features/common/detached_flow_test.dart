import 'package:bambuddy_mobile/features/common/detached_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Both claims here are about what is still usable *after* the screen that
/// started the flow is gone — a dismissed sheet, or a card the next status
/// frame rebuilt, while the request it fired is still in the air.
void main() {
  // The default is what a container built on the spot would answer, so a test
  // that reads the override is reading the app's own container and no other.
  final serverAnswer = Provider((ref) => 'a container built on the spot');

  /// The screen is swapped under a `ProviderScope` and `MaterialApp` that stay,
  /// which is what a popped route does: the app keeps its container and its
  /// messenger, the widget that took the handles does not. A `Scaffold` has to
  /// be somewhere on screen for the bar to have a place to sit — the messenger
  /// outliving the flow is not the same as the bar having room.
  Future<DetachedHandles> detachThenLoseTheScreen(WidgetTester tester) async {
    late DetachedHandles handles;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [serverAnswer.overrideWithValue('from the app container')],
        child: plApp(
          Scaffold(
            body: Builder(
              builder: (context) {
                handles = detachFrom(context);
                return const Text('the screen');
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [serverAnswer.overrideWithValue('from the app container')],
        child: plApp(const Scaffold(body: Text('the screen is gone'))),
      ),
    );
    expect(find.text('the screen'), findsNothing);
    return handles;
  }

  testWidgets('the messenger still speaks once the screen is gone', (
    tester,
  ) async {
    final handles = await detachThenLoseTheScreen(tester);

    handles.messenger.showSnackBar(
      const SnackBar(content: Text('the action failed')),
    );
    await tester.pump();

    expect(find.text('the action failed'), findsOneWidget);
  });

  testWidgets('reads go through the app container, not a fresh one', (
    tester,
  ) async {
    final handles = await detachThenLoseTheScreen(tester);

    expect(handles.providers.read(serverAnswer), 'from the app container');
  });
}
