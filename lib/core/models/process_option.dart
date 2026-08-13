/// The vendored OrcaSlicer process-option metadata under `assets/slicer/` —
/// what options exist, how each is edited, how they are grouped.
///
/// Generated from OrcaSlicer's `PrintConfig.cpp` / `Tab.cpp` by the bambuddy
/// server and copied here unmodified (`assets/slicer/PROVENANCE`). These classes
/// describe that generated shape: what the generator could not express
/// faithfully keeps the loose type it arrives in rather than being coerced.
library;

/// OrcaSlicer's `ConfigOptionType` names. The plural forms are per-extruder
/// vectors, stored in a process preset as a list rather than a scalar.
enum OptionType {
  coBool,
  coBools,
  coInt,
  coFloat,
  coFloats,
  coPercent,
  coFloatOrPercent,
  coFloatsOrPercents,
  coEnum,
  coString;

  static const _byName = <String, OptionType>{
    'coBool': coBool,
    'coBools': coBools,
    'coInt': coInt,
    'coFloat': coFloat,
    'coFloats': coFloats,
    'coPercent': coPercent,
    'coFloatOrPercent': coFloatOrPercent,
    'coFloatsOrPercents': coFloatsOrPercents,
    'coEnum': coEnum,
    'coString': coString,
  };

  /// Null for a type with no editor and no wire form here, so the option is
  /// dropped rather than guessed at: the server does not refuse a wrongly
  /// serialised value, it drops it with a log line — which reaches the user as a
  /// successful print missing one setting.
  static OptionType? tryParse(Object? raw) =>
      raw is String ? _byName[raw] : null;

  /// Whether the config stores this as a per-extruder list.
  bool get isVector =>
      this == coBools || this == coFloats || this == coFloatsOrPercents;
}

/// OrcaSlicer's visibility tiers. Declaration order **is** the rank: a mode
/// selector shows every option whose tier is at or below the selected one, and
/// [develop] sorting last is what keeps those options out of the app entirely.
enum OptionMode {
  simple,
  advanced,
  expert,
  develop;

  static const _byName = <String, OptionMode>{
    'simple': simple,
    'advanced': advanced,
    'expert': expert,
    'develop': develop,
  };

  /// An unrecognised tier reads as [develop], so a future mode name is hidden
  /// until someone looks at it rather than exposed by accident.
  static OptionMode parse(Object? raw) =>
      (raw is String ? _byName[raw] : null) ?? develop;

  bool visibleAt(OptionMode selected) => index <= selected.index;
}

/// One editable process option.
class ProcessOption {
  const ProcessOption({
    required this.key,
    required this.type,
    required this.mode,
    required this.label,
    this.tooltip,
    this.sidetext,
    this.min,
    this.max,
    this.enumValues,
    this.enumLabels,
    this.defaultValue,
  });

  /// Null when [OptionType.tryParse] does not recognise the type — see there.
  static ProcessOption? tryFromJson(String key, Map<String, dynamic> json) {
    final type = OptionType.tryParse(json['type']);
    if (type == null) return null;
    return ProcessOption(
      key: key,
      type: type,
      mode: OptionMode.parse(json['mode']),
      // Every entry but one carries a label; the key is a usable fallback and
      // beats an empty row.
      label: (json['label'] as String?)?.trim().isNotEmpty == true
          ? json['label'] as String
          : key,
      tooltip: json['tooltip'] as String?,
      sidetext: json['sidetext'] as String?,
      min: json['min'],
      max: json['max'],
      enumValues: (json['enum_values'] as List?)?.whereType<String>().toList(),
      enumLabels: (json['enum_labels'] as List?)?.whereType<String>().toList(),
      defaultValue: json['default'],
    );
  }

  /// The config key, which is also what goes into `process_overrides`.
  final String key;

  final OptionType type;
  final OptionMode mode;

  /// English, verbatim from `PrintConfig.cpp` — deliberately not localised, see
  /// the plan's §10.
  final String label;
  final String? tooltip;

  /// Unit shown after the field ("mm", "mm/s²", "%").
  final String? sidetext;

  /// Bounds as the generator emitted them: usually a number, but a handful are
  /// C++ expressions it could not resolve, so the JSON type is `num | String`.
  /// Read them through the codec's `numericBound`, never cast blindly.
  final Object? min;
  final Object? max;

  /// Wire values and their display labels, index-aligned. Set for `coEnum`.
  final List<String>? enumValues;
  final List<String>? enumLabels;

  /// OrcaSlicer's compiled-in default: `String`, `num`, `bool` or `List`. Only
  /// the last-resort baseline — the preset's own value, when the server can
  /// report one, is what the user edits against.
  final Object? defaultValue;
}

/// One labelled block of options inside a page, in display order.
class ProcessGroup {
  const ProcessGroup({required this.group, required this.options});

  factory ProcessGroup.fromJson(Map<String, dynamic> json) => ProcessGroup(
        group: json['group'] as String? ?? '',
        options: (json['options'] as List?)?.whereType<String>().toList() ??
            const [],
      );

  final String group;

  /// Option keys, to look up in the schema.
  final List<String> options;
}

/// One page of the settings tree — the tabs OrcaSlicer shows under Print
/// Settings (Quality, Strength, Speed, …).
class ProcessPage {
  const ProcessPage({required this.page, required this.groups, this.icon});

  factory ProcessPage.fromJson(Map<String, dynamic> json) => ProcessPage(
        page: json['page'] as String? ?? '',
        icon: json['icon'] as String?,
        groups: (json['groups'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(ProcessGroup.fromJson)
                .toList() ??
            const [],
      );

  final String page;

  /// The server frontend's icon name, kept verbatim; nothing maps it to a
  /// Flutter icon.
  final String? icon;

  final List<ProcessGroup> groups;
}

/// One enable/disable rule from OrcaSlicer's `toggle_print_fff_options`.
class ToggleRule {
  const ToggleRule({required this.fields, required this.enableIf});

  factory ToggleRule.fromJson(Map<String, dynamic> json) => ToggleRule(
        fields:
            (json['fields'] as List?)?.whereType<String>().toList() ?? const [],
        enableIf: json['enable_if'] as String? ?? '',
      );

  /// Option keys this rule governs.
  final List<String> fields;

  /// A C++ expression over [ToggleRules.locals] and `config->…` reads, verbatim
  /// from the slicer's source. Interpreted, not translated.
  final String enableIf;
}

/// The rule set, plus the named C++ locals its expressions are written over.
class ToggleRules {
  const ToggleRules({required this.locals, required this.rules});

  factory ToggleRules.fromJson(Map<String, dynamic> json) => ToggleRules(
        locals: {
          for (final e in ((json['locals'] as Map?) ?? const {}).entries)
            if (e.key is String && e.value is String)
              e.key as String: e.value as String,
        },
        rules: (json['rules'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(ToggleRule.fromJson)
                .toList() ??
            const [],
      );

  /// No rules means nothing is ever disabled, which is the fail-open answer the
  /// evaluator gives for anything it cannot decide anyway.
  static const empty = ToggleRules(locals: {}, rules: []);

  /// Name → C++ expression. Locals are defined in terms of config reads and of
  /// each other.
  final Map<String, String> locals;

  final List<ToggleRule> rules;
}
