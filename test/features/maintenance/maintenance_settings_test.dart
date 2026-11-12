import 'package:bambuddy_mobile/core/api/action_outcome.dart';
import 'package:bambuddy_mobile/core/models/maintenance.dart';
import 'package:bambuddy_mobile/features/maintenance/maintenance_providers.dart';
import 'package:bambuddy_mobile/features/maintenance/maintenance_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// The type is written, and the answer is something the app cannot read: the
/// write fails with something that is not an `AppApiException`.
class _UnreadableTypes extends MaintenanceTypesNotifier {
  @override
  Future<ActionOutcome> create(
    MaintenanceTypeDraft draft,
    List<int> printerIds,
  ) async => throw StateError('unreadable answer');
}

void main() {
  testWidgets('a type that fails to save with an unexpected error unlocks the '
      'sheet, and still reports it', (tester) async {
    await pumpPhone(
      tester,
      const MaintenanceSettingsScreen(),
      overrides: [
        noServerProfileOverride,
        maintenanceTypesProvider.overrideWith(_UnreadableTypes.new),
      ],
    );
    await tester.pumpAndSettle();
    await tester.tap(byLogId('maintenance_settings.add_type'));
    await tester.pumpAndSettle();
    await tester.enterText(byLogId('maintenance_type_form.name'), 'Lube rods');
    await tester.enterText(byLogId('maintenance_type_form.interval'), '100');
    await tester.pump();

    final errors = await tapCapturingErrors(
      tester,
      byLogId('maintenance_type_form.save'),
    );

    expect(errors.single, isA<StateError>());
    expect(buttonAt(tester, 'maintenance_type_form.save').onPressed, isNotNull);
  });
}
