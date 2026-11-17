import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/features/common/section_label.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(plApp(Scaffold(body: child)));

  testWidgets('says its words in capitals, whatever the translation holds', (
    tester,
  ) async {
    await pump(tester, SectionLabel(pl.aboutLicenseHeader));

    expect(find.text(pl.aboutLicenseHeader.toUpperCase()), findsOneWidget);
    expect(find.text(pl.aboutLicenseHeader), findsNothing);
  });

  testWidgets('a string that is already in capitals reads the same', (
    tester,
  ) async {
    await pump(tester, SectionLabel(pl.groupsPermissionsHeader));

    expect(find.text(pl.groupsPermissionsHeader), findsOneWidget);
  });

  testWidgets('every heading has the one look: bold, secondary ink, wide', (
    tester,
  ) async {
    await pump(tester, SectionLabel(pl.queueEditTarget));
    final shown = find.text(pl.queueEditTarget.toUpperCase());

    final style = tester.widget<Text>(shown).style!;
    final t = DashTokens.of(tester.element(shown));
    expect(style.fontSize, t.bodyBold.fontSize);
    expect(style.fontWeight, t.bodyBold.fontWeight);
    expect(style.color, t.textSecondary);
    expect(style.letterSpacing, DashTracking.caps);
  });

  testWidgets('is announced as a heading', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, SectionLabel(pl.queueEditTarget));
    final shown = find.text(pl.queueEditTarget.toUpperCase());

    expect(
      tester.getSemantics(shown),
      isSemantics(label: pl.queueEditTarget.toUpperCase(), isHeader: true),
    );
    handle.dispose();
  });

  testWidgets('gives way in a row with controls when it is told to', (
    tester,
  ) async {
    await pump(
      tester,
      const SizedBox(
        width: 60,
        child: SectionLabel(
          'Bardzo długi nagłówek sekcji',
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.widget<Text>(find.byType(Text)).overflow,
      TextOverflow.ellipsis,
    );
  });
}
