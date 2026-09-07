/// Evaluates OrcaSlicer's `toggle_print_fff_options` enable/disable rules, so
/// the process-settings screen greys out the same fields the desktop slicer does.
///
/// The vendored `process-toggle-rules.json` carries them verbatim from the C++
/// source: each rule is a list of option keys plus an `enable_if` expression
/// written in C++, over named locals that are themselves C++ expressions. This
/// interprets those expressions and resolves locals recursively, rather than
/// hand-translating a subset — which is what upstream's own evaluator does, for
/// 11 of 68 locals, silently enabling the rest.
///
/// **The cardinal rule is fail open.** Anything undecidable leaves the field
/// enabled. A wrongly-greyed control hides a setting the user needs and reads as
/// a bug; a wrongly-enabled one merely lets them set something the slicer
/// ignores, which is what every other settings surface in this app already does.
/// Every `null` returned below is that rule, not an oversight.
///
/// Ported from the server's `frontend/src/lib/slicerToggle.ts` — see the note in
/// [process_settings_codec] on resolving server paths.
library;

import '../models/process_option.dart';
import 'process_settings_codec.dart' show SettingValue, numericBound;

/// Returns the option keys the current values disable.
///
/// Only a rule evaluating to a definite `false` contributes; unknown and true
/// both leave the field enabled.
Set<String> disabledOptionKeys({
  required Map<String, SettingValue> values,
  required Map<String, ProcessOption> schema,
  required ToggleRules toggles,
}) {
  final config = _ConfigReader(values, schema);
  // Locals are shared across the whole pass: they depend only on the values,
  // and re-resolving them per rule is the difference between one traversal and
  // 152 of them on every keystroke.
  final memo = <String, Object?>{};
  final disabled = <String>{};

  for (final rule in toggles.rules) {
    final condition = conditionOf(rule.enableIf);
    if (condition == null) continue;
    final evaluator = _Evaluator(
      config,
      toggles.locals,
      schema,
      <String>{},
      memo,
    );
    if (_asBoolean(evaluator.evaluate(condition)) == false) {
      disabled.addAll(rule.fields);
    }
  }
  return disabled;
}

/// Takes the condition off an `enable_if`, dropping the trailing `variant_index`
/// argument the C++ helper takes.
///
/// Only parentheses count towards nesting: every argument-bearing call in the
/// rule set is parenthesised, while `<` and `>` appear far more often as
/// comparisons than as template brackets.
String? conditionOf(String expression) {
  var depth = 0;
  for (var i = 0; i < expression.length; i++) {
    final ch = expression[i];
    if (ch == '(') {
      depth++;
    } else if (ch == ')') {
      depth--;
    } else if (ch == ',' && depth == 0) {
      final head = expression.substring(0, i).trim();
      return head.isEmpty ? null : head;
    }
  }
  final trimmed = expression.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// A read of an enum-typed option, carrying the key so a comparison against a
/// C++ enumerator can be checked against that option's declared values.
class _EnumRead {
  const _EnumRead(this.optionKey, this.value);
  final String optionKey;
  final String? value;
}

/// A bare C++ enumerator (`ipGyroid`, `IroningType::NoIroning`) in an expression.
class _EnumSymbol {
  const _EnumSymbol(this.name);
  final String name;
}

/// Reads settings with schema defaults behind them.
class _ConfigReader {
  const _ConfigReader(this._values, this._schema);

  final Map<String, SettingValue> _values;
  final Map<String, ProcessOption> _schema;

  /// The user's override if they set one, else the schema default.
  ///
  /// Unwrapping runs before the fallback, unlike upstream, so that *every* empty
  /// shape falls back: there, an empty-string override fell back to the default
  /// while an empty vector did not, and instead read as a value the rules could
  /// not decide on.
  Object? read(String key) {
    final own = _firstScalar(_values[key]);
    if (own != null && own != '') return own;
    return _firstScalar(_schema[key]?.defaultValue);
  }

  bool has(String key) => _schema.containsKey(key);

  /// Vector options are per-extruder and every condition in the rule set tests
  /// the first entry — what `opt_float_nullable(key, variant_index)` reads for
  /// the active variant. Anything a config value cannot be reads as unknown.
  static Object? _firstScalar(Object? value) {
    var scalar = value;
    if (scalar is List) scalar = scalar.isEmpty ? null : scalar.first;
    return (scalar is bool || scalar is num || scalar is String)
        ? scalar
        : null;
  }
}

/// Accessor names that read a config key named by their first string argument.
///
/// `get_abs_value` appears in the rules and is deliberately **not** here, as
/// upstream leaves it out too: it resolves a float-or-percent against a
/// reference value, so reading it as the raw config value would produce
/// confidently wrong numbers — and a wrong definite answer is the one thing
/// fail-open exists to prevent.
const _accessors = <String>{
  'opt_bool',
  'opt_int',
  'opt_float',
  'opt_float_nullable',
  'opt_int_nullable',
  'opt_bool_nullable',
  'opt_enum',
  'opt_string',
  'option',
  'has',
};

enum _TokenKind { number, string, identifier, operator }

class _Token {
  const _Token(this.kind, this.text, [this.number]);
  final _TokenKind kind;
  final String text;
  final double? number;
}

/// Longest-first: `->` must be tried before `-`, `<=` before `<`.
const _operators = <String>[
  '->',
  '||',
  '&&',
  '==',
  '!=',
  '<=',
  '>=',
  '(',
  ')',
  ',',
  '<',
  '>',
  '!',
];

final _numberLiteral = RegExp(r'\d+(\.\d*)?f?');
final _identifierPattern = RegExp(
  r'[A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)*',
);

bool _isDigit(String ch) {
  final code = ch.codeUnitAt(0);
  return code >= 0x30 && code <= 0x39;
}

/// Null on anything unrecognised, which the caller turns into "enabled".
List<_Token>? _tokenize(String source) {
  final tokens = <_Token>[];
  var i = 0;
  while (i < source.length) {
    final ch = source[i];
    if (ch == ' ' || ch == '\t' || ch == '\n') {
      i++;
      continue;
    }
    if (ch == '"') {
      final end = source.indexOf('"', i + 1);
      if (end < 0) return null;
      tokens.add(_Token(_TokenKind.string, source.substring(i + 1, end)));
      i = end + 1;
      continue;
    }
    // C++ float literals carry an `f` suffix (`0.3f`) the extractor left intact.
    if (_isDigit(ch)) {
      final match = _numberLiteral.matchAsPrefix(source, i);
      final parsed = match == null ? null : numericBound(match[0]!);
      if (match == null || parsed == null) return null;
      tokens.add(_Token(_TokenKind.number, match[0]!, parsed));
      i += match[0]!.length;
      continue;
    }
    final op = _operators.where((o) => source.startsWith(o, i));
    if (op.isNotEmpty) {
      tokens.add(_Token(_TokenKind.operator, op.first));
      i += op.first.length;
      continue;
    }
    final id = _identifierPattern.matchAsPrefix(source, i);
    if (id != null) {
      tokens.add(_Token(_TokenKind.identifier, id[0]!));
      i += id[0]!.length;
      continue;
    }
    return null;
  }
  return tokens;
}

/// Recursive-descent evaluator. A resolved value is `bool`, `double`, `String`,
/// [_EnumRead] or [_EnumSymbol]; `null` means "could not determine".
class _Evaluator {
  _Evaluator(
    this._config,
    this._locals,
    this._schema,
    this._resolving,
    this._memo,
  );

  final _ConfigReader _config;
  final Map<String, String> _locals;
  final Map<String, ProcessOption> _schema;

  /// Locals currently being resolved — guards a cyclic definition.
  final Set<String> _resolving;
  final Map<String, Object?> _memo;

  List<_Token> _tokens = const [];
  int _pos = 0;

  Object? evaluate(String expression) {
    final tokens = _tokenize(expression);
    if (tokens == null || tokens.isEmpty) return null;
    _tokens = tokens;
    _pos = 0;
    final value = _parseOr();
    // Trailing tokens mean we misread the grammar; a partial parse is not a
    // result worth trusting.
    if (_pos != _tokens.length) return null;
    return value;
  }

  _Token? _peek() => _pos < _tokens.length ? _tokens[_pos] : null;

  bool _eat(String op) {
    final token = _peek();
    if (token != null &&
        token.kind == _TokenKind.operator &&
        token.text == op) {
      _pos++;
      return true;
    }
    return false;
  }

  Object? _parseOr() {
    var left = _parseAnd();
    while (_eat('||')) {
      final right = _parseAnd();
      final l = _asBoolean(left);
      final r = _asBoolean(right);
      // Short-circuit truth survives an unknown operand: `true || ???` is true.
      if (l == true || r == true) {
        left = true;
      } else if (l == null || r == null) {
        left = null;
      } else {
        left = l || r;
      }
    }
    return left;
  }

  Object? _parseAnd() {
    var left = _parseComparison();
    while (_eat('&&')) {
      final right = _parseComparison();
      final l = _asBoolean(left);
      final r = _asBoolean(right);
      if (l == false || r == false) {
        left = false;
      } else if (l == null || r == null) {
        left = null;
      } else {
        left = l && r;
      }
    }
    return left;
  }

  Object? _parseComparison() {
    final left = _parseUnary();
    for (final op in const ['==', '!=', '<=', '>=', '<', '>']) {
      if (_eat(op)) return _compare(left, _parseUnary(), op, _schema);
    }
    return left;
  }

  Object? _parseUnary() {
    if (_eat('!')) {
      final value = _asBoolean(_parseUnary());
      return value == null ? null : !value;
    }
    return _parsePrimary();
  }

  Object? _parsePrimary() {
    final token = _peek();
    if (token == null) return null;

    switch (token.kind) {
      case _TokenKind.number:
        _pos++;
        return token.number;
      case _TokenKind.string:
        _pos++;
        return token.text;
      case _TokenKind.operator:
        if (token.text != '(') return null;
        _pos++;
        final value = _parseOr();
        return _eat(')') ? value : null;
      case _TokenKind.identifier:
        _pos++;
        if (token.text == 'true') return true;
        if (token.text == 'false') return false;
        if (token.text == 'config') return _parseConfigAccess();
        // A bare identifier is either a named local or a C++ enumerator.
        final local = _locals[token.text];
        if (local != null) return _resolveLocal(token.text, local);
        return _EnumSymbol(token.text);
    }
  }

  /// Consumes the `->accessor<T>("key")` tail after a `config` identifier.
  Object? _parseConfigAccess() {
    if (!_eat('->')) return null;
    final accessor = _peek();
    if (accessor == null ||
        accessor.kind != _TokenKind.identifier ||
        !_accessors.contains(accessor.text)) {
      return null;
    }
    _pos++;

    // Optional `<ConfigOptionFloat>` / `<InfillPattern>` template argument.
    if (_eat('<')) {
      var depth = 1;
      while (depth > 0) {
        final token = _peek();
        if (token == null) return null;
        _pos++;
        if (token.kind == _TokenKind.operator && token.text == '<') depth++;
        if (token.kind == _TokenKind.operator && token.text == '>') depth--;
      }
    }

    if (!_eat('(')) return null;
    final arg = _peek();
    if (arg == null || arg.kind != _TokenKind.string) return null;
    _pos++;
    final key = arg.text;

    // Skip any further arguments (`, variant_index`, `, 0`).
    while (_eat(',')) {
      var depth = 0;
      for (;;) {
        final token = _peek();
        if (token == null) return null;
        final isOperator = token.kind == _TokenKind.operator;
        if (isOperator && token.text == '(') depth++;
        if (isOperator && token.text == ')') {
          if (depth == 0) break;
          depth--;
        }
        if (isOperator && token.text == ',' && depth == 0) break;
        _pos++;
      }
    }
    if (!_eat(')')) return null;

    // `config->option<T>("key")->value` — consume the trailing member access.
    if (_eat('->')) {
      final member = _peek();
      if (member == null || member.kind != _TokenKind.identifier) return null;
      _pos++;
    }

    if (accessor.text == 'has') return _config.has(key);

    final raw = _config.read(key);
    // Tag reads of enum options so a comparison against a C++ enumerator can
    // validate its transliteration against this option's declared values.
    if (_schema[key]?.enumValues != null) {
      return _EnumRead(key, raw is String ? raw : null);
    }
    return raw;
  }

  Object? _resolveLocal(String name, String source) {
    if (_memo.containsKey(name)) return _memo[name];
    if (_resolving.contains(name)) return null;

    _resolving.add(name);
    final nested = _Evaluator(_config, _locals, _schema, _resolving, _memo);
    final value = nested.evaluate(source);
    _resolving.remove(name);

    _memo[name] = value;
    return value;
  }
}

double? _asNumber(Object? value) {
  if (value is num) return value.toDouble();
  if (value is bool) return value ? 1 : 0;
  if (value is String) return numericBound(value);
  return null;
}

bool? _asBoolean(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value == '1' || value == 'true') return true;
  if (value == '0' || value == 'false') return false;
  return null;
}

/// JavaScript `String()` semantics, which is what these expressions were written
/// against — deliberately not the codec's process-JSON spelling, where a bool is
/// `1`. Only reachable when one operand is a string; in the vendored rules that
/// is always `opt_string(…) == ""`.
String _asComparisonString(Object? value) {
  if (value is bool) return value ? 'true' : 'false';
  if (value is double &&
      value.isFinite &&
      value == value.roundToDouble() &&
      value.abs() < 1e15) {
    return value.toInt().toString();
  }
  return '$value';
}

/// Compares two resolved values.
///
/// The interesting case is an enum option tested against a C++ enumerator:
/// `config->opt_enum<IroningType>("ironing_type") != IroningType::NoIroning`.
/// OrcaSlicer's enumerator spellings and its serialised config values are
/// related but not identical (`btNoBrim` → `no_brim`, `NoIroning` → `no
/// ironing`), so the plausible spellings are generated and the result is trusted
/// only when exactly one of them is a value the option actually declares. A
/// transliteration matching nothing yields null, not a confident `false` that
/// would grey out a field for the wrong reason.
Object? _compare(
  Object? left,
  Object? right,
  String op,
  Map<String, ProcessOption> schema,
) {
  final symbol = left is _EnumSymbol
      ? left
      : right is _EnumSymbol
      ? right
      : null;

  if (symbol != null) {
    if (op != '==' && op != '!=') return null;
    final other = left is _EnumSymbol ? right : left;
    if (other is! _EnumRead) return null;

    final declared = schema[other.optionKey]?.enumValues;
    if (declared == null || other.value == null) return null;

    final matches = _enumCandidates(
      symbol.name,
    ).where(declared.contains).toList();
    if (matches.length != 1) return null;

    final equal = matches.first == other.value;
    return op == '==' ? equal : !equal;
  }

  // An enum read compared against anything else is only meaningful by value.
  final l = left is _EnumRead ? left.value : left;
  final r = right is _EnumRead ? right.value : right;

  if (op == '==' || op == '!=') {
    if (l == null || r == null) return null;
    final equal = (l is String || r is String)
        ? _asComparisonString(l) == _asComparisonString(r)
        : _asNumber(l) == _asNumber(r);
    return op == '==' ? equal : !equal;
  }

  final ln = _asNumber(l);
  final rn = _asNumber(r);
  if (ln == null || rn == null) return null;
  return switch (op) {
    '<' => ln < rn,
    '<=' => ln <= rn,
    '>' => ln > rn,
    '>=' => ln >= rn,
    _ => null,
  };
}

/// Plausible config spellings for a C++ enumerator.
///
/// `IroningType::NoIroning` → `no_ironing`, `no ironing`, `noironing`;
/// `btNoBrim` → `no_brim`, `no brim`, `nobrim`.
List<String> _enumCandidates(String symbol) {
  final bare = symbol.contains('::')
      ? symbol.substring(symbol.lastIndexOf('::') + 2)
      : symbol;
  // Enumerators are either bare PascalCase or PascalCase behind a lowercase
  // type tag (ip*, bt*, sms*); try both readings.
  final cores = <String>[
    bare,
    ?RegExp(r'^[a-z]+([A-Z].*)$').firstMatch(bare)?[1],
  ];

  final out = <String>{};
  for (final core in cores) {
    final snake = core
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (m) => '${m[1]}_${m[2]}',
        )
        .toLowerCase();
    out.add(snake);
    out.add(snake.replaceAll('_', ' '));
    out.add(snake.replaceAll('_', ''));
  }
  return out.toList();
}
