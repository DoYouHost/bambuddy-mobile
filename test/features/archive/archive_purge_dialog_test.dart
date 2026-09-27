import 'dart:async';

import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/models/archive_purge.dart';
import 'package:bambuddy_mobile/core/models/no_3mf_warning.dart';
import 'package:bambuddy_mobile/data/archive_repository.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:bambuddy_mobile/features/archive/archive_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

/// Answers each preview only when the test says so, per day threshold.
class _HeldPreviews extends ArchiveRepository {
  _HeldPreviews() : super(Dio());

  final pending = <int, Completer<ArchivePurgePreview>>{};

  @override
  Future<ArchivePurgePreview> purgePreview({
    required int olderThanDays,
    bool purgeStats = false,
  }) => (pending[olderThanDays] = Completer()).future;
}

/// The archive screen with [repository] behind it, and its purge dialog open.
Future<AppLocalizations> _openDialog(
  WidgetTester tester,
  _HeldPreviews repository,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        archiveListOverride(const [
          Archive(id: 1, filename: 'a.gcode.3mf', status: 'completed'),
        ]),
        no3mfWarningProvider.overrideWith((ref) async => No3mfWarning.none),
        sharedPreferencesProvider.overrideWithValue(prefs),
        archiveRepositoryProvider.overrideWithValue(repository),
        noServerProfileOverride,
      ],
      child: plApp(const ArchiveScreen()),
    ),
  );
  await tester.pumpAndSettle();
  final l10n = AppLocalizations.of(tester.element(find.byType(ArchiveScreen)));

  await tester.tap(find.byType(PopupMenuButton<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.archivePurgeOlder));
  await tester.pump();
  await tester.pump();
  return l10n;
}

void main() {
  testWidgets('a late answer for an older threshold does not replace the '
      'newer preview', (tester) async {
    final repository = _HeldPreviews();
    final l10n = await _openDialog(tester, repository);

    // The dialog asked for its default threshold; switch before it answers.
    // `pumpAndSettle` would wait on the loading bar forever.
    await tester.tap(find.byType(DropdownMenu<int>));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text(l10n.archivePurgeDaysOption(365)).last);
    await tester.pump(const Duration(milliseconds: 500));

    repository.pending[365]!.complete(
      const ArchivePurgePreview(count: 50, totalBytes: 2048),
    );
    await tester.pump();
    repository.pending[90]!.complete(
      const ArchivePurgePreview(count: 3, totalBytes: 1024),
    );
    await tester.pump();

    expect(find.textContaining('50'), findsOneWidget);
    expect(find.textContaining('3 '), findsNothing);
  });

  testWidgets('an unexpected failure shows the error, not an endless bar', (
    tester,
  ) async {
    final repository = _HeldPreviews();
    final l10n = await _openDialog(tester, repository);

    repository.pending[90]!.completeError(StateError('bug'));
    await tester.pump();

    expect(find.text(l10n.archivePurgePreviewError), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
