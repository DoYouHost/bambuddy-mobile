import 'dart:async';

import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/features/queue/queue_edit_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';
import 'queue_form_harness.dart';

/// A billing server refuses a new queue item without a cost center, which the
/// app cannot pick yet (maziggy/bambuddy #3256): the form says so up front and
/// does not offer to send what will be refused.
void main() {
  setUp(setUpQueueForm);

  bool billing({Map<String, dynamic>? flags, Map<String, dynamic>? settings}) {
    final container = ProviderContainer(
      overrides: [
        serverUiFlagsProvider.overrideWith((ref) async => flags ?? const {}),
        serverSettingsOverride(settings ?? const {}),
      ],
    );
    addTearDown(container.dispose);
    container
      ..listen(serverUiFlagsProvider, (_, _) {})
      ..listen(serverSettingsProvider, (_, _) {});
    return container.read(billingEnabledProvider);
  }

  test(
    'the UI flags answer first, the full settings on an older server',
    () async {
      Future<bool> settled({
        Map<String, dynamic>? flags,
        Map<String, dynamic>? settings,
      }) async {
        final container = ProviderContainer(
          overrides: [
            serverUiFlagsProvider.overrideWith(
              (ref) async => flags ?? const {},
            ),
            serverSettingsOverride(settings ?? const {}),
          ],
        );
        addTearDown(container.dispose);
        await container.read(serverUiFlagsProvider.future);
        await container.read(serverSettingsProvider.future);
        return container.read(billingEnabledProvider);
      }

      expect(await settled(flags: {'billing_enabled': true}), isTrue);
      // A non-admin's settings read is refused, so only the flags know.
      expect(
        await settled(flags: {'billing_enabled': true}, settings: const {}),
        isTrue,
      );
      expect(await settled(settings: {'billing_enabled': true}), isTrue);
      expect(await settled(flags: {'billing_enabled': false}), isFalse);
      expect(await settled(), isFalse);
      expect(billing(), isFalse, reason: 'false until either answers');
    },
  );

  test('the flag is read afresh for the next screen that asks', () async {
    // Switched on in the web while the app runs, or a read that failed: either
    // must not stand for the rest of the session.
    var reads = 0;
    final container = ProviderContainer(
      overrides: [
        serverUiFlagsProvider.overrideWith((ref) async {
          reads++;
          return {'billing_enabled': reads > 1};
        }),
        serverSettingsOverride(const {}),
      ],
    );
    addTearDown(container.dispose);

    var sub = container.listen(billingEnabledProvider, (_, _) {});
    await container.read(serverUiFlagsProvider.future);
    expect(sub.read(), isFalse);
    sub.close();
    await Future<void>.delayed(Duration.zero);

    sub = container.listen(billingEnabledProvider, (_, _) {});
    await container.read(serverUiFlagsProvider.future);
    expect(sub.read(), isTrue);
    expect(reads, 2);
  });

  Future<void> pump(WidgetTester tester, {QueueItem? item}) async {
    await tester.pumpWidget(
      queueFormScreen(
        item ?? archiveDraft(),
        mode: item == null ? QueueEditMode.create : QueueEditMode.edit,
        extra: [
          serverUiFlagsProvider.overrideWith(
            (ref) async => {'billing_enabled': true},
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  QueueItem queued({int? costCenter}) => QueueItem.fromJson({
    'id': 5,
    'position': 1,
    'status': 'pending',
    'printer_id': 1,
    'archive_id': 77,
    'cost_center_id': costCenter,
  });

  FilledButton submit(WidgetTester tester, String id) => tester.widget(
    find.descendant(of: byLogId(id), matching: find.byType(FilledButton)),
  );

  testWidgets('a new job is not offered, and the form says why', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text(formL10n.queueBillingUseWeb), findsOneWidget);
    expect(submit(tester, 'queue_create.save').onPressed, isNull);
  });

  testWidgets('an item with no cost center cannot be saved either', (
    tester,
  ) async {
    // `update_queue_item` checks the budget on every PATCH.
    await pump(tester, item: queued());

    expect(find.text(formL10n.queueBillingUseWeb), findsOneWidget);
    expect(submit(tester, 'queue_edit.save').onPressed, isNull);
  });

  testWidgets('an item queued in the web with a cost center still saves', (
    tester,
  ) async {
    await pump(tester, item: queued(costCenter: 3));

    expect(find.text(formL10n.queueBillingUseWeb), findsNothing);
    expect(submit(tester, 'queue_edit.save').onPressed, isNotNull);
  });

  testWidgets('submit waits for the flag, without flashing the note', (
    tester,
  ) async {
    final flags = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      queueFormScreen(
        archiveDraft(),
        extra: [serverUiFlagsProvider.overrideWith((ref) => flags.future)],
      ),
    );
    await tester.pump();

    expect(submit(tester, 'queue_create.save').onPressed, isNull);
    expect(find.text(formL10n.queueBillingUseWeb), findsNothing);

    flags.complete({'billing_enabled': false});
    await tester.pumpAndSettle();
    expect(submit(tester, 'queue_create.save').onPressed, isNotNull);
  });

  testWidgets('a job with a cost center does not wait for the flag', (
    tester,
  ) async {
    await tester.pumpWidget(
      queueFormScreen(
        queued(costCenter: 3),
        mode: QueueEditMode.edit,
        extra: [
          serverUiFlagsProvider.overrideWith(
            (ref) => Completer<Map<String, dynamic>>().future,
          ),
        ],
      ),
    );
    await tester.pump();

    expect(submit(tester, 'queue_edit.save').onPressed, isNotNull);
  });

  test('an action outside a build waits for the answer', () async {
    Future<bool> settled(
      Map<String, dynamic> flags,
      Map<String, dynamic> settings,
    ) {
      final container = ProviderContainer(
        overrides: [
          serverUiFlagsProvider.overrideWith((ref) async => flags),
          serverSettingsOverride(settings),
        ],
      );
      addTearDown(container.dispose);
      return settledBillingEnabled(container);
    }

    expect(await settled({'billing_enabled': true}, const {}), isTrue);
    expect(await settled(const {}, {'billing_enabled': true}), isTrue);
    expect(await settled({'billing_enabled': false}, const {}), isFalse);
  });
}
