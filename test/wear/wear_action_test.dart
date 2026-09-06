import 'dart:async';

import 'package:bambuddy_mobile/wear/wear_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The guards every wear action shares. Each one here is a bug this app shipped
/// or nearly shipped, which is the reason they live in one mixin instead of
/// being remembered three times.
class _Host extends ConsumerStatefulWidget {
  const _Host({super.key});

  @override
  ConsumerState<_Host> createState() => _HostState();
}

class _HostState extends ConsumerState<_Host> with WearAction {
  int started = 0;
  int done = 0;
  Object? failure;

  Future<void> go(Future<void> Function() action) {
    started++;
    return run(
      action,
      onDone: () => done++,
      onError: (error) => failure = error,
    );
  }

  @override
  Widget build(BuildContext context) =>
      Directionality(textDirection: TextDirection.ltr, child: Text('$busy'));
}

void main() {
  final key = GlobalKey<State<_Host>>();

  Future<_HostState> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(child: _Host(key: key)));
    return key.currentState! as _HostState;
  }

  testWidgets('busy while the action runs, idle again after it', (
    tester,
  ) async {
    final host = await pumpHost(tester);
    final gate = Completer<void>();

    final call = host.go(() => gate.future);
    await tester.pump();
    expect(host.busy, isTrue);
    expect(find.text('true'), findsOneWidget);

    gate.complete();
    await call;
    await tester.pump();
    expect(host.busy, isFalse);
    expect(host.done, 1);
  });

  testWidgets('a second call while one is in flight is dropped', (
    tester,
  ) async {
    final host = await pumpHost(tester);
    final gate = Completer<void>();
    var runs = 0;

    final first = host.go(() {
      runs++;
      return gate.future;
    });
    await tester.pump();
    await host.go(() async => runs++);

    expect(runs, 1, reason: 'the second tap must not start a second write');
    gate.complete();
    await first;
    await tester.pump();
    // ...and the gate lifts once the first one is done.
    await host.go(() async => runs++);
    expect(runs, 2);
  });

  testWidgets('a failure reaches onError and still clears busy', (
    tester,
  ) async {
    final host = await pumpHost(tester);

    await host.go(() async => throw Exception('keystore is gone'));
    await tester.pump();

    expect(host.failure.toString(), contains('keystore'));
    expect(host.done, 0);
    // The spinner coming back is what leaves a way out of a failed step.
    expect(host.busy, isFalse);
  });

  testWidgets('nothing fires once the widget is gone', (tester) async {
    final host = await pumpHost(tester);
    final gate = Completer<void>();

    final call = host.go(() => gate.future);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete();
    await call;

    // No onDone, no setState on a disposed State — that last one is what throws.
    expect(host.done, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failure after the widget is gone is swallowed too', (
    tester,
  ) async {
    final host = await pumpHost(tester);
    final gate = Completer<void>();

    final call = host.go(() => gate.future);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    gate.completeError(Exception('too late'));
    await call;

    expect(host.failure, isNull);
    expect(tester.takeException(), isNull);
  });
}
