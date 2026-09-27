import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/router.dart';
import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the probe records, and how, is tested in `app_diagnostics` against a
/// router the test builds itself. This is the part that can only be asked here:
/// whether *this* app's router is actually wired to it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the app router reports every tab navigator to the probe', () async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final shell = container
        .read(routerProvider)
        .configuration
        .routes
        .whereType<StatefulShellRoute>()
        .single;

    for (final branch in shell.branches) {
      expect(
        branch.observers?.whereType<ModalObserver>(),
        isNotEmpty,
        reason: 'a sheet opened in this tab would go unrecorded',
      );
    }
  });
}
