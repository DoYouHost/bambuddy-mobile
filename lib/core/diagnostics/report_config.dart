import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:app_report_client/app_report_client.dart';

import 'filament_material.dart';

/// Bambuddy's half of the report contract. The rules below are asserted against
/// real payloads in `http_probe_test.dart` and `redaction_real_payloads_test`.

/// The session's two hard ceilings; `docs/diagnostics-log.md` has the reasoning
/// behind both numbers. They live here rather than in `app_diagnostics`: how
/// long one of *these* bugs takes to reproduce, and how much log that is worth,
/// are answers about this app.
const recordingLimit = Duration(minutes: 30);
const recordingSizeLimit = 20 * 1024 * 1024;

/// What the HTTP probe may quote back, and how much of it.
///
/// Six kilobytes because that is what the records worth reading measure: a live
/// printer status is 4.6 kB and a maintenance overview 3.2 kB. The first cut of
/// this (1.9 kB) turned both into escaped, truncated text, losing the AMS tail
/// and most of the maintenance list. The clipped ceiling stays under
/// `LogRedactor.maxStringLength`, so an over-long sample is marked once rather
/// than twice.
final HttpProbeConfig bambuddyHttpProbe = HttpProbeConfig(
  sampledPaths: _sampledPaths,
  neverSampled: _neverSampled,
  maxSampleChars: 6 * 1024,
  maxClippedChars: 1900,
  pathOf: loggablePath,
);

/// Endpoints whose answers are the app's content.
final RegExp _sampledPaths = RegExp(
  r'/api/v1/(queue|archives|printers|inventory|spoolman'
  r'|smart-plugs|maintenance|projects|library|scheduled-dryings'
  r'|location-ha-sensors)(/|$)',
);

/// Checked before [_sampledPaths] and wins over it.
final RegExp _neverSampled = RegExp(r'(token|api-keys)(/|$)');

/// How the interaction probe reads this app's identifier grammar: `id@MATERIAL`
/// where the material is on [FilamentMaterial]'s closed list, and nothing at
/// all where it is not.
({String id, Map<String, Object?> fields}) bambuddyIdFields(String rawId) {
  final tag = FilamentMaterial.split(rawId);
  return (
    id: tag.id,
    fields: tag.material == null ? const {} : {'mat': tag.material},
  );
}

/// No trailing slash — both relay endpoints hang off this, and the prefix is
/// what picks the repository.
const String relayBaseUrl = 'https://app-relay.morganmlg.com/bambuddy';

/// Must equal the log's own `v`: the relay accepts a fixed window of schemas, so
/// bumping it means registering the new one there first.
const int reportLogSchema = LogHeader.formatVersion;

LogRedactor bambuddyRedactor({int maxStringLength = 2000}) => LogRedactor(
  maxStringLength: maxStringLength,
  ourKeys: _ourKeys,
  secretKeyPatterns: [_secretKey],
  valuePatterns: [(_apiKey, '[APIKEY]'), (_serial, '[SERIAL]')],
  freeTextKeys: _freeTextKeys,
  schemaKeys: _schemaKeys,
);

/// The app's own vocabulary, exempt from the scrub: a server called `demo` or
/// `pla` would otherwise eat every control id and every material.
final Map<String, RegExp> _ourKeys = {
  'id': RegExp(r'^\w+(\.\w+)*$'),
  'mat': RegExp(r'^[A-Z0-9]+(-[A-Z0-9]+)*$'),
  'event': RegExp(r'^[a-zA-Z]+$'),
  'reason': RegExp(r'^[a-zA-Z]+$'),
  'limit': RegExp(r'^[a-z]+$'),
};

/// Printer credentials, plus the smart-plug wiring, which describes a house
/// rather than bambuddy. `entity`/`topic` fenced so `identity` survives; the
/// `*_path` selectors stay readable on purpose.
final RegExp _secretKey = RegExp(
  r'(access_?code|serial'
  r'|(?:^|[^a-z0-9])entity|(?:^|[^a-z0-9])topic|headers|rest_\w*(?:url|body))',
  caseSensitive: false,
);

final RegExp _apiKey = RegExp(r'\bbb_[A-Za-z0-9_-]{8,}');

/// The letter in third position keeps HMS codes and stray floats out.
final RegExp _serial = RegExp(
  r'\b(?:0[0-3][A-Z][A-Z0-9]{9,13}|\d{2}[A-Z][0-9A-Z]{12})\b',
  caseSensitive: false,
);

/// Fields the user names. Exact, not substrings: `printer_name` is theirs and
/// `printer_model` is Bambu's.
const Set<String> _freeTextKeys = {
  'archive_name',
  'description',
  'file_name',
  'filename',
  'folder',
  'folder_name',
  'library_file_name',
  'location',
  'model_name',
  'name',
  'note',
  'notes',
  'nozzle_diameter_label',
  'path',
  'printer_name',
  'project_name',
  'spool_name',
  'subtask_name',
  'tags',
  'target_location',
  'target_model',
  'task_name',
  'title',
  'vendor',
};

/// Where a machine's exact formatting is the diagnosis and the shape rule would
/// measure it away.
const Set<String> _schemaKeys = {
  'locale',
  'mqtt_energy_path',
  'mqtt_power_path',
  'mqtt_state_path',
  'rest_power_path',
  'rest_status_path',
  'server_version',
  'timezone',
  'version',
};
