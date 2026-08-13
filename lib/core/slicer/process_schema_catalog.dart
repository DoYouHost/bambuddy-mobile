import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;

import '../models/process_option.dart';

/// Decoded form of the three vendored files, as they come out of `jsonDecode`.
typedef _RawCatalog = (
  Map<String, dynamic> schema,
  List<dynamic> tree,
  Map<String, dynamic> toggles,
);

/// Runs in the isolate — 122 KB of JSON is the whole reason this is off the UI
/// thread, and only plain maps and lists cross back.
_RawCatalog _decode(List<String> sources) => (
      jsonDecode(sources[0]) as Map<String, dynamic>,
      jsonDecode(sources[1]) as List<dynamic>,
      jsonDecode(sources[2]) as Map<String, dynamic>,
    );

/// Reads one asset by key. Injectable so tests can drive the degrade-to-empty
/// paths, which are otherwise unreachable: the real keys are constants and a
/// bundled asset is always valid.
typedef AssetReader = Future<String> Function(String key);

/// The vendored OrcaSlicer process metadata (`assets/slicer/`), loaded once per
/// isolate and kept.
///
/// Mirrors `HmsCatalog`: lazy, idempotent, degrading to empty rather than
/// throwing. What differs is what empty means — HMS falls back to a raw error
/// code, while a settings screen with no schema has nothing to show, so callers
/// gate on [isLoaded] and keep the screen out of reach.
class ProcessSchemaCatalog {
  ProcessSchemaCatalog({AssetReader? readAsset})
      : _readAsset = readAsset ?? rootBundle.loadString;

  /// Shared instance per isolate.
  static final ProcessSchemaCatalog instance = ProcessSchemaCatalog();

  final AssetReader _readAsset;

  Map<String, ProcessOption> _schema = const {};
  List<ProcessPage> _tree = const [];
  ToggleRules _toggles = ToggleRules.empty;

  Future<void>? _loading;

  /// Option key → metadata. A key whose `type` cannot be serialised is absent,
  /// so a lookup miss is the one check callers need before rendering.
  Map<String, ProcessOption> get schema => _schema;

  /// Pages and groups in display order. A key it names may be missing from
  /// [schema] — skip those rather than render a row nothing can edit.
  List<ProcessPage> get tree => _tree;

  ToggleRules get toggles => _toggles;

  /// False until [load] has succeeded, and permanently false if the assets are
  /// missing or corrupt — which is a build error, not a server problem.
  ///
  /// [toggles] is deliberately not part of this. A rule set that parsed to
  /// nothing disables nothing, which is the same fail-open answer the evaluator
  /// gives for any condition it cannot decide, so it is no reason to withhold
  /// the whole screen. What catches a re-vendor that renamed the rule file's
  /// keys is `test/core/slicer/process_schema_catalog_test.dart`, at build time.
  bool get isLoaded => _schema.isNotEmpty && _tree.isNotEmpty;

  /// Reads and parses the assets. Concurrent callers share one load, and a
  /// failed attempt is not retried: a corrupt bundled asset does not become
  /// valid on the second tap.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final sources = await Future.wait([
        _readAsset('assets/slicer/process-schema.json'),
        _readAsset('assets/slicer/process-ui-tree.json'),
        _readAsset('assets/slicer/process-toggle-rules.json'),
      ]);
      final (rawSchema, rawTree, rawToggles) = await compute(_decode, sources);

      final schema = <String, ProcessOption>{};
      for (final entry in rawSchema.entries) {
        final json = entry.value;
        if (json is! Map<String, dynamic>) continue;
        final option = ProcessOption.tryFromJson(entry.key, json);
        if (option != null) schema[entry.key] = option;
      }
      _schema = schema;
      _tree = rawTree
          .whereType<Map<String, dynamic>>()
          .map(ProcessPage.fromJson)
          .toList();
      _toggles = ToggleRules.fromJson(rawToggles);
    } on Object {
      _schema = const {};
      _tree = const [];
      _toggles = ToggleRules.empty;
    }
  }
}
