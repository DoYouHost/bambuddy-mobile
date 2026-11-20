import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/wled_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WledConfig.fromJson', () {
    test('reads the shape the server stores', () {
      final config = WledConfig.fromJson({
        'enabled': true,
        'base_url': 'http://wled.local',
        'presets': {'idle': 1, 'printing': 2, 'hms_error': 250, 'paused': null},
        'finished_timeout_seconds': 300,
      });

      expect(config.enabled, isTrue);
      expect(config.baseUrl, 'http://wled.local');
      expect(config.presets, {
        WledState.idle: 1,
        WledState.printing: 2,
        WledState.hmsError: 250,
      });
      expect(config.finishedTimeoutSeconds, 300);
    });

    test('an empty object is a disabled mapping with nothing set', () {
      final config = WledConfig.fromJson(const {});

      expect(config.enabled, isFalse);
      expect(config.baseUrl, isNull);
      expect(config.presets, isEmpty);
      expect(config.finishedTimeoutSeconds, isNull);
    });

    test('drops preset ids outside 1..250 and of the wrong type', () {
      final config = WledConfig.fromJson({
        'presets': {
          'idle': 0,
          'prepare': 251,
          'printing': 'two',
          'paused': 1,
          'finished': 250,
          'nonsense_state': 5,
        },
      });

      expect(config.presets, {WledState.paused: 1, WledState.finished: 250});
    });

    test('presets that are not an object are none', () {
      expect(WledConfig.fromJson({'presets': 'idle'}).presets, isEmpty);
    });
  });

  test('toJson sends every state, the unmapped ones as null', () {
    const config = WledConfig(
      enabled: true,
      baseUrl: 'http://10.0.0.5',
      presets: {WledState.queueWaiting: 7},
      finishedTimeoutSeconds: 0,
    );

    expect(config.toJson(), {
      'enabled': true,
      'base_url': 'http://10.0.0.5',
      'presets': {
        'idle': null,
        'prepare': null,
        'printing': null,
        'paused': null,
        'finished': null,
        'error': null,
        'queue_waiting': 7,
        'filament_problem': null,
        'hms_error': null,
        'offline': null,
      },
      'finished_timeout_seconds': 0,
    });
  });

  group('Printer.wledConfig', () {
    Map<String, dynamic> row(Object? wled) => {
      'id': 1,
      'name': 'X1C',
      'wled_config': wled,
    };

    test('parses an object', () {
      final printer = Printer.fromJson(row({'enabled': true}));
      expect(printer.wledConfig?.enabled, isTrue);
    });

    test('is null for null, a missing key and a value of the wrong type', () {
      expect(Printer.fromJson(row(null)).wledConfig, isNull);
      expect(
        Printer.fromJson(const {'id': 1, 'name': 'X1C'}).wledConfig,
        isNull,
      );
      expect(Printer.fromJson(row('on')).wledConfig, isNull);
    });
  });
}
