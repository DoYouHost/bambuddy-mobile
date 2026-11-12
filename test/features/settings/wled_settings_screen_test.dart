import 'package:bambuddy_mobile/core/api/endpoints.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/settings/wled_settings_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:material_ui/material_ui.dart';

import '../../contract/sent_writes.dart';
import '../../helpers.dart';

/// Settings → WLED (server #1528): the preset each printer state switches
/// WLED to, kept on the printer row and edited per printer.
void main() {
  group('parseFinishedTimeout', () {
    test('empty is 0, which turns the fallback off', () {
      expect(parseFinishedTimeout(''), 0);
      expect(parseFinishedTimeout('   '), 0);
    });

    test('a whole number in range, spaces around it allowed', () {
      expect(parseFinishedTimeout('0'), 0);
      expect(parseFinishedTimeout(' 300 '), 300);
      expect(parseFinishedTimeout('86400'), 86400);
    });

    test('out of range, fractions and words are refused', () {
      expect(parseFinishedTimeout('86401'), isNull);
      expect(parseFinishedTimeout('-1'), isNull);
      expect(parseFinishedTimeout('1.5'), isNull);
      expect(parseFinishedTimeout('ten'), isNull);
    });
  });

  late DioAdapter server;
  late RequestLog log;

  const url = 'http://192.168.1.50';
  final workshop = {
    'id': 1,
    'name': 'Workshop X1C',
    'wled_config': {
      'enabled': true,
      'base_url': url,
      'presets': {'idle': 1, 'printing': 5},
      'finished_timeout_seconds': 120,
    },
  };
  const garage = {'id': 2, 'name': 'Garage A1', 'wled_config': null};
  const presets = [
    {'id': 1, 'name': 'Blue'},
    {'id': 2, 'name': 'Rainbow'},
  ];

  Future<void> pump(
    WidgetTester tester, {
    void Function(DioAdapter server)? routes,
    double textScale = 1,
  }) async {
    usePhoneWindow(tester, dp: 3000);
    final dio = testDio();
    server = mockServer(dio);
    log = captureRequests(dio);
    server.onGet(Endpoints.printers, (s) => s.reply(200, [workshop, garage]));
    routes?.call(server);
    await pumpPhone(
      tester,
      const WledSettingsScreen(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      overrides: [
        noServerProfileOverride,
        printersRepositoryProvider.overrideWithValue(PrintersRepository(dio)),
      ],
    );
    await tester.pumpAndSettle();
  }

  void replyPresets(DioAdapter s, {Duration? delay}) => s.onPost(
    Endpoints.printerWledPresets(1),
    (r) => r.reply(200, presets, delay: delay),
    data: {'base_url': url},
  );

  Finder presetCombo(int index) => byLogId('wled.preset').at(index);

  Future<void> pick(WidgetTester tester, Finder combo, String entry) async {
    await tester.tap(combo);
    await tester.pumpAndSettle();
    await tester.tap(find.text(entry).last);
    await tester.pumpAndSettle();
  }

  testWidgets('a saved, enabled mapping opens with WLED\'s preset names, and '
      'a saved id WLED no longer has is still shown', (tester) async {
    await pump(tester, routes: replyPresets);

    expect(find.text('Workshop X1C'), findsOneWidget);
    expect(find.text(url), findsOneWidget);
    expect(find.text(pl.wledPresetsLoaded(2)), findsOneWidget);
    expect(find.text(pl.wledPresetOption('Blue', 1)), findsOneWidget);
    expect(find.text(pl.wledPresetSaved(5)), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
  });

  testWidgets('Save sends the whole mapping with the edit in it', (
    tester,
  ) async {
    await pump(
      tester,
      routes: (s) {
        replyPresets(s);
        s.onPatch(
          Endpoints.printer(1),
          (r) => r.reply(200, {...workshop, 'wled_config': null}),
          data: {
            'wled_config': {
              'enabled': true,
              'base_url': url,
              'presets': {
                'idle': 1,
                'prepare': null,
                'printing': 5,
                'paused': 2,
                'finished': null,
                'error': null,
                'queue_waiting': null,
                'filament_problem': null,
                'hms_error': null,
                'offline': null,
              },
              'finished_timeout_seconds': 120,
            },
          },
        );
      },
    );

    await pick(tester, presetCombo(3), pl.wledPresetOption('Rainbow', 2));
    await tester.tap(byLogId('wled.save'));
    await tester.pumpAndSettle();

    expect(find.text(pl.wledSaved), findsOneWidget);
    expectSentAsRecorded(
      'wled_save',
      writesOf(log.requests.where((r) => r.method == 'PATCH')),
    );
  });

  testWidgets('a WLED that does not answer keeps the saved ids and says so', (
    tester,
  ) async {
    await pump(
      tester,
      routes: (s) => s.onPost(
        Endpoints.printerWledPresets(1),
        (r) => r.reply(502, {'detail': 'Could not load WLED presets'}),
        data: {'base_url': url},
      ),
    );

    expect(find.text(pl.wledPresetsOffline), findsOneWidget);
    expect(find.text(pl.wledPresetSaved(1)), findsOneWidget);
    expect(find.text(pl.wledPresetSaved(5)), findsOneWidget);
  });

  testWidgets('a URL the server refuses is said under the field', (
    tester,
  ) async {
    const reason = 'WLED URL must not include credentials';
    await pump(
      tester,
      routes: (s) {
        replyPresets(s);
        s.onPatch(
          Endpoints.printer(1),
          (r) => r.reply(422, {
            'detail': [
              {'msg': 'Value error, $reason'},
            ],
          }),
          data: {
            'wled_config': {
              'enabled': true,
              'base_url': url,
              'presets': {
                for (final key in const [
                  'idle',
                  'prepare',
                  'printing',
                  'paused',
                  'finished',
                  'error',
                  'queue_waiting',
                  'filament_problem',
                  'hms_error',
                  'offline',
                ])
                  key: const {'idle': 1, 'printing': 5}[key],
              },
              'finished_timeout_seconds': 120,
            },
          },
        );
      },
    );

    await tester.tap(byLogId('wled.save'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.descendant(
        of: byLogId('wled.url'),
        matching: find.byType(TextField),
      ),
    );
    expect(field.decoration?.errorText, pl.wledRefused(reason));
  });

  testWidgets('an enabled mapping cannot be saved without an address', (
    tester,
  ) async {
    await pump(tester, routes: replyPresets);
    await pick(tester, byLogId('wled.printer'), 'Garage A1');

    FilledButton save() => tester.widget<FilledButton>(
      find.descendant(
        of: byLogId('wled.save'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(save().onPressed, isNotNull, reason: 'off needs no address');

    await tester.tap(byLogId('wled.enabled'));
    await tester.pumpAndSettle();
    expect(save().onPressed, isNull);
    expect(find.text(pl.wledUrlRequired), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: byLogId('wled.url'),
        matching: find.byType(TextField),
      ),
      'http://10.0.0.9',
    );
    await tester.pump();
    expect(save().onPressed, isNotNull);
  });

  testWidgets('a delay that is not a whole number in range blocks Save', (
    tester,
  ) async {
    await pump(tester, routes: replyPresets);

    await tester.enterText(
      find.descendant(
        of: byLogId('wled.finished_timeout'),
        matching: find.byType(TextField),
      ),
      '90000',
    );
    await tester.pump();

    expect(find.text(pl.wledFinishedTimeoutInvalid), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(
              of: byLogId('wled.save'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('presets that arrive after switching printers are not shown '
      'for the new one', (tester) async {
    await pump(
      tester,
      routes: (s) => replyPresets(s, delay: const Duration(seconds: 5)),
    );
    // The first printer's request is still out.
    await pick(tester, byLogId('wled.printer'), 'Garage A1');
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(find.text(pl.wledPresetsLoaded(2)), findsNothing);
    expect(find.text(pl.wledPresetOption('Blue', 1)), findsNothing);
  });

  testWidgets('a preset test sends the address and the mapped preset', (
    tester,
  ) async {
    await pump(
      tester,
      routes: (s) {
        replyPresets(s);
        s.onPost(
          Endpoints.printerWledTestPreset(1),
          (r) => r.reply(200, {'success': true}),
          data: {'base_url': url, 'preset_id': 1},
        );
      },
    );

    await tester.tap(byLogId('wled.test_preset').first);
    await tester.pumpAndSettle();

    expect(find.text(pl.wledPresetTested), findsOneWidget);
    expect(log.requests.where((r) => r.method == 'POST').map((r) => r.path), [
      Endpoints.printerWledPresets(1),
      Endpoints.printerWledTestPreset(1),
    ]);
  });

  for (final scale in const [1.0, 1.5, 2.0]) {
    testWidgets('lays out at ${scale}x text with every line showing', (
      tester,
    ) async {
      await pump(
        tester,
        textScale: scale,
        routes: (s) {
          replyPresets(s);
          s.onPost(
            Endpoints.printerWledTestConnection(1),
            (r) => r.reply(200, {'name': 'Shelf strip', 'version': '0.15.1'}),
            data: {'base_url': url},
          );
        },
      );
      await tester.tap(byLogId('wled.test_connection'));
      await tester.pumpAndSettle();

      expect(
        find.text(pl.wledConnectedVersion('Shelf strip', '0.15.1')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
