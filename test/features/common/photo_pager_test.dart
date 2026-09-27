import 'package:bambuddy_mobile/features/common/photo_pager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  Widget pager(List<String> paths, {int initialPage = 0}) => ProviderScope(
    overrides: [noServerProfileOverride, mediaAuthOverride()],
    child: plApp(
      Scaffold(
        body: PhotoPager(paths: paths, initialPage: initialPage),
      ),
    ),
  );

  testWidgets('opens on the page it was asked for', (tester) async {
    await tester.pumpWidget(pager(const ['/a', '/b', '/c'], initialPage: 2));
    await tester.pumpAndSettle();

    expect(find.text('3 / 3'), findsOneWidget);
  });

  testWidgets('a list that shrinks under it keeps the counter on the glass', (
    tester,
  ) async {
    await tester.pumpWidget(pager(const ['/a', '/b', '/c'], initialPage: 2));
    await tester.pumpAndSettle();

    await tester.pumpWidget(pager(const ['/a', '/b'], initialPage: 2));
    await tester.pumpAndSettle();

    expect(find.text('2 / 2'), findsOneWidget);
  });
}
