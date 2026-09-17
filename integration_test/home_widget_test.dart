import 'package:flutter_test/flutter_test.dart';
import 'package:home_widget/home_widget.dart';
import 'package:integration_test/integration_test.dart';

/// What a home-screen widget upgrade can quietly break: the store the plugin
/// writes into, and the provider class it hands to the launcher. Neither is
/// visible from a host test — `home_widget` answers there through a missing
/// plugin, not through Android.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Keys of its own, not the ones the publishers use: writing `multi_title`
  // here leaves the widget on the test device showing this test's value until
  // the app publishes again, and a second run would read the first run's value
  // back even if saving had stopped working.
  const text = 'integration_test_text';
  const number = 'integration_test_number';

  Future<void> clear() async {
    await HomeWidget.saveWidgetData<String>(text, null);
    await HomeWidget.saveWidgetData<int>(number, null);
  }

  // Both ends: a run killed halfway leaves values behind, and reading one of
  // those back would pass a test whose write had stopped working.
  setUp(clear);
  tearDown(clear);

  testWidgets('a published value comes back out of the widget store', (
    tester,
  ) async {
    await HomeWidget.saveWidgetData<String>(text, 'Farm');
    await HomeWidget.saveWidgetData<int>(number, 3);

    expect(await HomeWidget.getWidgetData<String>(text), 'Farm');
    expect(await HomeWidget.getWidgetData<int>(number), 3);
  });

  testWidgets('both providers answer an update by name', (tester) async {
    // The names are the ones the publishers use; a renamed or unresolvable
    // provider is how a widget stops refreshing without anything failing in
    // Dart.
    await expectLater(
      HomeWidget.updateWidget(
        androidName: 'BambuddyWidgetProvider',
        qualifiedAndroidName:
            'page.codeberg.morganmlgman.bambuddy_mobile.BambuddyWidgetProvider',
      ),
      completion(isTrue),
    );
    await expectLater(
      HomeWidget.updateWidget(
        androidName: 'BambuddyMultiWidgetProvider',
        qualifiedAndroidName:
            'page.codeberg.morganmlgman.bambuddy_mobile.BambuddyMultiWidgetProvider',
      ),
      completion(isTrue),
    );
  });
}
