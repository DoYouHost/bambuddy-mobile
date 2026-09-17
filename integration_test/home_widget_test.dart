import 'package:flutter_test/flutter_test.dart';
import 'package:home_widget/home_widget.dart';
import 'package:integration_test/integration_test.dart';

/// What a home-screen widget upgrade can quietly break: the store the plugin
/// writes into, and the provider class it hands to the launcher. Neither is
/// visible from a host test — `home_widget` answers there through a missing
/// plugin, not through Android.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a published value comes back out of the widget store', (
    tester,
  ) async {
    await HomeWidget.saveWidgetData<String>('multi_title', 'Farm');
    await HomeWidget.saveWidgetData<int>('multi_printing', 3);

    expect(await HomeWidget.getWidgetData<String>('multi_title'), 'Farm');
    expect(await HomeWidget.getWidgetData<int>('multi_printing'), 3);
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
