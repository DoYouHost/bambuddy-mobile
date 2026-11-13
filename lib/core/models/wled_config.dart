import 'package:app_util/app_util.dart';

/// The printer states a WLED preset can be mapped to (server #1528), in the
/// order the web lists them (`WLEDSettings.tsx` `mappingKeys`).
enum WledState {
  idle('idle'),
  prepare('prepare'),
  printing('printing'),
  paused('paused'),
  finished('finished'),
  error('error'),
  queueWaiting('queue_waiting'),
  filamentProblem('filament_problem'),
  hmsError('hms_error'),
  offline('offline');

  const WledState(this.wire);

  final String wire;
}

/// `WLEDConfig` on a printer row and on `PATCH /printers/{id}`. WLED keeps
/// every colour and effect; the server only switches presets.
class WledConfig {
  const WledConfig({
    this.enabled = false,
    this.baseUrl,
    this.presets = const {},
    this.finishedTimeoutSeconds,
  });

  /// Lenient: a preset id outside the server's 1..250 or of the wrong type is
  /// dropped rather than failing the whole printer row.
  factory WledConfig.fromJson(Map<String, dynamic> json) {
    final raw = json['presets'];
    return WledConfig(
      enabled: json['enabled'] == true,
      baseUrl: toStringOrNull(json['base_url']),
      presets: {
        if (raw is Map<String, dynamic>)
          for (final state in WledState.values)
            if (toIntOrNull(raw[state.wire]) case final id?
                when isValidPresetId(id))
              state: id,
      },
      finishedTimeoutSeconds: toIntOrNull(json['finished_timeout_seconds']),
    );
  }

  final bool enabled;

  /// Stored as the server normalised it: trimmed, no trailing slash. A login
  /// in a stored URL comes back masked, but the server refuses one on input,
  /// so the app never sends or shows a real one.
  final String? baseUrl;

  /// A state with no entry has no preset and leaves WLED as it is.
  final Map<WledState, int> presets;

  /// Seconds after which Finished falls back to Idle; null or 0 never does.
  final int? finishedTimeoutSeconds;

  static const maxFinishedTimeoutSeconds = 86400;

  /// The range `WLEDPresets` validates; WLED itself numbers presets 1..250.
  static bool isValidPresetId(int id) => id >= 1 && id <= 250;

  /// The whole object, every state included: the route replaces the stored
  /// config rather than merging into it, as the web sends it.
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'base_url': baseUrl,
    'presets': {for (final s in WledState.values) s.wire: presets[s]},
    'finished_timeout_seconds': finishedTimeoutSeconds,
  };

  WledConfig copyWith({
    bool? enabled,
    String? Function()? baseUrl,
    Map<WledState, int>? presets,
    int? Function()? finishedTimeoutSeconds,
  }) => WledConfig(
    enabled: enabled ?? this.enabled,
    baseUrl: baseUrl != null ? baseUrl() : this.baseUrl,
    presets: presets ?? this.presets,
    finishedTimeoutSeconds: finishedTimeoutSeconds != null
        ? finishedTimeoutSeconds()
        : this.finishedTimeoutSeconds,
  );
}

/// One preset as `POST /printers/{id}/wled/presets` lists it: the server
/// already sorted them, dropped ids outside 1..250 and named a nameless one
/// by its id.
typedef WledPreset = ({int id, String name});

/// `WLEDConnectionInfo`: what the controller says about itself, both optional.
typedef WledConnectionInfo = ({String? name, String? version});
