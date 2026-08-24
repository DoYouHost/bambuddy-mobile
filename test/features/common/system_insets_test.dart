import 'package:bambuddy_mobile/features/common/system_insets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Pumps [child] under a MediaQuery whose bottom viewPadding is [inset] and
  /// returns what `withSystemNavInset` computed there.
  Future<EdgeInsets> resolve(
    WidgetTester tester, {
    required double inset,
    required EdgeInsets base,
  }) async {
    late EdgeInsets result;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(viewPadding: EdgeInsets.only(bottom: inset)),
        child: Builder(
          builder: (context) {
            result = withSystemNavInset(context, base);
            return const SizedBox();
          },
        ),
      ),
    );
    return result;
  }

  testWidgets('adds the system navigation inset to the bottom only', (
    tester,
  ) async {
    final padding = await resolve(
      tester,
      inset: 48,
      base: const EdgeInsets.fromLTRB(12, 8, 16, 24),
    );

    expect(padding, const EdgeInsets.fromLTRB(12, 8, 16, 72));
  });

  testWidgets('leaves the padding untouched without an inset', (tester) async {
    final padding = await resolve(
      tester,
      inset: 0,
      base: const EdgeInsets.all(16),
    );

    expect(padding, const EdgeInsets.all(16));
  });

  testWidgets('a zero base still clears the navigation bar', (tester) async {
    final padding = await resolve(
      tester,
      inset: 24,
      base: EdgeInsets.zero,
    );

    expect(padding, const EdgeInsets.only(bottom: 24));
  });
}
