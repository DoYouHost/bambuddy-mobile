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

  Future<void> pump(WidgetTester tester, {required bool edit}) async {
    await tester.pumpWidget(
      queueFormScreen(
        edit
            ? QueueItem.fromJson({
                'id': 5,
                'position': 1,
                'status': 'pending',
                'printer_id': 1,
                'archive_id': 77,
              })
            : archiveDraft(),
        mode: edit ? QueueEditMode.edit : QueueEditMode.create,
        extra: [
          serverUiFlagsProvider.overrideWith(
            (ref) async => {'billing_enabled': true},
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  FilledButton submit(WidgetTester tester, String id) => tester.widget(
    find.descendant(of: byLogId(id), matching: find.byType(FilledButton)),
  );

  testWidgets('a new job is not offered, and the form says why', (
    tester,
  ) async {
    await pump(tester, edit: false);

    expect(find.text(formL10n.queueBillingUseWeb), findsOneWidget);
    expect(submit(tester, 'queue_create.save').onPressed, isNull);
  });

  testWidgets('editing a queued job still saves', (tester) async {
    // The server checks the budget on an edit only when billing fields change.
    await pump(tester, edit: true);

    expect(find.text(formL10n.queueBillingUseWeb), findsNothing);
    expect(submit(tester, 'queue_edit.save').onPressed, isNotNull);
  });
}
