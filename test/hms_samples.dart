import 'package:bambuddy_mobile/core/models/printer_status.dart';

/// Real faults, in the shape bambuddy's WebSocket frame carries them
/// (`printer_manager.py::printer_state_to_dict`), each with where it came from.
///
/// The same payloads bambuddy's own tests are built on
/// (`backend/tests/unit/services/test_hms_severity_2728.py`) plus the ones
/// reported against this app. `description` is the server catalogue's text
/// (`backend/app/data/hms_catalog.json`), null where Bambu publishes none —
/// which is itself part of what each case pins.
class HmsSample {
  const HmsSample._(
    this.source,
    this.json, {
    required this.level,
    required this.alerts,
  });

  /// An `hms[]` fault: `attr` is module, module no., part, part no.; `code` is
  /// the level (high half) and the error (low half).
  factory HmsSample.hms(
    String source,
    int attr,
    int code, {
    String? description,
    List<String> actions = const [],
    required bool alerts,
  }) {
    final level = (code >> 16) & 0xFFFF;
    return HmsSample._(
      source,
      {
        'code': '0x${code.toRadixString(16)}',
        'attr': attr,
        'module': (attr >> 24) & 0xFF,
        'severity': level,
        'actions': actions,
        'job_id': null,
        'full_code': _hex(attr) + _hex(code),
        'description': description,
      },
      level: level >= 1 && level <= 4 ? level : null,
      alerts: alerts,
    );
  }

  /// A `print_error` fault: one 32-bit word, module then error, whose first
  /// error digit carries the level (`hms_errors.py::alert_level_from_print_error`).
  factory HmsSample.printError(
    String source,
    int value, {
    String? description,
    List<String> actions = const [],
    required bool alerts,
  }) {
    final error = value & 0xFFFF;
    final level = const {0x4: 1, 0x8: 2, 0xC: 3}[(error >> 12) & 0xF];
    return HmsSample._(
      source,
      {
        'code': '0x${error.toRadixString(16)}',
        'attr': value,
        'module': (value >> 24) & 0xFF,
        'severity': level ?? 0,
        'actions': actions,
        'job_id': null,
        'full_code': _hex(value),
        'description': description,
      },
      level: level,
      alerts: alerts,
    );
  }

  final String source;
  final Map<String, Object?> json;

  /// The level the app must read off it.
  final int? level;

  /// Whether a notification must come of it, given the server's text only.
  final bool alerts;

  HmsError get fault => HmsError.fromJson(json);

  String get fullCode => json['full_code']! as String;

  String? get description => json['description'] as String?;

  @override
  String toString() => '$fullCode ($source)';

  static String _hex(int v) =>
      v.toRadixString(16).padLeft(8, '0').toUpperCase();
}

/// Bug report #46: an X2D switched on at the plug, for about five seconds.
final hmsX2dChamberHeater = HmsSample.hms(
  'X2D power-up, report #46',
  0x03009100,
  0x0001000A,
  description:
      'The temperature of chamber heater 1 is abnormal. '
      'The AC board may be broken.',
  alerts: true,
);

/// Bug report #46, the second of the pair — the same `code`, another part.
final hmsX2dHeatbed = HmsSample.hms(
  'X2D power-up, report #46',
  0x03000100,
  0x0001000A,
  description:
      'The heatbed temperature control is abnormal; '
      'the AC board may be broken.',
  alerts: true,
);

/// A filament runout: pauses the print and offers the buttons to go on.
final hmsRunout = HmsSample.printError(
  'filament runout',
  0x03008004,
  description: 'Filament ran out. Please load new filament.',
  actions: const ['RESUME_PRINTING', 'STOP_PRINTING'],
  alerts: true,
);

final List<HmsSample> hmsSamples = [
  HmsSample.hms(
    'P2S, bambuddy #2728',
    0x05000300,
    0x0002000E,
    description:
        'Some modules are incompatible with the printer\'s firmware version, '
        'which may affect use. Please go to the "Firmware" page to update '
        'after connected to the internet, or you may update offline '
        'according to wiki.',
    alerts: true,
  ),
  // Also the healthy X2D this app painted red on 2026-07-29.
  HmsSample.hms('P2S, bambuddy #2728', 0x05000600, 0x00020070, alerts: false),
  HmsSample.hms('P2S, bambuddy #2728', 0x05000200, 0x0003000A, alerts: false),
  HmsSample.hms(
    'H2C, bambuddy #1840 — paused the printer, Bambu lists no text',
    0x05000600,
    0x00020005,
    alerts: false,
  ),
  HmsSample.hms(
    'nozzle temperature, a level-1 code in Bambu\'s catalogue',
    0x03000200,
    0x00010008,
    description:
        'The extruder nozzle temperature is abnormal and cannot reach the '
        'set value. This may be caused by an improperly installed nozzle '
        'silicone sock.',
    alerts: true,
  ),
  HmsSample.hms(
    'H2S cancel echo, bambuddy #2728 — listed without text',
    0x0C000100,
    0x0002001B,
    alerts: false,
  ),
  HmsSample.hms(
    'top cover open — a notice a printer holds through a whole print',
    0x03009700,
    0x00030001,
    description: 'The top cover is open.',
    alerts: false,
  ),
  HmsSample.hms(
    'top cover open, waiting on the user',
    0x03009700,
    0x00030001,
    description: 'The top cover is open.',
    actions: const ['OK_BUTTON'],
    alerts: true,
  ),
  HmsSample.hms(
    'level 0, Bambu\'s invalid level',
    0x05000000,
    0x00004038,
    alerts: false,
  ),
  hmsX2dChamberHeater,
  hmsX2dHeatbed,
  HmsSample.hms(
    'MQTT command verification failed, bambuddy #2732',
    0x05000500,
    0x00010007,
    description:
        'MQTT Command verification failed. Please update Studio (including '
        'the network plugin) or Handy to the latest version, then restart '
        'the software and try again.',
    alerts: true,
  ),
  hmsRunout,
  HmsSample.printError(
    'first-layer defect prompt — a print_error at the notice level',
    0x0C00C003,
    description: 'Possible defects were detected in the first layer.',
    alerts: true,
  ),
  HmsSample.printError(
    'task cancel echo — only an older server forwards it',
    0x0300400C,
    description: 'The task was canceled.',
    alerts: false,
  ),
];
