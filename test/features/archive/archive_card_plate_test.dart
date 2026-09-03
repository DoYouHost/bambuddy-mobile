import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:bambuddy_mobile/features/archive/archive_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Which plate an archived run printed. The server stored it all along but
/// reported null until 1.2.5.4 (#2796), so the card has to read an absent
/// value as "no plate was chosen" — the common case, and the one where naming
/// a plate on every row would be noise rather than information.
class _FakeArchiveNotifier extends ArchiveNotifier {
  _FakeArchiveNotifier(this._items);

  final List<Archive> _items;

  @override
  Future<List<Archive>> build() async => _items;
}

/// Null profile → the thumbnail draws its placeholder instead of hitting the
/// network.
class _NullProfileNotifier extends ServerProfileNotifier {
  @override
  ServerProfile? build() => null;
}

Widget _screen(List<Archive> items) => ProviderScope(
      overrides: [
        archiveProvider.overrideWith(() => _FakeArchiveNotifier(items)),
        serverProfileProvider.overrideWith(_NullProfileNotifier.new),
      ],
      child: plApp(const ArchiveScreen()),
    );

Archive _archive({int? plateId}) => Archive(
      id: 1,
      filename: 'multi.gcode.3mf',
      status: 'completed',
      printName: 'Benchy',
      filamentType: 'PETG',
      plateId: plateId,
    );

void main() {
  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(ArchiveScreen)));

  testWidgets('a run with a chosen plate says which one', (tester) async {
    await tester.pumpWidget(_screen([_archive(plateId: 3)]));
    await tester.pumpAndSettle();

    expect(find.textContaining(l10n(tester).archivePlate(3)), findsOneWidget);
  });

  testWidgets('a run with no plate recorded says nothing about plates',
      (tester) async {
    await tester.pumpWidget(_screen([_archive()]));
    await tester.pumpAndSettle();

    // Not even plate 1: an app-started print never sends a plate, so claiming
    // one would be inventing it.
    expect(find.textContaining(l10n(tester).archivePlate(1)), findsNothing);
    expect(find.textContaining('PETG'), findsOneWidget);
  });
}
