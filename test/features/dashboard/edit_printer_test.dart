import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_location.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/features/locations/printer_locations_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bambuddy_mobile/core/models/printer_create.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/add_printer_screen.dart';
import 'package:bambuddy_mobile/l10n/app_localizations_pl.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../../helpers.dart';

final _l10n = AppLocalizationsPl();

const _passing = {
  'overall': 'ok',
  'checks': [
    {'id': 'port_mqtt', 'status': 'pass'},
  ],
};

const _failing = {
  'overall': 'problems',
  'checks': [
    {'id': 'port_mqtt', 'status': 'fail'},
  ],
};

/// What the check sends for [_printer]: no access code, since none was typed.
const _diagnoseBody = {
  'ip_address': '192.168.4.21',
  'serial_number': '01P00A390800000',
};

final _keyProfile = fakeServerProfileOverride(authMode: AuthMode.apiKey);

Printer _printer({bool servesWearCost = true, double? rate = 0.25}) =>
    Printer.fromJson({
      'id': 1,
      'name': 'X1 Carbon',
      'model': 'X1C',
      'ip_address': '192.168.4.21',
      'serial_number': '01P00A390800000',
      'location': 'Workshop',
      'is_active': true,
      'auto_archive': true,
      if (servesWearCost) 'wear_cost_per_hour': rate,
    });

void main() {
  group('wear rate as typed', () {
    test('a plain number and a comma decimal are both accepted', () {
      expect(rateIsValid('0.25'), isTrue);
      expect(rateIsValid(' 1,5 '), isTrue);
    });

    test('empty means off, and is allowed', () {
      expect(rateIsValid(''), isTrue);
      expect(rateIsValid('   '), isTrue);
    });

    test('odd input is refused before the server 422s it', () {
      expect(rateIsValid('abc'), isFalse);
      expect(rateIsValid('-1'), isFalse);
      expect(rateIsValid('100001'), isFalse);
      expect(rateIsValid('1.2.3'), isFalse);
      expect(rateIsValid('100000'), isTrue);
    });

    test('a stored rate goes back into the field without a trailing .0', () {
      expect(fmtRate(2), '2');
      expect(fmtRate(0.25), '0.25');
    });
  });

  group('Printer.servesWearCost', () {
    test('a null rate still says the server knows the field', () {
      final p = _printer(rate: null);
      expect(p.servesWearCost, isTrue);
      expect(p.wearCostPerHour, isNull);
    });

    test('an older server sends no key at all', () {
      expect(_printer(servesWearCost: false).servesWearCost, isFalse);
    });
  });

  group('PrinterUpdate', () {
    PrinterUpdate update({
      String? accessCode,
      String? location,
      double? rate,
      bool send = true,
    }) => PrinterUpdate(
      name: 'X1',
      ipAddress: '10.0.0.2',
      autoArchive: true,
      isActive: false,
      accessCode: accessCode,
      location: location,
      wearCostPerHour: rate,
      sendWearCost: send,
    );

    test('an untyped access code is left out, a typed one is sent', () {
      expect(update().toJson().containsKey('access_code'), isFalse);
      expect(update(accessCode: '1234').toJson()['access_code'], '1234');
    });

    test('an empty location clears it rather than keeping the old one', () {
      final json = update(location: '').toJson();
      expect(json.containsKey('location'), isTrue);
      expect(json['location'], isNull);
    });

    test('"not set" clears the model instead of keeping the old one', () {
      final json = update().toJson();
      expect(json.containsKey('model'), isTrue);
      expect(json['model'], isNull);
    });

    test('a zero or empty rate turns wear off, as the web sends it', () {
      expect(update(rate: 0).toJson()['wear_cost_per_hour'], isNull);
      expect(update().toJson()['wear_cost_per_hour'], isNull);
      expect(update(rate: 1.5).toJson()['wear_cost_per_hour'], 1.5);
    });

    test('a server that does not know the rate is not sent one', () {
      expect(
        update(
          rate: 1.5,
          send: false,
        ).toJson().containsKey('wear_cost_per_hour'),
        isFalse,
      );
    });
  });

  group('edit form', () {
    late DioAdapter server;
    late RequestLog log;

    Future<void> pump(
      WidgetTester tester,
      Printer printer, {
      List<Override> extra = const [],
    }) async {
      usePhoneWindow(tester, dp: 2400);
      final dio = testDio();
      server = mockServer(dio);
      log = captureRequests(dio);
      await pumpPhone(
        tester,
        AddPrinterScreen(printer: printer),
        overrides: [
          ...extra,
          if (!extra.any((o) => o == _keyProfile)) noServerProfileOverride,
          printersRepositoryProvider.overrideWithValue(PrintersRepository(dio)),
          fixedDashboardOverride(),
          serverSettingsOverride(const {'currency': 'PLN'}),
        ],
      );
      await tester.pumpAndSettle();
    }

    Finder wearField() =>
        find.widgetWithText(TextFormField, _l10n.editPrinterWearCost('zł'));

    Map<String, dynamic>? patched() => log.requests
        .where((r) => r.method == 'PATCH')
        .map((r) => r.data as Map<String, dynamic>)
        .firstOrNull;

    testWidgets('opens filled in, and saves the rate the user typed', (
      tester,
    ) async {
      await pump(tester, _printer());
      expect(find.text(_l10n.editPrinterTitle), findsOneWidget);
      expect(find.text('0.25'), findsOneWidget);

      server
        ..onPost(
          Endpoints.printersDiagnostic,
          (s) => s.reply(200, _passing),
          data: _diagnoseBody,
        )
        ..onPatch(
          Endpoints.printer(1),
          (s) => s.reply(200, {'id': 1, 'name': 'X1 Carbon'}),
          data: {
            'name': 'X1 Carbon',
            'ip_address': '192.168.4.21',
            'auto_archive': true,
            'is_active': true,
            'model': 'X1C',
            'location': 'Workshop',
            'wear_cost_per_hour': 1.5,
          },
        );
      await tester.enterText(wearField(), '1,5');
      await tester.tap(find.text(_l10n.editPrinterSubmit));
      await tester.pumpAndSettle();

      expect(patched()?['wear_cost_per_hour'], 1.5);
      expect(log.statuses, [200, 200]);
    });

    testWidgets('an older server gets no rate field and no rate sent', (
      tester,
    ) async {
      await pump(tester, _printer(servesWearCost: false));
      expect(wearField(), findsNothing);

      server
        ..onPost(
          Endpoints.printersDiagnostic,
          (s) => s.reply(200, _passing),
          data: _diagnoseBody,
        )
        ..onPatch(
          Endpoints.printer(1),
          (s) => s.reply(200, {'id': 1, 'name': 'X1 Carbon'}),
          data: {
            'name': 'X1 Carbon',
            'ip_address': '192.168.4.21',
            'auto_archive': true,
            'is_active': true,
            'model': 'X1C',
            'location': 'Workshop',
          },
        );
      await tester.tap(find.text(_l10n.editPrinterSubmit));
      await tester.pumpAndSettle();

      // Both answered 200: the exact-body mock matched what went out.
      expect(log.statuses, [200, 200]);
      expect(patched()!.containsKey('wear_cost_per_hour'), isFalse);
    });

    testWidgets('a failed connection check asks before saving', (tester) async {
      await pump(tester, _printer());
      server
        ..onPost(
          Endpoints.printersDiagnostic,
          (s) => s.reply(200, _failing),
          data: _diagnoseBody,
        )
        ..onPatch(
          Endpoints.printer(1),
          (s) => s.reply(200, {'id': 1, 'name': 'X1 Carbon'}),
          data: {
            'name': 'X1 Carbon',
            'ip_address': '192.168.4.21',
            'auto_archive': true,
            'is_active': true,
            'model': 'X1C',
            'location': 'Workshop',
            'wear_cost_per_hour': 0.25,
          },
        );
      await tester.tap(find.text(_l10n.editPrinterSubmit));
      await tester.pumpAndSettle();

      expect(find.text(_l10n.editPrinterPreflightWarning), findsOneWidget);
      expect(patched(), isNull);

      await tester.tap(find.text(_l10n.editPrinterSaveAnyway));
      await tester.pumpAndSettle();
      expect(log.statuses, [200, 200]);
    });

    testWidgets('a refused save keeps the warning to retry from', (
      tester,
    ) async {
      await pump(tester, _printer());
      server
        ..onPost(
          Endpoints.printersDiagnostic,
          (s) => s.reply(200, _failing),
          data: _diagnoseBody,
        )
        ..onPatch(
          Endpoints.printer(1),
          (s) => s.reply(403, {'detail': 'Only an admin can do that.'}),
          data: {
            'name': 'X1 Carbon',
            'ip_address': '192.168.4.21',
            'auto_archive': true,
            'is_active': true,
            'model': 'X1C',
            'location': 'Workshop',
            'wear_cost_per_hour': 0.25,
          },
        );
      await tester.tap(find.text(_l10n.editPrinterSubmit));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_l10n.editPrinterSaveAnyway));
      await tester.pumpAndSettle();

      expect(log.statuses, [200, 403]);
      expect(find.text(_l10n.editPrinterSaveAnyway), findsOneWidget);
    });

    testWidgets('save anyway still checks the fields edited meanwhile', (
      tester,
    ) async {
      await pump(tester, _printer());
      server.onPost(
        Endpoints.printersDiagnostic,
        (s) => s.reply(200, _failing),
        data: _diagnoseBody,
      );
      await tester.tap(find.text(_l10n.editPrinterSubmit));
      await tester.pumpAndSettle();
      await tester.enterText(wearField(), 'abc');
      await tester.tap(find.text(_l10n.editPrinterSaveAnyway));
      await tester.pumpAndSettle();

      expect(find.text(_l10n.editPrinterWearCostInvalid), findsOneWidget);
      expect(patched(), isNull);
    });

    group('location', () {
      List<Override> managed({bool apiKey = false}) => [
        if (apiKey) _keyProfile,
        printerLocationsSupportedProvider.overrideWithValue(
          const AsyncData(true),
        ),
        printerLocationsProvider.overrideWith(
          (ref) async => const [
            PrinterLocation(name: 'Workshop', printerCount: 1),
            PrinterLocation(name: 'Garage'),
          ],
        ),
      ];

      testWidgets('offers the managed ones, an empty one included', (
        tester,
      ) async {
        await pump(tester, _printer(), extra: managed());
        await tester.tap(byLogId('add_printer.location'));
        await tester.pumpAndSettle();

        expect(find.text('Garage'), findsWidgets);
        expect(byLogId('add_printer.manage_locations'), findsOneWidget);
      });

      testWidgets('a name typed in that is on no list is saved as typed', (
        tester,
      ) async {
        await pump(tester, _printer(), extra: managed());
        server
          ..onPost(
            Endpoints.printersDiagnostic,
            (s) => s.reply(200, _passing),
            data: _diagnoseBody,
          )
          ..onPatch(
            Endpoints.printer(1),
            (s) => s.reply(200, {'id': 1, 'name': 'X1 Carbon'}),
            data: {
              'name': 'X1 Carbon',
              'ip_address': '192.168.4.21',
              'auto_archive': true,
              'is_active': true,
              'model': 'X1C',
              'location': 'Attic',
              'wear_cost_per_hour': 0.25,
            },
          );
        await tester.enterText(
          find.descendant(
            of: byLogId('add_printer.location'),
            matching: find.byType(TextField),
          ),
          'Attic',
        );
        await tester.tap(find.text(_l10n.editPrinterSubmit));
        await tester.pumpAndSettle();

        expect(log.statuses, [200, 200]);
      });

      testWidgets('an API key gets the names but not the way to manage them', (
        tester,
      ) async {
        await pump(tester, _printer(), extra: managed(apiKey: true));
        expect(byLogId('add_printer.manage_locations'), findsNothing);
      });
    });

    testWidgets('a rate the server would refuse is stopped in the form', (
      tester,
    ) async {
      await pump(tester, _printer());
      await tester.enterText(wearField(), '-3');
      await tester.tap(find.text(_l10n.editPrinterSubmit));
      await tester.pumpAndSettle();

      expect(find.text(_l10n.editPrinterWearCostInvalid), findsOneWidget);
      expect(log.requests, isEmpty);
    });
  });
}
