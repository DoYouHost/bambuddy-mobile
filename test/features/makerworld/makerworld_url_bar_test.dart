import 'package:bambuddy_mobile/core/models/makerworld.dart';
import 'package:bambuddy_mobile/features/makerworld/makerworld_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  testWidgets('the resolve button is exactly as tall as the URL field',
      (tester) async {
    // It used to be forced to a constant 56, eight pixels taller than the
    // field next to it — and a constant would drift again the moment the
    // system font size changed the field's height.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          makerworldStatusProvider.overrideWith(
            (ref) async =>
                const MakerWorldStatus(hasCloudToken: true, canDownload: true),
          ),
        ],
        child: plApp(const MakerWorldScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final field = tester.getSize(find.byType(TextField));
    final button = tester.getSize(find.byType(FilledButton));

    expect(button.height, field.height);
  });
}
