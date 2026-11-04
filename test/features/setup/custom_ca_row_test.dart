import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bambuddy_mobile/core/api/custom_ca.dart';
import 'package:bambuddy_mobile/core/settings/settings_repository.dart';
import 'package:bambuddy_mobile/features/setup/custom_ca_row.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers.dart';

void main() {
  late SharedPreferences prefs;
  late _Picker picker;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    picker = _Picker();
    FilePicker.platform = picker;
    addTearDown(() => trustCustomCa(null));
  });

  Future<void> pump(WidgetTester tester) => pumpPhone(
    tester,
    const Scaffold(body: CustomCaRow()),
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );

  CustomCa? stored() => SettingsRepository(prefs).loadCustomCa();

  testWidgets('imports a CA file, then removes it', (tester) async {
    picker.answer = PlatformFile(
      name: 'home-root.crt',
      size: 0,
      bytes: Uint8List.fromList(
        File('test/fixtures/tls/ca.der').readAsBytesSync(),
      ),
    );
    await pump(tester);
    await tester.tap(find.text(pl.customCaImport));
    await tester.pumpAndSettle();

    expect(find.text(pl.customCaTrusted('home-root.crt')), findsOneWidget);
    expect(stored()?.name, 'home-root.crt');

    await tester.tap(find.byTooltip(pl.customCaRemove));
    await tester.pumpAndSettle();

    expect(find.text(pl.customCaImport), findsOneWidget);
    expect(stored(), isNull);
  });

  testWidgets('a file that is not a certificate is refused', (tester) async {
    picker.answer = PlatformFile(
      name: 'notes.txt',
      size: 0,
      bytes: Uint8List.fromList(utf8.encode('hello')),
    );
    await pump(tester);
    await tester.tap(find.text(pl.customCaImport));
    await tester.pumpAndSettle();

    expect(find.text(pl.customCaInvalid), findsOneWidget);
    expect(stored(), isNull);
  });

  testWidgets('backing out of the picker says nothing', (tester) async {
    await pump(tester);
    await tester.tap(find.text(pl.customCaImport));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(stored(), isNull);
  });

  testWidgets('a picker that fails says so', (tester) async {
    picker.fails = true;
    await pump(tester);
    await tester.tap(find.text(pl.customCaImport));
    await tester.pumpAndSettle();

    expect(find.text(pl.customCaPickFailed), findsOneWidget);
  });

  testWidgets('a second tap while the picker opens is dropped', (tester) async {
    picker.gate = Completer<void>();
    await pump(tester);
    await tester.tap(find.text(pl.customCaImport));
    await tester.pump();
    await tester.tap(find.text(pl.customCaImport));
    await tester.pump();
    picker.gate!.complete();
    await tester.pumpAndSettle();

    expect(picker.opened, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('leaving while the picker is open stores nothing', (
    tester,
  ) async {
    picker
      ..gate = Completer<void>()
      ..answer = PlatformFile(
        name: 'root.pem',
        size: 0,
        bytes: File('test/fixtures/tls/ca.pem').readAsBytesSync(),
      );
    await pump(tester);
    await tester.tap(find.text(pl.customCaImport));
    await tester.pump();
    await pumpPhone(
      tester,
      const SizedBox(),
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    picker.gate!.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(stored(), isNull);
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('a long file name fits at text scale $scale', (tester) async {
      await SettingsRepository(prefs).saveCustomCa(
        CustomCa.parse(
          'my-very-long-home-lab-root-certificate-authority-2026.pem',
          File('test/fixtures/tls/ca.pem').readAsBytesSync(),
        ),
      );
      await pumpPhone(
        tester,
        const Scaffold(body: CustomCaRow()),
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byTooltip(pl.customCaRemove), findsOneWidget);
    });
  }
}

class _Picker extends FilePicker {
  /// Null is a cancelled dialog.
  PlatformFile? answer;
  bool fails = false;
  Completer<void>? gate;
  int opened = 0;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    opened++;
    await gate?.future;
    if (fails) throw PlatformException(code: 'boom');
    final file = answer;
    return file == null ? null : FilePickerResult([file]);
  }
}
