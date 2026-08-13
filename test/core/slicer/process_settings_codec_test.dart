import 'package:bambuddy_mobile/core/models/process_option.dart';
import 'package:bambuddy_mobile/core/slicer/process_schema_catalog.dart';
import 'package:bambuddy_mobile/core/slicer/process_settings_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// The codec is the one place a mistake is invisible: the server does not refuse
/// a badly serialised value, it drops the key with a log line and slices without
/// it. Every case below is a wire form the slicer CLI either accepts or fails
/// the whole slice on.
void main() {
  ProcessOption option(
    OptionType type, {
    Object? min,
    Object? max,
    String? sidetext,
    Object? defaultValue,
    List<String>? enumValues,
  }) =>
      ProcessOption(
        key: 'k',
        type: type,
        mode: OptionMode.advanced,
        label: 'K',
        min: min,
        max: max,
        sidetext: sidetext,
        defaultValue: defaultValue,
        enumValues: enumValues,
      );

  group('serializeSetting', () {
    test('coBool is 1/0, never true/false', () {
      final bool_ = option(OptionType.coBool);
      expect(serializeSetting(bool_, true), '1');
      expect(serializeSetting(bool_, false), '0');
      // Whatever form a control hands back has to land on the same two values.
      expect(serializeSetting(bool_, '1'), '1');
      expect(serializeSetting(bool_, 'true'), '1');
      expect(serializeSetting(bool_, 1), '1');
      expect(serializeSetting(bool_, '0'), '0');
      expect(serializeSetting(bool_, 'anything else'), '0');
    });

    test('coPercent keeps the sign the config expects', () {
      final percent = option(OptionType.coPercent);
      expect(serializeSetting(percent, '20'), '20%');
      expect(serializeSetting(percent, 20), '20%');
      expect(serializeSetting(percent, '20%'), '20%');
      expect(serializeSetting(percent, ' 20 '), '20%');
    });

    test('numbers and strings are trimmed and passed through', () {
      expect(serializeSetting(option(OptionType.coFloat), ' 0.42 '), '0.42');
      expect(serializeSetting(option(OptionType.coInt), 3), '3');
      expect(serializeSetting(option(OptionType.coString), ' text '), 'text');
      // coFloatOrPercent holds either shape, so it must not gain a % sign.
      expect(serializeSetting(option(OptionType.coFloatOrPercent), '50%'), '50%');
      expect(serializeSetting(option(OptionType.coFloatOrPercent), '0.5'), '0.5');
    });

    test('vectors become lists, trimmed, with empties dropped', () {
      final vector = option(OptionType.coFloats);
      expect(serializeSetting(vector, '500, 300 ,'), ['500', '300']);
      expect(serializeSetting(vector, [500, 300]), ['500', '300']);
      expect(serializeSetting(vector, ''), <String>[]);
      expect(serializeSetting(vector, ' , '), <String>[]);
    });

    test('a bool inside a vector is 1/0 too', () {
      // The deviation from upstream, which sends "true" here while sending "1"
      // for the identical scalar. The server documents 1/0 as the only spelling
      // a process JSON uses.
      final vector = option(OptionType.coBools);
      expect(serializeSetting(vector, [true]), ['1']);
      expect(serializeSetting(vector, [false, true]), ['0', '1']);
    });

    test('a whole double loses the trailing .0 Dart would keep', () {
      expect(serializeSetting(option(OptionType.coFloat), 2.0), '2');
      expect(serializeSetting(option(OptionType.coFloat), 0.42), '0.42');
      expect(serializeSetting(option(OptionType.coFloats), [2.0]), ['2']);
    });
  });

  group('numericBound', () {
    test('numbers pass through', () {
      expect(numericBound(0), 0);
      expect(numericBound(100), 100);
      expect(numericBound(0.42), 0.42);
      expect(numericBound(-5), -5);
    });

    test('numeric strings are parsed — the generator emits both shapes', () {
      expect(numericBound('0'), 0);
      expect(numericBound('0.3'), 0.3);
      expect(numericBound('0.005'), 0.005);
      expect(numericBound(' 2 '), 2);
    });

    test('C++ literal artefacts still parse', () {
      expect(numericBound('0.3f'), 0.3);
      expect(numericBound('0.'), 0);
      expect(numericBound('.5'), 0.5);
      expect(numericBound('100.%'), 100);
      expect(numericBound('1e3'), 1000);
    });

    test('an unresolved expression is no bound at all', () {
      // standby_temperature_delta really is bounded by these in the schema; a
      // NaN reaching a field's min/max makes it unfillable.
      expect(numericBound('max_temp'), isNull);
      expect(numericBound('-max_temp'), isNull);
      expect(numericBound('def_x->max'), isNull);
      expect(numericBound(null), isNull);
      expect(numericBound(true), isNull);
      expect(numericBound(double.nan), isNull);
      expect(numericBound(double.infinity), isNull);
    });
  });

  group('displaySidetext', () {
    test('a real unit is shown', () {
      expect(displaySidetext(option(OptionType.coFloat, sidetext: 'mm')), 'mm');
      expect(displaySidetext(option(OptionType.coFloat, sidetext: 'mm/s²')),
          'mm/s²');
    });

    test('an unresolved reference shows nothing', () {
      expect(
          displaySidetext(option(OptionType.coFloat, sidetext: 'def_x->sidetext')),
          isNull);
      expect(displaySidetext(option(OptionType.coFloat, sidetext: 'Foo::bar')),
          isNull);
      expect(displaySidetext(option(OptionType.coFloat, sidetext: '')), isNull);
      expect(displaySidetext(option(OptionType.coFloat)), isNull);
    });
  });

  group('baselineForDisplay', () {
    test("the preset's own value wins over the schema default", () {
      // The case that motivates the whole preset-values endpoint: line_width is
      // 0 in the C++ and 0.42 in any real preset.
      final lineWidth = option(OptionType.coFloat, defaultValue: 0);
      expect(baselineForDisplay(lineWidth), '0');
      expect(baselineForDisplay(lineWidth, '0.42'), '0.42');
    });

    test('bools show as 1/0 and vectors as a comma list', () {
      expect(baselineForDisplay(option(OptionType.coBool, defaultValue: true)),
          '1');
      expect(
          baselineForDisplay(option(OptionType.coBools, defaultValue: [true])),
          '1');
      expect(
          baselineForDisplay(
              option(OptionType.coFloats, defaultValue: [500, 300])),
          '500, 300');
    });

    test('nothing known shows an empty field', () {
      expect(baselineForDisplay(option(OptionType.coFloat)), '');
    });
  });

  group('isModified', () {
    final layerHeight = option(OptionType.coFloat, defaultValue: 0.2);

    test('equal to the baseline is not a change', () {
      expect(isModified(layerHeight, '0.2'), isFalse);
      expect(isModified(layerHeight, 0.2), isFalse);
      expect(isModified(layerHeight, ' 0.2 '), isFalse);
      expect(isModified(layerHeight, '0.28'), isTrue);
    });

    test('compared against the preset, not the default', () {
      // Typing the C++ default into a preset that sets something else IS a
      // change; matching the preset is not.
      expect(isModified(layerHeight, '0.2', '0.28'), isTrue);
      expect(isModified(layerHeight, '0.28', '0.28'), isFalse);
    });

    test('empty and null are never a change', () {
      // An empty field is a value being retyped, not a request to send nothing.
      expect(isModified(layerHeight, ''), isFalse);
      expect(isModified(layerHeight, null), isFalse);
    });

    test('every empty shape a vector can take is not a change', () {
      // The shapes differ but they all mean "nothing entered". Judging the raw
      // input let `[]` through as a change, which sent an empty array — a value
      // nobody typed, written straight into the process JSON.
      final vector = option(OptionType.coFloats, defaultValue: [500]);
      expect(isModified(vector, <Object>[]), isFalse);
      expect(isModified(vector, <Object>['', '']), isFalse);
      expect(isModified(vector, ''), isFalse);
      expect(isModified(vector, ' , '), isFalse);
      expect(isModified(vector, <Object>[600]), isTrue);
    });

    test('percent forms compare through the serialiser', () {
      final percent = option(OptionType.coPercent, defaultValue: 50);
      expect(isModified(percent, '50'), isFalse);
      expect(isModified(percent, '50%'), isFalse);
      expect(isModified(percent, '60'), isTrue);
    });

    test('a bool matches its baseline in either spelling', () {
      final flag = option(OptionType.coBool, defaultValue: true);
      expect(isModified(flag, true), isFalse);
      expect(isModified(flag, '1'), isFalse);
      expect(isModified(flag, false), isTrue);
      expect(isModified(flag, '0'), isTrue);
    });

    test('vectors compare flattened, whitespace and shape aside', () {
      final vector = option(OptionType.coFloats, defaultValue: [500, 300]);
      expect(isModified(vector, '500, 300'), isFalse);
      expect(isModified(vector, [500, 300]), isFalse);
      expect(isModified(vector, '500,300'), isFalse);
      expect(isModified(vector, '500, 400'), isTrue);
    });

    test('with no baseline at all, anything non-empty is a change', () {
      expect(isModified(option(OptionType.coString), 'x'), isTrue);
    });
  });

  group('against all 348 real options', () {
    late ProcessSchemaCatalog catalog;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      catalog = ProcessSchemaCatalog();
      await catalog.load();
      expect(catalog.isLoaded, isTrue,
          reason: 'assets/slicer/*.json did not load — the rest is vacuous');
    });

    test('a field seeded from its own default is never modified', () {
      // The property that keeps an untouched screen silent. It has to hold for
      // every type, including the 37 vector options and the 4 whose default is a
      // bare string, or opening the screen would send values nobody typed.
      final wrong = <String>[];
      for (final option in catalog.schema.values) {
        final seeded = baselineForDisplay(option);
        if (isModified(option, seeded)) wrong.add(option.key);
      }
      expect(wrong, isEmpty);
    });

    test('every default serialises to a form the server keeps', () {
      for (final option in catalog.schema.values) {
        final wire = serializeSetting(option, baselineForDisplay(option));
        expect(wire, anyOf(isA<String>(), isA<List<String>>()),
            reason: '${option.key} (${option.type.name})');
      }
    });

    test('no bound survives as NaN', () {
      for (final option in catalog.schema.values) {
        for (final bound in [numericBound(option.min), numericBound(option.max)]) {
          if (bound != null) {
            expect(bound.isFinite, isTrue, reason: option.key);
          }
        }
      }
    });

    test('the one option with unresolved bounds yields no bounds', () {
      // Concrete, because the generic check above passes trivially if every
      // bound happens to parse.
      final delta = catalog.schema['standby_temperature_delta']!;
      expect(delta.min, isA<String>());
      expect(numericBound(delta.min), isNull);
      expect(numericBound(delta.max), isNull);
    });
  });

  group('buildProcessOverrides', () {
    final schema = <String, ProcessOption>{
      'layer_height': option(OptionType.coFloat, defaultValue: 0.2),
      'wall_loops': option(OptionType.coInt, defaultValue: 2),
      'enable_support': option(OptionType.coBool, defaultValue: false),
      'sparse_infill_density': option(OptionType.coPercent, defaultValue: 15),
      'default_acceleration': option(OptionType.coFloats, defaultValue: [500]),
    };

    test('an untouched screen sends nothing', () {
      expect(buildProcessOverrides(values: const {}, schema: schema), isEmpty);
    });

    test('only genuine deviations are sent', () {
      final body = buildProcessOverrides(
        values: {
          'layer_height': '0.28',
          'wall_loops': '2', // equal to the default — noise, not an override
          'enable_support': true,
        },
        schema: schema,
      );
      expect(body, {'layer_height': '0.28', 'enable_support': '1'});
    });

    test('each value is serialised through its own type', () {
      final body = buildProcessOverrides(
        values: {
          'sparse_infill_density': '25',
          'default_acceleration': '600, 400',
        },
        schema: schema,
      );
      expect(body, {
        'sparse_infill_density': '25%',
        'default_acceleration': ['600', '400'],
      });
    });

    test('the preset values decide what counts as a deviation', () {
      // Same edit, two servers: one whose preset already says 0.28.
      const edit = {'layer_height': '0.28'};
      expect(buildProcessOverrides(values: edit, schema: schema),
          {'layer_height': '0.28'});
      expect(
          buildProcessOverrides(
              values: edit,
              schema: schema,
              presetValues: {'layer_height': '0.28'}),
          isEmpty);
    });

    test('an emptied vector sends nothing rather than an empty array', () {
      for (final emptied in <Object>[<Object>[], <Object>['', ''], '', ' , ']) {
        expect(
            buildProcessOverrides(
                values: {'default_acceleration': emptied}, schema: schema),
            isEmpty,
            reason: '$emptied');
      }
    });

    test('a key with no schema entry is dropped, never sent raw', () {
      // The server ignores an unknown key with only a log line, so a typo would
      // fail the slice with nothing pointing back at this screen.
      final body = buildProcessOverrides(
        values: {'layer_height': '0.28', 'not_a_real_option': 'x'},
        schema: schema,
      );
      expect(body.keys, ['layer_height']);
    });

    test('every key it emits satisfies the server-side key regex', () {
      // `^[a-z][a-z0-9_]*$` in services/process_overrides.py — a key that fails
      // it is dropped server-side.
      final body = buildProcessOverrides(
        values: {
          'layer_height': '0.28',
          'enable_support': true,
          'default_acceleration': '600',
        },
        schema: schema,
      );
      expect(body, isNotEmpty);
      for (final key in body.keys) {
        expect(RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(key), isTrue, reason: key);
      }
    });

    test('every value it emits is a string or a list of strings', () {
      // The server accepts scalars and lists of scalars and drops anything else;
      // nothing here may emit a num or a bool.
      final body = buildProcessOverrides(
        values: {
          'layer_height': 0.28,
          'wall_loops': 4,
          'enable_support': true,
          'sparse_infill_density': 25,
          'default_acceleration': [600, 400],
        },
        schema: schema,
      );
      expect(body, hasLength(5));
      for (final value in body.values) {
        expect(value, anyOf(isA<String>(), isA<List<String>>()), reason: '$value');
      }
    });
  });
}
