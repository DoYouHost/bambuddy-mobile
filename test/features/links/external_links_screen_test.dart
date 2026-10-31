import 'package:bambuddy_mobile/core/models/external_link.dart';
import 'package:bambuddy_mobile/features/links/external_links_providers.dart';
import 'package:bambuddy_mobile/features/links/external_links_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

ExternalLink _link({
  int id = 1,
  String name = 'Orders',
  String url = 'http://orders.lan:8080/todo',
  int? badge,
  bool icon = false,
}) => ExternalLink(
  id: id,
  name: name,
  url: url,
  badgeCount: badge,
  hasCustomIcon: icon,
);

void main() {
  Future<void> pump(
    WidgetTester tester,
    List<ExternalLink> links, {
    double scale = 1,
  }) async {
    useLogicalWindow(tester, const Size(360, 800));
    await pumpPhone(
      tester,
      const ExternalLinksScreen(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      overrides: [
        noServerProfileOverride,
        externalLinksProvider.overrideWith((ref) async => links),
      ],
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists each link with its host and shows a count only above 0', (
    tester,
  ) async {
    await pump(tester, [
      _link(name: 'Orders', badge: 3),
      _link(id: 2, name: 'Wiki', url: 'https://wiki.lan', badge: 0),
      _link(id: 3, name: 'Slicer', url: 'http://slicer.lan', badge: null),
    ]);

    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('orders.lan:8080'), findsOneWidget);
    expect(find.text('wiki.lan'), findsOneWidget);
    expect(find.byType(ExternalLinkBadge), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('a count past 99 reads 99+', (tester) async {
    await pump(tester, [_link(badge: 100)]);
    expect(find.text('99+'), findsOneWidget);
  });

  testWidgets('no links says so', (tester) async {
    await pump(tester, const []);
    expect(find.text(pl.linkedAppsEmpty), findsOneWidget);
  });

  testWidgets('a login in the URL is never drawn', (tester) async {
    await pump(tester, [_link(url: 'http://admin:hunter2@orders.lan')]);
    expect(find.textContaining('hunter2'), findsNothing);
    expect(find.textContaining('admin'), findsNothing);
  });

  testWidgets(
    'an uploaded icon that cannot be drawn falls back to the letter',
    (tester) async {
      await pump(tester, [_link(name: 'orders', icon: true)]);
      expect(find.text('O'), findsOneWidget);
    },
  );

  testWidgets('a link that is not a web address is refused, not launched', (
    tester,
  ) async {
    await pump(tester, [_link(url: 'intent://scan#Intent;scheme=zxing;end')]);
    await tester.tap(find.text('Orders'));
    await tester.pump();
    expect(find.text(pl.linkOpenFailed), findsOneWidget);
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('fits at ${scale * 100}% text with a long name and a count', (
      tester,
    ) async {
      await pump(tester, [
        _link(
          name: 'Bambuddy Orders and the whole print farm to-do list',
          url: 'http://a-very-long-hostname.print-farm.example.lan:8080',
          badge: 1234,
        ),
        _link(id: 2, name: 'Spoolman'),
      ], scale: scale);
      expect(tester.takeException(), isNull);
    });
  }
}
