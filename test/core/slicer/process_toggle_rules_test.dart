import 'package:bambuddy_mobile/core/models/process_option.dart';
import 'package:bambuddy_mobile/core/slicer/process_schema_catalog.dart';
import 'package:bambuddy_mobile/core/slicer/process_toggle_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// The interpreter for OrcaSlicer's enable/disable rules.
///
/// Almost every case here is really a test of **fail open**: only a rule that
/// evaluates to a definite `false` may grey a field out. A wrongly-greyed control
/// hides a setting and reads as a bug, so "I could not decide" and "enabled" have
/// to be the same outcome.
void main() {
  ProcessOption option(
    String key,
    OptionType type, {
    Object? defaultValue,
    List<String>? enumValues,
  }) => ProcessOption(
    key: key,
    type: type,
    mode: OptionMode.advanced,
    label: key,
    defaultValue: defaultValue,
    enumValues: enumValues,
  );

  /// Runs one condition over [schema] and reports whether it disabled the field.
  bool disables(
    String enableIf, {
    Map<String, ProcessOption> schema = const {},
    Map<String, String> locals = const {},
    Map<String, Object> values = const {},
  }) => disabledOptionKeys(
    values: values,
    schema: schema,
    toggles: ToggleRules(
      locals: locals,
      rules: [
        ToggleRule(fields: const ['target'], enableIf: enableIf),
      ],
    ),
  ).contains('target');

  group('only a definite false disables', () {
    test('true enables, false disables', () {
      expect(disables('true'), isFalse);
      expect(disables('false'), isTrue);
    });

    test('an unparseable expression enables', () {
      expect(disables('this is not an expression'), isFalse);
      expect(disables('&&'), isFalse);
      expect(disables(''), isFalse);
      expect(disables('config->'), isFalse);
      // An unterminated string literal, and a character the tokenizer refuses.
      expect(disables('config->opt_bool("x'), isFalse);
      expect(disables('1 @ 2'), isFalse);
    });

    test('a trailing token is not a usable parse', () {
      // `false` followed by junk must not be read as plain `false`, or a grammar
      // we misread would start greying fields out.
      expect(disables('false false'), isFalse);
      expect(disables('false)'), isFalse);
    });

    test('an unknown accessor enables', () {
      // get_abs_value is in the real rule set and deliberately unsupported: it
      // resolves a float-or-percent against a reference, so reading it as the
      // raw value would give a confidently wrong number.
      expect(
        disables(
          'config->get_abs_value("x") > 0',
          schema: {'x': option('x', OptionType.coFloat, defaultValue: 0)},
        ),
        isFalse,
      );
    });

    test('a missing key gives no answer rather than a false one', () {
      expect(disables('config->opt_bool("absent")'), isFalse);
    });
  });

  group('boolean operators short-circuit through unknowns', () {
    final schema = {
      'flag': option('flag', OptionType.coBool, defaultValue: false),
    };

    // A read of a key no schema declares: parses cleanly, resolves to nothing.
    // It has to be this rather than a bad accessor — see the last test here.
    const unknown = 'config->opt_bool("absent")';

    test('true survives an unknown operand in ||', () {
      expect(disables('true || $unknown'), isFalse);
      expect(disables('$unknown || true'), isFalse);
    });

    test('false survives an unknown operand in &&', () {
      expect(disables('false && $unknown'), isTrue);
      expect(disables('$unknown && false'), isTrue);
    });

    test('unknown with a non-decisive operand stays unknown', () {
      // false || unknown is *not* false: the unknown side could be true.
      expect(disables('false || $unknown'), isFalse);
      expect(disables('true && $unknown'), isFalse);
    });

    test(
      'an unsupported accessor poisons the whole expression, not one operand',
      () {
        // It leaves its tokens unconsumed, so the trailing-token guard rejects the
        // parse before any short-circuit applies — `false && …` does not disable
        // here even though `false && unknown` does. Upstream behaves identically,
        // and both outcomes are enabled, so the distinction only ever costs a
        // grey-out we chose not to make.
        expect(disables('false && config->get_abs_value("x")'), isFalse);
        expect(disables('false'), isTrue, reason: 'the same rule without it');
      },
    );

    test('plain combinations', () {
      expect(disables('false || false'), isTrue);
      expect(disables('true && true'), isFalse);
      expect(disables('false && true'), isTrue);
      expect(disables('config->opt_bool("flag")', schema: schema), isTrue);
      expect(disables('!config->opt_bool("flag")', schema: schema), isFalse);
      expect(disables('!!config->opt_bool("flag")', schema: schema), isTrue);
    });

    test('parentheses group', () {
      expect(disables('(false || false) && true'), isTrue);
      expect(disables('false || (true && true)'), isFalse);
      expect(disables('(true'), isFalse, reason: 'unclosed — fail open');
    });
  });

  group('comparisons', () {
    final schema = {
      'count': option('count', OptionType.coInt, defaultValue: 2),
      'density': option('density', OptionType.coPercent, defaultValue: 20),
      'name': option('name', OptionType.coString, defaultValue: ''),
    };

    test('numeric relations', () {
      expect(disables('config->opt_int("count") > 0', schema: schema), isFalse);
      expect(disables('config->opt_int("count") > 5', schema: schema), isTrue);
      expect(disables('config->opt_int("count") < 5', schema: schema), isFalse);
      expect(
        disables('config->opt_int("count") == 2', schema: schema),
        isFalse,
      );
      expect(disables('config->opt_int("count") != 2', schema: schema), isTrue);
      expect(
        disables('config->opt_int("count") >= 2', schema: schema),
        isFalse,
      );
      expect(disables('config->opt_int("count") <= 1', schema: schema), isTrue);
    });

    test('a percent compares by its number', () {
      // The stored form is "20%", and every threshold in the rule set is bare.
      expect(
        disables(
          'config->opt_int("density") > 0',
          schema: schema,
          values: {'density': '20%'},
        ),
        isFalse,
      );
      expect(
        disables(
          'config->opt_int("density") > 0',
          schema: schema,
          values: {'density': '0%'},
        ),
        isTrue,
      );
    });

    test('a string compares as a string', () {
      // The real shape: three rules read `opt_string(...) == ""`, i.e. "enabled
      // while the template is blank", so filling the template in is what greys
      // the dependent fields out.
      expect(
        disables('config->opt_string("name") == ""', schema: schema),
        isFalse,
      );
      expect(
        disables(
          'config->opt_string("name") == ""',
          schema: schema,
          values: {'name': 'x'},
        ),
        isTrue,
      );
    });

    test('a relation against something non-numeric gives no answer', () {
      expect(
        disables('config->opt_string("name") > 0', schema: schema),
        isFalse,
      );
    });
  });

  group('config access forms', () {
    final schema = {
      'x': option('x', OptionType.coFloat, defaultValue: 5),
      'v': option('v', OptionType.coFloats, defaultValue: [7, 9]),
    };

    test('the template argument and the ->value tail are consumed', () {
      expect(
        disables(
          'config->option<ConfigOptionFloat>("x")->value > 1',
          schema: schema,
        ),
        isFalse,
      );
      expect(
        disables(
          'config->option<ConfigOptionFloat>("x")->value > 9',
          schema: schema,
        ),
        isTrue,
      );
    });

    test('extra arguments are skipped', () {
      expect(
        disables(
          'config->opt_float_nullable("x", variant_index) > 1',
          schema: schema,
        ),
        isFalse,
      );
      expect(disables('config->opt_float("x", 0) > 9', schema: schema), isTrue);
    });

    test('has() asks the schema, not the value', () {
      expect(disables('config->has("x")', schema: schema), isFalse);
      expect(disables('config->has("nope")', schema: schema), isTrue);
    });

    test('a vector option is read at its first entry', () {
      // Matching opt_float_nullable(key, variant_index) for the active variant.
      expect(disables('config->opt_float("v") == 7', schema: schema), isFalse);
      expect(disables('config->opt_float("v") == 9', schema: schema), isTrue);
    });

    test('a user value outranks the schema default', () {
      expect(
        disables(
          'config->opt_float("x") > 9',
          schema: schema,
          values: {'x': '10'},
        ),
        isFalse,
      );
      // An empty field is not a value — it falls back to the default.
      expect(
        disables(
          'config->opt_float("x") > 9',
          schema: schema,
          values: {'x': ''},
        ),
        isTrue,
      );
    });

    test(
      'an emptied vector falls back to the default, like an empty field',
      () {
        // Upstream unwraps the list *after* the fallback, so an empty vector
        // override skipped the default and read as undecidable while an empty
        // string fell back. Both are "nothing entered" and behave alike here.
        expect(
          disables(
            'config->opt_float("v") == 7',
            schema: schema,
            values: {'v': <Object>[]},
          ),
          isFalse,
          reason: 'falls back to [7, 9] and its first entry is 7',
        );
        expect(
          disables(
            'config->opt_float("v") == 9',
            schema: schema,
            values: {'v': <Object>[]},
          ),
          isTrue,
        );
        // A non-empty override still wins, read at its first entry.
        expect(
          disables(
            'config->opt_float("v") == 3',
            schema: schema,
            values: {
              'v': <Object>[3, 4],
            },
          ),
          isFalse,
        );
      },
    );
  });

  group('named locals', () {
    final schema = {
      'count': option('count', OptionType.coInt, defaultValue: 0),
    };

    test('resolve, and nest through each other', () {
      const locals = {
        'have_perimeters': 'config->opt_int("count") > 0',
        'has_walls': 'have_perimeters',
        'anything': 'has_walls || have_perimeters',
      };
      expect(disables('anything', schema: schema, locals: locals), isTrue);
      expect(
        disables(
          'anything',
          schema: schema,
          locals: locals,
          values: {'count': '3'},
        ),
        isFalse,
      );
    });

    test('a cyclic definition terminates and decides nothing', () {
      const locals = {'a': 'b', 'b': 'a'};
      expect(disables('a', locals: locals), isFalse);
    });

    test('a self-referential definition terminates', () {
      expect(
        disables('loop', locals: const {'loop': 'loop || false'}),
        isFalse,
      );
    });

    test(
      'an undefined name is not a local, and decides nothing on its own',
      () {
        expect(disables('mystery_flag'), isFalse);
      },
    );

    test('locals are shared across rules in one pass', () {
      // Cheap observable proxy for the memo: two rules over the same local must
      // agree, and both must see the user's value rather than a stale default.
      final disabled = disabledOptionKeys(
        values: {'count': '0'},
        schema: schema,
        toggles: const ToggleRules(
          locals: {'have_perimeters': 'config->opt_int("count") > 0'},
          rules: [
            ToggleRule(fields: ['a'], enableIf: 'have_perimeters'),
            ToggleRule(
              fields: ['b'],
              enableIf: 'have_perimeters, variant_index',
            ),
          ],
        ),
      );
      expect(disabled, {'a', 'b'});
    });
  });

  group('enum comparisons', () {
    final schema = {
      'ironing_type': option(
        'ironing_type',
        OptionType.coEnum,
        defaultValue: 'no ironing',
        enumValues: const ['no ironing', 'top', 'topmost', 'solid'],
      ),
      'brim_type': option(
        'brim_type',
        OptionType.coEnum,
        defaultValue: 'auto_brim',
        enumValues: const ['auto_brim', 'no_brim', 'outer_only'],
      ),
    };

    test('a C++ enumerator is transliterated to the declared spelling', () {
      // NoIroning -> no_ironing | no ironing | noironing; exactly one is declared.
      expect(
        disables(
          'config->opt_enum<IroningType>("ironing_type") != IroningType::NoIroning',
          schema: schema,
        ),
        isTrue,
      );
      expect(
        disables(
          'config->opt_enum<IroningType>("ironing_type") == IroningType::NoIroning',
          schema: schema,
        ),
        isFalse,
      );
    });

    test('the lowercase type tag is stripped as an alternative reading', () {
      // btNoBrim -> no_brim, which brim_type declares.
      expect(
        disables(
          'config->opt_enum<BrimType>("brim_type") == btNoBrim',
          schema: schema,
        ),
        isTrue,
      );
      expect(
        disables(
          'config->opt_enum<BrimType>("brim_type") != btNoBrim',
          schema: schema,
          values: {'brim_type': 'no_brim'},
        ),
        isTrue,
      );
    });

    test('an enumerator matching nothing declared decides nothing', () {
      expect(
        disables(
          'config->opt_enum<IroningType>("ironing_type") == ipGyroid',
          schema: schema,
        ),
        isFalse,
      );
    });

    test('a relation on an enum decides nothing', () {
      expect(
        disables(
          'config->opt_enum<IroningType>("ironing_type") < ipGyroid',
          schema: schema,
        ),
        isFalse,
      );
    });

    test('two enumerators compared to each other decide nothing', () {
      expect(disables('ipGyroid == ipGrid'), isFalse);
    });

    test('an enum read still compares by plain value', () {
      expect(
        disables(
          'config->opt_enum<IroningType>("ironing_type") == "top"',
          schema: schema,
        ),
        isTrue,
      );
      expect(
        disables(
          'config->opt_enum<IroningType>("ironing_type") == "top"',
          schema: schema,
          values: {'ironing_type': 'top'},
        ),
        isFalse,
      );
    });
  });

  group('conditionOf', () {
    test('drops the trailing variant_index argument', () {
      expect(conditionOf('have_perimeters, variant_index'), 'have_perimeters');
      expect(
        conditionOf('have_infill || has_solid_infill, variant_index'),
        'have_infill || has_solid_infill',
      );
    });

    test('only parentheses count towards nesting', () {
      // A comma inside a call is part of the condition; `<`/`>` are comparisons
      // far more often than template brackets.
      expect(
        conditionOf('config->opt_float("x", 0) > 1, variant_index'),
        'config->opt_float("x", 0) > 1',
      );
      expect(
        conditionOf('config->opt_int("a") < 5'),
        'config->opt_int("a") < 5',
      );
    });

    test('nothing usable is null', () {
      expect(conditionOf(''), isNull);
      expect(conditionOf('   '), isNull);
      expect(conditionOf(', variant_index'), isNull);
    });
  });

  group('against the real 152 rules', () {
    late ProcessSchemaCatalog catalog;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      catalog = ProcessSchemaCatalog();
      await catalog.load();
      expect(
        catalog.isLoaded,
        isTrue,
        reason: 'assets/slicer/*.json did not load — the rest is vacuous',
      );
    });

    Set<String> disabledAt(Map<String, Object> values) => disabledOptionKeys(
      values: values,
      schema: catalog.schema,
      toggles: catalog.toggles,
    );

    test('the whole rule set evaluates over schema defaults', () {
      final disabled = disabledAt(const {});
      // Every key it names has to be renderable, or the screen greys out
      // something it never drew.
      for (final key in disabled) {
        expect(catalog.schema.containsKey(key), isTrue, reason: key);
      }
    });

    test('a real dependency really disables: no walls, no wall settings', () {
      // have_perimeters = config->opt_int("wall_loops") > 0, and wall_loops
      // defaults to 2. This is the canary for a parser regression: if the
      // interpreter stops understanding the grammar, everything fails open and
      // this set goes empty.
      expect(disabledAt(const {}), isNot(contains('outer_wall_speed')));
      final noWalls = disabledAt(const {'wall_loops': '0'});
      expect(
        noWalls,
        containsAll(<String>[
          'outer_wall_speed',
          'inner_wall_speed',
          'small_perimeter_speed',
          'detect_thin_wall',
          'seam_position',
        ]),
      );
    });

    test('a real dependency really disables: no infill, no infill settings', () {
      // have_infill reads sparse_infill_density through a ConfigOptionPercent
      // template argument and a ->value tail, so it exercises the whole accessor
      // grammar in one condition.
      expect(disabledAt(const {}), isNot(contains('sparse_infill_pattern')));
      final noInfill = disabledAt(const {'sparse_infill_density': '0%'});
      expect(
        noInfill,
        containsAll(<String>[
          'sparse_infill_pattern',
          'infill_combination',
          'minimum_sparse_infill_area',
        ]),
      );
    });

    test('the enum transliteration works on a real rule', () {
      // `is_locked_zig` is `sparse_infill_pattern == InfillPattern::ipLockedZag`,
      // and the value that option actually declares is `lockedzag` — no
      // underscore. Bridging those two spellings is the whole point of the
      // candidate generation, and this is the rule that depends on it.
      const locked = {'sparse_infill_pattern': 'lockedzag'};
      const other = {'sparse_infill_pattern': 'crosshatch'};
      const gated = 'skin_infill_density';

      expect(disabledAt(locked), isNot(contains(gated)));
      expect(disabledAt(other), contains(gated));
      // Not just any non-default value: a near-miss pattern still disables it.
      expect(
        disabledAt(const {'sparse_infill_pattern': 'crosszag'}),
        contains(gated),
      );
    });

    test('turning one setting off never enables something it had disabled', () {
      // Sanity on the whole pass: dropping walls can only ever grey more out,
      // since no rule in the set is written to require walls to be absent.
      final base = disabledAt(const {});
      final noWalls = disabledAt(const {'wall_loops': '0'});
      expect(noWalls, containsAll(base));
      expect(noWalls.length, greaterThan(base.length));
    });

    test('enough rules reach a definite answer to prove the parser works', () {
      // Floors, not exact counts — a re-vendor may legitimately move them. What
      // they catch is a collapse: fail-open means a broken tokenizer or parser
      // can only ever *under*-disable, so a partial regression shows up here as
      // a sagging count while the targeted tests above may still pass.
      //
      // Measured at the pinned commit: 147 at defaults, 159 without walls.
      expect(disabledAt(const {}).length, greaterThan(100));
      expect(disabledAt(const {'wall_loops': '0'}).length, greaterThan(100));
    });
  });
}
