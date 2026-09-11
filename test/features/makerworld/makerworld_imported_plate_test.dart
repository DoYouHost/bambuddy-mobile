import 'package:bambuddy_mobile/core/models/makerworld.dart';
import 'package:bambuddy_mobile/core/theme/dash_theme.dart';
import 'package:bambuddy_mobile/data/makerworld_repository.dart';
import 'package:bambuddy_mobile/features/makerworld/makerworld_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';

/// The "In library" row is a state badge wearing a disabled button, and its
/// green is the only thing separating "already yours" from "you cannot press
/// this". The ink was handed to `foregroundColor`, which a disabled button
/// resolves to null — so the badge rendered in Material's grey for as long as
/// it existed, and nothing could notice: no test in the suite read a rendered
/// button colour.
void main() {
  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(MakerWorldScreen)));

  testWidgets('an imported plate wears the accent, not the disabled grey', (
    tester,
  ) async {
    final dio = testDio();
    DioAdapter(dio: dio)
      ..onPost(
        '/api/v1/makerworld/resolve',
        (s) => s.reply(200, {
          'model_id': 7,
          'design': {'title': 'Mug Holder'},
          'instances': [
            {'profile_id': 11, 'name': 'Plate 1'},
          ],
        }),
        data: {'url': 'https://makerworld.com/models/7'},
      )
      ..onPost(
        '/api/v1/makerworld/import',
        (s) => s.reply(200, {'library_file_id': 3, 'filename': 'mug.3mf'}),
        data: {'model_id': 7, 'profile_id': 11},
      );

    await pumpPhone(
      tester,
      const MakerWorldScreen(),
      overrides: [
        fakeServerProfileOverride(),
        makerworldRepositoryProvider.overrideWithValue(
          MakerWorldRepository(dio),
        ),
        makerworldStatusProvider.overrideWith(
          (ref) async =>
              const MakerWorldStatus(hasCloudToken: true, canDownload: true),
        ),
        makerworldRecentImportsProvider.overrideWith((ref) async => const []),
      ],
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'https://makerworld.com/models/7',
    );
    await tester.tap(find.widgetWithText(FilledButton, l10n(tester).mwResolve));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, l10n(tester).mwImport));
    await tester.pumpAndSettle();

    final label = l10n(tester).mwInLibrary;
    final ink = (tester.renderObject(find.text(label)) as RenderParagraph)
        .text
        .style
        ?.color;

    expect(
      ink,
      DashTokens.of(
        tester.element(find.byType(MakerWorldScreen)),
      ).accentGreenInk.withValues(alpha: 0.6),
    );
  });
}
