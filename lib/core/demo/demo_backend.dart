import 'dart:math' as math;

import 'demo_config.dart';

/// Result of a routed demo request: HTTP status + JSON-encodable body.
typedef DemoResult = ({int status, Object? body});

/// In-process fake bambuddy server for demo mode (see [DemoConfig]).
///
/// Serves a fabricated dataset shaped like the real `/api/v1` contract
/// (reference: bambuddy backend schemas + `test/fixtures/`). State is mutable —
/// control actions (pause, plug toggle, spool CRUD, maintenance perform, …)
/// modify it so the app feels alive. The printing simulation is time-based
/// (progress derives from the wall clock), so it advances without timers and
/// stays consistent across REST, WS frames and the background isolate.
///
/// One instance per process (UI isolate and FGS isolate each get their own —
/// both compute the same time-based print state, so they stay in sync).
class DemoBackend {
  DemoBackend._() {
    // Start mid-print so the dashboard is immediately interesting.
    _printAnchor = _nowSec() - (_printCycleSec * 0.42).round();
  }

  static final DemoBackend instance = DemoBackend._();

  // --- Print simulation (printer 1) ---

  /// Simulated job duration; the job loops forever.
  static const _printCycleSec = 5400; // 90 min
  static const _totalLayers = 264;

  late int _printAnchor;
  bool _paused = false;
  int _pausedElapsed = 0;

  /// After "stop", printer 1 idles until this epoch second, then a new
  /// simulated job starts automatically.
  int _stoppedUntil = 0;

  static int _nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  int get _elapsedSec {
    if (_paused) return _pausedElapsed;
    return (_nowSec() - _printAnchor) % _printCycleSec;
  }

  bool get _stopped => _nowSec() < _stoppedUntil;

  void _pausePrint() {
    if (_paused || _stopped) return;
    _pausedElapsed = _elapsedSec;
    _paused = true;
  }

  void _resumePrint() {
    if (!_paused) return;
    _printAnchor = _nowSec() - _pausedElapsed;
    _paused = false;
  }

  void _stopPrint() {
    _paused = false;
    _stoppedUntil = _nowSec() + 90;
    _printAnchor = _stoppedUntil;
    _skippedObjects.clear();
  }

  /// Printable objects for the skip-objects screen. Only the X1 (id 1) is
  /// mid-print in demo; an idle/stopped printer has nothing to skip.
  Map<String, dynamic> _printObjectsResponse(int pid) {
    if (pid != 1 || _stopped) {
      return const {
        'objects': <Object>[],
        'total': 0,
        'skipped_count': 0,
        'is_printing': false,
        'bbox_all': null,
      };
    }
    final objects = [
      for (final o in _x1Objects)
        {...o, 'skipped': _skippedObjects.contains(o['id'])},
    ];
    return {
      'objects': objects,
      'total': objects.length,
      'skipped_count': _skippedObjects.length,
      'is_printing': true,
      'bbox_all': _x1BboxAll,
    };
  }

  /// Marks the requested ids skipped (X1 only, while printing). Body is a bare
  /// JSON array of identify_ids — [rawBody], not the coerced map.
  DemoResult _skipObjects(int pid, Object? rawBody) {
    if (pid != 1 || _stopped) {
      return (status: 400, body: {'detail': 'Printer not printing'});
    }
    final ids = rawBody is List
        ? rawBody.map((e) => e is int ? e : int.tryParse('$e')).nonNulls
        : const <int>[];
    final valid = ids.where((e) => _x1Objects.any((o) => o['id'] == e)).toList();
    _skippedObjects.addAll(valid);
    return _ok({'success': true, 'skipped_objects': valid});
  }

  // --- Mutable device state ---

  final Map<int, bool> _chamberLight = {1: true, 2: false};
  final Map<int, int> _speedLevel = {1: 2, 2: 2};
  // Optimistic temperature/airduct overrides set via control endpoints; when
  // present they win over the status generator's defaults so demo reflects them.
  final Map<int, double> _nozzleTarget = {};
  final Map<int, double> _bedTarget = {};
  final Map<int, int> _airductMode = {};
  // Fan overrides for the primary demo printer, keyed by fan id.
  final Map<String, int> _fanSpeeds = {};
  // AMS drying: minutes remaining keyed by ams id (demo doesn't count down).
  final Map<int, int> _dryTime = {};
  final Map<int, bool> _plugOn = {1: true, 2: false};
  // What the slot-configuration sheet wrote, keyed `printer:ams:tray`. Applied
  // over the generated status so a demo write shows on the card, the way the
  // printer's own push would.
  final Map<String, Map<String, dynamic>> _slotConfig = {};
  // Which preset each slot was given, keyed the same way — the mapping the real
  // server keeps so a configured slot can be named, not just shown.
  final Map<String, Map<String, dynamic>> _slotPreset = {};

  /// identify_ids skipped during the current X1 demo print. Reset on stop so a
  /// fresh cycle shows every object again.
  final Set<int> _skippedObjects = {};

  /// Printable objects on the X1's current plate ("Drawer organizer x4"), laid
  /// out 2×2 with plate coordinates (mm) inside [_x1BboxAll] so their markers
  /// land on the right spots in the skip-objects overlay. `width`/`height` are
  /// demo-only illustrative footprints (the real server sends none, see
  /// [PrintableObject]) — dividers tall and narrow, front/back wide and low —
  /// so the preview reads as actual parts instead of identical badges.
  static const _x1Objects = [
    {'id': 421, 'name': 'Divider_left.stl', 'x': 104.0, 'y': 104.0, 'width': 26.0, 'height': 34.0},
    {'id': 512, 'name': 'Divider_right.stl', 'x': 152.0, 'y': 104.0, 'width': 26.0, 'height': 34.0},
    {'id': 683, 'name': 'Drawer_front.stl', 'x': 104.0, 'y': 152.0, 'width': 34.0, 'height': 20.0},
    {'id': 705, 'name': 'Drawer_back.stl', 'x': 152.0, 'y': 152.0, 'width': 34.0, 'height': 20.0},
  ];
  static const _x1BboxAll = [88.0, 88.0, 168.0, 168.0];

  // --- Routing ---

  /// Handles one request. [body] is the raw Dio request payload
  /// (already JSON-decoded map/list, or null).
  DemoResult handle(String method, Uri uri, Object? requestBody) {
    var path = uri.path;
    const prefix = '/api/v1';
    if (!path.startsWith(prefix)) return _notFound();
    path = path.substring(prefix.length);
    final seg = path.split('/').where((s) => s.isNotEmpty).toList();
    final q = uri.queryParameters;
    final body = requestBody is Map<String, dynamic> ? requestBody : const <String, dynamic>{};

    try {
      return _route(method, seg, q, body, requestBody) ?? _fallback(method);
    } on Object {
      return (status: 500, body: {'detail': 'demo backend error'});
    }
  }

  DemoResult _ok(Object? body) => (status: 200, body: body);
  DemoResult _notFound() => (status: 404, body: {'detail': 'Not Found'});
  DemoResult _fallback(String method) =>
      method == 'GET' ? _notFound() : _ok(const <String, dynamic>{});

  DemoResult? _route(
    String m,
    List<String> s,
    Map<String, String> q,
    Map<String, dynamic> body,
    Object? rawBody,
  ) {
    int? id(int i) => i < s.length ? int.tryParse(s[i]) : null;
    bool at(int i, String name) => i < s.length && s[i] == name;

    if (s.isEmpty) return _notFound();
    switch (s[0]) {
      case 'auth':
        if (at(1, 'status')) {
          return _ok({'auth_enabled': true, 'requires_setup': false});
        }
        if (at(1, 'login') && m == 'POST') return _login(body);
        if (at(1, 'ws-token') || at(1, 'me')) {
          return at(1, 'me') ? _ok(_demoUser) : _ok({'token': 'demo-ws-token'});
        }
        return _notFound();

      case 'updates':
        // The demo queue speaks the 1.2.5 contract (tri-state calibrations), so
        // it has to report a version that matches, or the print form would offer
        // two states over three-state data.
        if (at(1, 'version')) {
          return _ok(const {
            'version': '1.2.5.1',
            'repo': 'maziggy/bambuddy',
          });
        }
        return _notFound();

      case 'printers':
        if (s.length == 1) return _ok(_printers);
        if (at(1, 'camera')) return _ok({'token': 'demo-camera-token'});
        if (at(1, 'available-filaments')) return _ok(_availableFilaments());
        final pid = id(1);
        if (pid == null) return _notFound();
        if (s.length == 2) {
          final p = _printers.where((e) => e['id'] == pid).firstOrNull;
          return p == null ? _notFound() : _ok(p);
        }
        if (at(2, 'status')) return _ok(statusJson(pid));
        if (at(2, 'print')) {
          if (at(3, 'objects')) return _ok(_printObjectsResponse(pid));
          if (at(3, 'skip-objects')) return _skipObjects(pid, rawBody);
          if (pid == 1) {
            if (at(3, 'pause')) _pausePrint();
            if (at(3, 'resume')) _resumePrint();
            if (at(3, 'stop')) _stopPrint();
          }
          return _ok(const {'ok': true});
        }
        if (at(2, 'cover')) {
          // No rendered images in demo; the skip screen falls back gracefully.
          return _notFound();
        }
        if (at(2, 'chamber-light')) {
          _chamberLight[pid] = q['on'] == 'true';
          return _ok(const {'ok': true});
        }
        if (at(2, 'print-speed')) {
          _speedLevel[pid] = int.tryParse(q['mode'] ?? '') ?? 2;
          return _ok(const {'ok': true});
        }
        if (at(2, 'temperature') && s.length >= 4) {
          final target = double.tryParse(q['target'] ?? '') ?? 0;
          switch (s[3]) {
            case 'nozzle':
              _nozzleTarget[pid] = target;
              return _ok(const {'ok': true});
            case 'bed':
              _bedTarget[pid] = target;
              return _ok(const {'ok': true});
            case 'chamber':
              return _ok(const {'ok': true});
          }
        }
        if (at(2, 'airduct-mode')) {
          _airductMode[pid] = q['mode'] == 'heating' ? 1 : 0;
          return _ok(const {'ok': true});
        }
        if (at(2, 'fan-speed')) {
          final fan = q['fan'] ?? '';
          final sp = int.tryParse(q['speed'] ?? '');
          if (sp != null && const ['part', 'aux', 'chamber'].contains(fan)) {
            _fanSpeeds[fan] = sp;
            return _ok(const {'ok': true});
          }
        }
        if (at(2, 'drying') && s.length >= 4) {
          final amsId = int.tryParse(q['ams_id'] ?? '') ?? 0;
          if (s[3] == 'start') {
            _dryTime[amsId] = (int.tryParse(q['duration'] ?? '') ?? 4) * 60;
            return _ok(const {'status': 'drying_started'});
          }
          if (s[3] == 'stop') {
            _dryTime[amsId] = 0;
            return _ok(const {'status': 'drying_stopped'});
          }
        }
        // Movement jogs + homing are momentary — no persistent demo state.
        if (at(2, 'bed-jog') ||
            at(2, 'xy-jog') ||
            at(2, 'extruder-jog') ||
            at(2, 'home-axes')) {
          return _ok(const {'success': true});
        }
        if (at(2, 'clear-plate')) return _ok(const {'ok': true});
        if (at(2, 'files')) {
          if (s.length == 3 && m == 'GET') return _ok(_printerFiles(q['path'] ?? '/'));
          return _fallback(m);
        }
        if (at(2, 'storage')) {
          return _ok({'used_bytes': 3 * 1024 * 1024 * 1024, 'free_bytes': 24 * 1024 * 1024 * 1024});
        }
        if (at(2, 'kprofiles')) {
          return _ok(_kProfilesResponse(q['nozzle_diameter'] ?? '0.4'));
        }
        if (at(2, 'slot-presets')) return _slotPresetRoute(m, pid, s, q);
        // `slots/{ams}/{tray}/configure` — ids are local to the unit.
        if (at(2, 'slots') && at(5, 'configure')) {
          return _configureSlot(pid, id(3) ?? 0, id(4) ?? 0, q);
        }
        if (at(2, 'ams')) {
          // `ams/{ams}/tray/{tray}/reset` — the tray id sits past the literal.
          if (at(6, 'reset')) return _resetSlot(pid, id(3) ?? 0, id(5) ?? 0);
          // Load, unload and the RFID re-read change nothing a demo can show:
          // there is no filament path to move anything along.
          return _ok(const {'ok': true});
        }
        return _fallback(m);

      case 'ams-history':
        return _ok(_amsHistory(id(1) ?? 1, id(2) ?? 0, int.tryParse(q['hours'] ?? '') ?? 24));

      case 'printer-sensor-history':
        return _ok(_heaterHistory(
          id(1) ?? 1,
          int.tryParse(q['hours'] ?? '') ?? 24,
          (q['kinds'] ?? 'nozzle,bed,chamber').split(','),
        ));

      case 'queue':
        return _queueRoute(m, s, body);

      case 'archives':
        return _archivesRoute(m, s, q);

      case 'smart-plugs':
        return _plugsRoute(m, s, body);

      case 'maintenance':
        return _maintenanceRoute(m, s, body);

      case 'inventory':
        return _inventoryRoute(m, s, q, body);

      case 'spoolman':
        // Demo runs the native backend; Spoolman variant serves empty data.
        return m == 'GET' ? _ok(const <Object>[]) : _fallback(m);

      case 'filament-catalog':
        return _ok(_filamentPresets);

      case 'firmware':
        if (at(1, 'updates') && s.length == 2) {
          return _ok({'updates': _firmware, 'updates_available': 1});
        }
        if (at(1, 'updates')) {
          final f = _firmware.where((e) => e['printer_id'] == id(2)).firstOrNull;
          return f == null ? _notFound() : _ok(f);
        }
        return _notFound();

      case 'library':
        return _libraryRoute(m, s, q, body);

      case 'projects':
        return _projectsRoute(m, s, q, body);

      case 'makerworld':
        if (at(1, 'status')) {
          return _ok(const {'has_cloud_token': false, 'can_download': false});
        }
        if (at(1, 'recent-imports')) return _ok(const <Object>[]);
        return _fallback(m);

      case 'cloud':
        if (at(1, 'status')) return _ok(const {'is_authenticated': false});
        // Nobody is logged in to Bambu Cloud in the demo, and the slot picker
        // is built to say so and fall back — serving a cloud tier anyway would
        // contradict the line above.
        if (at(1, 'settings')) {
          return (status: 401, body: {'detail': 'Not authenticated'});
        }
        if (at(1, 'builtin-filaments')) return _ok(_builtinFilaments);
        return _fallback(m);

      case 'local-presets':
        return _ok({'filament': _localPresets});

      case 'settings':
        return _ok(const {
          'require_plate_clear': false,
          'use_slicer_api': false,
          'currency': 'USD',
          // Auto-print snippets, as the real server stores them: a JSON string
          // keyed by printer model. Only the A1 mini has one, so demo shows both
          // halves of the gate — the injection checkbox appears, and picking the
          // X1C or the P1S says out loud that nothing would be injected.
          'gcode_snippets':
              '{"A1 mini":{"start_gcode":"G4 S1\\nM106 P1 S255",'
                  '"end_gcode":"G4 S1\\nG0 Y5 F500\\nG0 Y100 F5000\\n;plate-swap start"}}',
        });

      case 'slicer':
        if (at(1, 'printer-models')) return _ok(_printerModels);
        return _ok(const <String, dynamic>{});

      case 'users':
        return _ok([
          {'id': 1, 'username': DemoConfig.username},
        ]);
    }
    return null;
  }

  DemoResult _login(Map<String, dynamic> body) {
    if (body['username'] == DemoConfig.username &&
        body['password'] == DemoConfig.password) {
      return _ok({
        'access_token': 'demo.access.token',
        'token_type': 'bearer',
        'user': _demoUser,
        'requires_2fa': false,
      });
    }
    return (status: 401, body: {'detail': 'Incorrect username or password'});
  }

  Map<String, dynamic> get _demoUser => {
        'id': 1,
        'username': DemoConfig.username,
        'email': null,
        'role': 'admin',
        'is_active': true,
        'is_admin': true,
        'auth_source': 'local',
        'groups': const <Object>[],
        'permissions': const <Object>[],
        'created_at': _iso(_daysAgo(60)),
      };

  // --- Printers + status ---

  static final List<Map<String, dynamic>> _printers = [
    {
      'id': 1,
      'name': 'X1 Carbon',
      'serial_number': '01P00A390800000',
      'ip_address': '192.168.4.21',
      'access_code': '18354270',
      'model': 'X1C',
      'location': 'Workshop',
      'is_active': true,
      'nozzle_count': 1,
    },
    {
      'id': 2,
      'name': 'P1S',
      'serial_number': '01S00C471200000',
      'ip_address': '192.168.4.22',
      'access_code': '92641835',
      'model': 'P1S',
      'location': 'Office',
      'is_active': true,
      'nozzle_count': 1,
    },
    {
      'id': 3,
      'name': 'A1 mini',
      'serial_number': '039M0B584300000',
      'ip_address': '192.168.4.23',
      'access_code': '30157294',
      'model': 'A1 mini',
      'location': 'Workshop',
      'is_active': true,
      'nozzle_count': 1,
    },
    // Carries both P2S accessory fan kits — the only configuration that shows
    // four fan tiles and the "Exhaust" label, so the layout is reachable
    // without the hardware.
    {
      'id': 4,
      'name': 'P2S',
      'serial_number': '01N70D216500000',
      'ip_address': '192.168.4.24',
      'access_code': '47281630',
      'model': 'P2S',
      'location': 'Workshop',
      'is_active': true,
      'nozzle_count': 1,
    },
  ];

  /// Full status for the REST endpoint (`id`+`name` included).
  /// For WS frames use [statusData] (id travels as `printer_id`).
  Map<String, dynamic> statusJson(int printerId) => {
        'id': printerId,
        ...statusData(printerId),
      };

  /// Status payload without `id` — the WS `data` shape.
  Map<String, dynamic> statusData(int printerId) =>
      _withSlotConfig(printerId, switch (printerId) {
        1 => _statusPrinting(),
        2 => _statusIdle(),
        4 => _statusAccessoryFans(),
        _ => const {
            'name': 'A1 mini',
            'model': 'A1 mini',
            'connected': false,
            'state': null,
          },
      });

  /// Lays whatever the slot sheet wrote over the generated trays.
  ///
  /// Applied here rather than in the tray builders so both the REST poll and
  /// the WS frame carry it — a demo write that only one of them saw would flip
  /// back and forth as the two arrive.
  Map<String, dynamic> _withSlotConfig(
    int printerId,
    Map<String, dynamic> status,
  ) {
    if (_slotConfig.isEmpty) return status;
    final units = status['ams'];
    if (units is! List) return status;
    return {
      ...status,
      'ams': [
        for (final unit in units)
          if (unit is! Map<String, dynamic>)
            unit
          else
            {
              ...unit,
              'tray': [
                for (final tray in (unit['tray'] as List? ?? const []))
                  if (tray is! Map<String, dynamic>)
                    tray
                  else
                    {
                      ...tray,
                      ...?_slotConfig['$printerId:${unit['id']}:${tray['id']}'],
                    },
              ],
            },
      ],
    };
  }

  /// Small deterministic wiggle so temperatures/power look alive.
  double _wiggle(double amplitude, {int periodSec = 90, int phase = 0}) {
    final t = (_nowSec() + phase) * 2 * math.pi / periodSec;
    return math.sin(t) * amplitude;
  }

  double _r1(double v) => (v * 10).roundToDouble() / 10;

  Map<String, dynamic> _statusPrinting() {
    final stopped = _stopped;
    final elapsed = _elapsedSec;
    final frac = elapsed / _printCycleSec;
    final printing = !stopped;
    // Paused print keeps temperatures at target; only fans/motion stop.
    final heating = printing;
    final moving = printing && !_paused;

    return {
      'name': 'X1 Carbon',
      'model': 'X1C',
      'connected': true,
      'state': stopped ? 'IDLE' : (_paused ? 'PAUSE' : 'RUNNING'),
      'current_print': printing ? 'Drawer organizer x4.3mf' : null,
      'subtask_name': printing ? 'Drawer organizer x4' : null,
      'gcode_file': printing ? '/data/Metadata/plate_1.gcode' : null,
      'progress': printing ? _r1(frac * 100) : 0,
      'remaining_time':
          printing ? ((_printCycleSec - elapsed) / 60).ceil() : 0,
      'layer_num': printing ? (frac * _totalLayers).floor() : 0,
      'total_layers': printing ? _totalLayers : 0,
      'temperatures': {
        'nozzle': _r1(heating ? 220 + _wiggle(1.4) : 152),
        'nozzle_target': _nozzleTarget[1] ?? (heating ? 220.0 : 0.0),
        'bed': _r1(heating ? 65 + _wiggle(0.6, phase: 30) : 48),
        'bed_target': _bedTarget[1] ?? (heating ? 65.0 : 0.0),
        'chamber': _r1(33 + _wiggle(0.8, phase: 60)),
        'nozzle_heating': false,
        'bed_heating': false,
        'chamber_heating': false,
      },
      'cooling_fan_speed': _fanSpeeds['part'] ?? (moving ? 70 : 0),
      'big_fan1_speed': _fanSpeeds['aux'] ?? (moving ? 40 : 0),
      'big_fan2_speed': _fanSpeeds['chamber'] ?? (moving ? 60 : 0),
      'heatbreak_fan_speed': heating ? 90 : 0,
      'speed_level': _speedLevel[1] ?? 2,
      'chamber_light': _chamberLight[1] ?? true,
      'airduct_mode': _airductMode[1] ?? 0,
      'wifi_signal': -52,
      'door_open': false,
      'ams_exists': true,
      'ams': [_amsUnit1()],
      'vt_tray': const <Object>[],
      'tray_now': printing ? 1 : 255,
      'active_extruder': 0,
      'ams_status_main': 0,
      'ams_status_sub': 0,
      'hms_errors': const <Object>[],
      'firmware_version': '01.08.02.00',
      'cover_url': null,
      'supports_drying': true,
      'current_plate_id': 1,
      'awaiting_plate_clear': false,
      'printable_objects_count': 4,
      'sdcard': true,
      'ipcam': true,
    };
  }

  Map<String, dynamic> _statusIdle() => {
        'name': 'P1S',
        'model': 'P1S',
        'connected': true,
        'state': 'IDLE',
        'current_print': null,
        'gcode_file': null,
        'progress': 0,
        'remaining_time': 0,
        'layer_num': 0,
        'total_layers': 0,
        'temperatures': {
          'nozzle': _r1(23.8 + _wiggle(0.3, phase: 10)),
          'nozzle_target': 0.0,
          'bed': _r1(23.5 + _wiggle(0.2, phase: 45)),
          'bed_target': 0.0,
        },
        'cooling_fan_speed': 0,
        'big_fan1_speed': 0,
        'big_fan2_speed': 0,
        'heatbreak_fan_speed': 0,
        'speed_level': _speedLevel[2] ?? 2,
        'chamber_light': _chamberLight[2] ?? false,
        'wifi_signal': -61,
        'door_open': false,
        'ams_exists': true,
        'ams': [_amsUnit2()],
        'vt_tray': const <Object>[],
        'tray_now': 255,
        'active_extruder': 0,
        'hms_errors': const <Object>[],
        'firmware_version': '01.07.01.00',
        'cover_url': null,
        'supports_drying': false,
        'awaiting_plate_clear': false,
        'sdcard': true,
        'ipcam': true,
      };

  /// P2S wearing both accessory fan kits: `left_aux_fan_speed` is reported
  /// (airduct part 10 present) and `exhaust_fan_present` is true (part 3), so
  /// the card shows four fan tiles with the enclosure one labelled "Exhaust".
  /// A base P2S sends the same payload with `left_aux_fan_speed: null` and
  /// `exhaust_fan_present: false`, which hides both.
  Map<String, dynamic> _statusAccessoryFans() => {
        'name': 'P2S',
        'model': 'P2S',
        'connected': true,
        'state': 'IDLE',
        'current_print': null,
        'gcode_file': null,
        'progress': 0,
        'remaining_time': 0,
        'layer_num': 0,
        'total_layers': 0,
        'temperatures': {
          'nozzle': _r1(24.1 + _wiggle(0.3, phase: 20)),
          'nozzle_target': 0.0,
          'bed': _r1(23.9 + _wiggle(0.2, phase: 55)),
          'bed_target': 0.0,
          'chamber': _r1(25.4 + _wiggle(0.4, phase: 75)),
        },
        'cooling_fan_speed': _fanSpeeds['part'] ?? 0,
        'big_fan1_speed': _fanSpeeds['aux'] ?? 0,
        'left_aux_fan_speed': _fanSpeeds['aux2'] ?? 0,
        'big_fan2_speed': _fanSpeeds['chamber'] ?? 0,
        'exhaust_fan_present': true,
        'heatbreak_fan_speed': 0,
        'speed_level': _speedLevel[4] ?? 2,
        'chamber_light': _chamberLight[4] ?? false,
        'airduct_mode': _airductMode[4] ?? 0,
        'wifi_signal': -49,
        'door_open': false,
        'ams_exists': false,
        'ams': const <Object>[],
        'vt_tray': const <Object>[],
        'tray_now': 255,
        'active_extruder': 0,
        'hms_errors': const <Object>[],
        'firmware_version': '01.02.00.00',
        'cover_url': null,
        'supports_drying': false,
        'awaiting_plate_clear': false,
        'sdcard': true,
        'ipcam': true,
      };

  /// [tagUid] / [trayUuid] are what the AMS read off an RFID spool. Null on a
  /// third-party spool and on an empty slot, exactly as the server sends it —
  /// it nulls the firmware's empty and all-zero tags before they leave.
  Map<String, dynamic> _tray(
    int id,
    String? color,
    String? type, {
    String? subBrand,
    String? idName,
    String? infoIdx,
    int remain = -1,
    String? tagUid,
    String? trayUuid,
  }) =>
      {
        'id': id,
        'tray_color': color,
        'tray_type': type,
        'tray_sub_brands': subBrand ?? '',
        'tray_id_name': idName ?? '',
        'tray_info_idx': infoIdx ?? '',
        'remain': remain,
        'tag_uid': tagUid,
        'tray_uuid': trayUuid,
        'nozzle_temp_min': type == null ? null : '190',
        'nozzle_temp_max': type == null ? null : '240',
        'state': type == null ? 9 : 11,
      };

  // --- AMS slot configuration ---

  /// Long printer-preset name → short model code, as `/slicer/printer-models`
  /// serves it. The picker matches preset names against this.
  static const _printerModels = {
    'Bambu Lab X1 Carbon': 'X1C',
    'Bambu Lab X1': 'X1',
    'Bambu Lab P1S': 'P1S',
    'Bambu Lab P2S': 'P2S',
    'Bambu Lab A1 mini': 'A1M',
  };

  /// Bambu's built-in filament table. The ids match what the demo trays report,
  /// so a configured slot reopens on the preset it is actually set to.
  static const _builtinFilaments = [
    {'filament_id': 'GFA00', 'name': 'Bambu PLA Basic'},
    {'filament_id': 'GFA01', 'name': 'Bambu PLA Matte'},
    {'filament_id': 'GFA05', 'name': 'Bambu PLA Silk'},
    {'filament_id': 'GFG02', 'name': 'Bambu PETG HF'},
    {'filament_id': 'GFB00', 'name': 'Bambu ABS'},
    {'filament_id': 'GFU01', 'name': 'Bambu TPU 95A'},
    {'filament_id': 'GFL99', 'name': 'Generic PLA'},
    {'filament_id': 'GFG99', 'name': 'Generic PETG'},
    {'filament_id': 'GFB99', 'name': 'Generic ABS'},
  ];

  /// Presets imported from a slicer bundle. The P1S one is here to show the
  /// printer filter doing something on the X1C card, and the ASA one to show a
  /// preset that declares no compatibility staying visible anyway.
  static const _localPresets = [
    {
      'id': 1,
      'name': 'eSUN PLA+ @BBL X1C',
      'filament_type': 'PLA',
      'nozzle_temp_min': 205,
      'nozzle_temp_max': 225,
      'compatible_printers': '["Bambu Lab X1 Carbon 0.4 nozzle"]',
    },
    {
      'id': 2,
      'name': 'Devil Design PETG @BBL P1S',
      'filament_type': 'PETG',
      'nozzle_temp_min': 230,
      'nozzle_temp_max': 250,
      'compatible_printers': '["Bambu Lab P1S 0.4 nozzle"]',
    },
    {
      'id': 3,
      'name': 'Fiberlogy ASA @BBL X1C',
      'filament_type': 'ASA',
      'nozzle_temp_min': 250,
      'nozzle_temp_max': 270,
    },
  ];

  /// Calibrations the demo printer has stored. The 0.6 one is filtered out by
  /// every slot in this demo — it is here so the nozzle filter is visibly real
  /// rather than a parameter nothing depends on.
  static const _kProfiles = [
    {
      'slot_id': 1,
      'extruder_id': 0,
      'nozzle_id': 'HS00-0.4',
      'nozzle_diameter': '0.4',
      'filament_id': 'GFA00',
      'name': 'Bambu PLA Basic',
      'k_value': '0.020000',
      'setting_id': 'GFSA00_00',
    },
    {
      'slot_id': 2,
      'extruder_id': 0,
      'nozzle_id': 'HS00-0.4',
      'nozzle_diameter': '0.4',
      'filament_id': 'GFG02',
      'name': 'Bambu PETG HF',
      'k_value': '0.037000',
      'setting_id': 'GFSG02_00',
    },
    {
      'slot_id': 3,
      'extruder_id': 0,
      'nozzle_id': 'HS00-0.4',
      'nozzle_diameter': '0.4',
      'filament_id': 'GFA05',
      'name': 'Gold silk, slower',
      'k_value': '0.028000',
    },
    {
      'slot_id': 4,
      'extruder_id': 0,
      'nozzle_id': 'HS00-0.6',
      'nozzle_diameter': '0.6',
      'filament_id': 'GFA00',
      'name': 'PLA on the 0.6',
      'k_value': '0.022000',
    },
  ];

  Map<String, dynamic> _kProfilesResponse(String nozzleDiameter) => {
        'nozzle_diameter': nozzleDiameter,
        'profiles': [
          for (final p in _kProfiles)
            if (p['nozzle_diameter'] == nozzleDiameter) p,
        ],
      };

  String _slotKey(int printerId, int amsId, int trayId) =>
      '$printerId:$amsId:$trayId';

  /// `GET`/`PUT /printers/{id}/slot-presets/{ams}/{tray}`. An unmapped slot
  /// answers a bare `null`, which is what the real route does and what the
  /// picker reads as "nothing saved".
  DemoResult _slotPresetRoute(
    String m,
    int printerId,
    List<String> s,
    Map<String, String> q,
  ) {
    if (s.length < 5) return _ok(const <Object>[]);
    final amsId = int.tryParse(s[3]) ?? 0;
    final trayId = int.tryParse(s[4]) ?? 0;
    final key = _slotKey(printerId, amsId, trayId);
    if (m == 'PUT') {
      _slotPreset[key] = {
        'ams_id': amsId,
        'tray_id': trayId,
        'preset_id': q['preset_id'] ?? '',
        'preset_name': q['preset_name'] ?? '',
        'preset_source': q['preset_source'],
      };
      return _ok(const {'ok': true});
    }
    return _ok(_slotPreset[key]);
  }

  /// `POST /printers/{id}/slots/{ams}/{tray}/configure`. The real route derives
  /// nothing either — it hands the query straight to the printer — so the demo
  /// keeps the values verbatim and lets them show on the card.
  DemoResult _configureSlot(
    int printerId,
    int amsId,
    int trayId,
    Map<String, String> q,
  ) {
    _slotConfig[_slotKey(printerId, amsId, trayId)] = {
      'tray_color': q['tray_color'],
      'tray_type': q['tray_type'],
      'tray_sub_brands': q['tray_sub_brands'] ?? '',
      'tray_info_idx': q['tray_info_idx'] ?? '',
      'nozzle_temp_min': q['nozzle_temp_min'],
      'nozzle_temp_max': q['nozzle_temp_max'],
      'cali_idx': int.tryParse(q['cali_idx'] ?? ''),
      'state': 11,
    };
    return _ok(const {'success': true});
  }

  /// `POST /printers/{id}/ams/{ams}/tray/{tray}/reset` — empties the slot and
  /// drops its saved preset, the pair the real route undoes together.
  DemoResult _resetSlot(int printerId, int amsId, int trayId) {
    final key = _slotKey(printerId, amsId, trayId);
    _slotConfig[key] = const {
      'tray_color': null,
      'tray_type': null,
      'tray_sub_brands': '',
      'tray_info_idx': '',
      'cali_idx': null,
      'nozzle_temp_min': null,
      'nozzle_temp_max': null,
      'state': 9,
    };
    _slotPreset.remove(key);
    return _ok(const {'success': true});
  }

  Map<String, dynamic> _amsUnit1() => {
        'id': 0,
        'humidity': 21 + (_wiggle(1.5, periodSec: 600)).round(),
        'temp': _r1(28.5 + _wiggle(0.5, periodSec: 300)),
        'is_ams_ht': false,
        'module_type': 'n3f', // AMS 2 Pro — drying-capable
        'dry_time': _dryTime[0] ?? 0,
        'dry_status': (_dryTime[0] ?? 0) > 0 ? 2 : 0,
        'tray': [
          _tray(0, '000000FF', 'PLA',
              subBrand: 'PLA Basic', idName: 'A00-K0', infoIdx: 'GFA00', remain: 66),
          _tray(1, 'FF6A13FF', 'PLA',
              subBrand: 'PLA Basic', idName: 'A00-A0', infoIdx: 'GFA00', remain: 88),
          _tray(2, 'FFFFFFFF', 'PETG', infoIdx: 'GFG02', remain: 78),
          _tray(3, null, null),
        ],
      };

  Map<String, dynamic> _amsUnit2() => {
        'id': 0,
        'humidity': 34,
        'temp': _r1(24.0 + _wiggle(0.4, periodSec: 420)),
        'is_ams_ht': false,
        'module_type': 'ams',
        'dry_time': 0,
        'dry_status': 0,
        'tray': [
          _tray(0, '0ACCB8FF', 'PETG', infoIdx: 'GFG02', remain: 92),
          _tray(1, 'D4AF37FF', 'PLA',
              subBrand: 'PLA Silk', infoIdx: 'GFA05', remain: 10),
          // A genuine Bambu spool the shelf has never seen: tagged, full, and
          // deliberately absent from `_assignments`. That is the one state the
          // slot sheet offers "add to inventory" from.
          _tray(2, '00AE42FF', 'PLA',
              subBrand: 'PLA Basic',
              idName: 'A00-G1',
              infoIdx: 'GFA00',
              remain: 100,
              tagUid: 'B7A21C0439E5D168',
              trayUuid: '6F2C41D9A87B4E0359CD12FA8B76E430'),
          _tray(3, null, null),
        ],
      };

  // --- Printer files (on-device storage) ---

  Object _printerFiles(String path) {
    final files = switch (path) {
      '/' => [
          {'name': 'cache', 'path': '/cache', 'is_directory': true, 'size': 0},
          {
            'name': 'timelapse',
            'path': '/timelapse',
            'is_directory': true,
            'size': 0,
          },
          {
            'name': 'Drawer organizer x4.gcode.3mf',
            'path': '/Drawer organizer x4.gcode.3mf',
            'is_directory': false,
            'size': 4318208,
            'mtime': _iso(_daysAgo(0, hours: 2)),
          },
        ],
      '/cache' => [
          {
            'name': 'Benchy.gcode.3mf',
            'path': '/cache/Benchy.gcode.3mf',
            'is_directory': false,
            'size': 2108509,
            'mtime': _iso(_daysAgo(3)),
          },
          {
            'name': 'Cable clips x8.gcode.3mf',
            'path': '/cache/Cable clips x8.gcode.3mf',
            'is_directory': false,
            'size': 1524736,
            'mtime': _iso(_daysAgo(6)),
          },
        ],
      _ => const <Object>[],
    };
    return {'path': path, 'files': files};
  }

  // --- AMS history ---

  Map<String, dynamic> _amsHistory(int printerId, int amsId, int hours) {
    final now = DateTime.now();
    final points = <Map<String, dynamic>>[];
    final samples = math.min(hours * 12, 500); // every 5 min
    for (var i = samples; i >= 0; i--) {
      final t = now.subtract(Duration(minutes: i * 5));
      final phase = t.millisecondsSinceEpoch / 3600000 * 2 * math.pi / 6;
      points.add({
        'recorded_at': t.toUtc().toIso8601String(),
        'humidity': _r1(22 + 3 * math.sin(phase)),
        'temperature': _r1(27.5 + 2 * math.sin(phase / 2 + 1)),
      });
    }
    return {
      'printer_id': printerId,
      'ams_id': amsId,
      'data': points,
      'min_humidity': 19.0,
      'max_humidity': 25.0,
      'avg_humidity': 22.0,
      'min_temperature': 25.5,
      'max_temperature': 29.5,
      'avg_temperature': 27.5,
    };
  }

  // --- Heater history ---

  /// One series per requested sensor: the printer idles, then runs a print over
  /// the last two hours, so the chart shows a ramp, a hold and the setpoint.
  Map<String, dynamic> _heaterHistory(
    int printerId,
    int hours,
    List<String> kinds,
  ) {
    const idle = {'nozzle': 26.0, 'nozzle_2': 26.0, 'bed': 24.0, 'chamber': 28.0};
    const hot = {'nozzle': 220.0, 'nozzle_2': 218.0, 'bed': 60.0, 'chamber': 38.0};
    const printMinutes = 120;
    const rampMinutes = 10;

    final now = DateTime.now();
    final samples = math.min(hours * 60, 1000); // every minute, as the server
    final series = <Map<String, dynamic>>[];

    for (final kind in kinds) {
      final cold = idle[kind];
      if (cold == null) continue;
      final points = <Map<String, dynamic>>[];
      var min = double.infinity;
      var max = -double.infinity;
      var sum = 0.0;
      for (var i = samples; i >= 0; i--) {
        final printing = i < printMinutes;
        final ramp = printing
            ? math.min(1.0, (printMinutes - i) / rampMinutes)
            : 0.0;
        final noise = math.sin(i / 7) * (printing ? 1.2 : 0.3);
        final value = _r1(cold + (hot[kind]! - cold) * ramp + noise);
        points.add({
          'recorded_at': now.subtract(Duration(minutes: i)).toUtc().toIso8601String(),
          'value': value,
          'target': printing ? hot[kind] : 0.0,
        });
        min = math.min(min, value);
        max = math.max(max, value);
        sum += value;
      }
      series.add({
        'sensor_kind': kind,
        'data': points,
        'min_value': min,
        'max_value': max,
        'avg_value': _r1(sum / points.length),
      });
    }

    return {'printer_id': printerId, 'series': series};
  }

  // --- Queue ---

  late final List<Map<String, dynamic>> _queue = [
    _queueItem(
      id: 101,
      printerId: 1,
      position: 1,
      name: 'Cable clips x8',
      status: 'pending',
      timeSec: 5520,
      grams: 42.3,
      type: 'PETG',
      color: '#FFFFFF',
      createdDaysAgo: 1,
    ),
    _queueItem(
      id: 102,
      printerId: null,
      position: 2,
      name: 'Phone stand',
      status: 'pending',
      timeSec: 8340,
      grams: 68.9,
      type: 'PLA',
      color: '#FF6A13',
      createdDaysAgo: 0,
    ),
    // Plate-swap job on the one model demo has snippets for: opening it shows
    // the injection checkbox already ticked, with no "nothing will be injected"
    // note. Move it to the X1C or the P1S and the note appears.
    _queueItem(
      id: 103,
      printerId: 3,
      position: 3,
      name: 'Keychain batch (plate swap)',
      status: 'pending',
      timeSec: 2760,
      grams: 12.4,
      type: 'PLA',
      color: '#1F8F4D',
      createdDaysAgo: 0,
      gcodeInjection: true,
      slicedForModel: 'A1 mini',
    ),
  ];

  /// Demo filaments "loaded on other printers of the model" — options for the
  /// Edit Queue Item filament-override dropdowns. Static set covering the common
  /// materials so the override UI is exercisable offline.
  List<Map<String, dynamic>> _availableFilaments() => const [
        {'type': 'PLA', 'color': '#FFFFFF', 'tray_info_idx': 'GFA00', 'tray_sub_brands': 'Bambu PLA Basic', 'extruder_id': null},
        {'type': 'PLA', 'color': '#1F8F4D', 'tray_info_idx': 'GFA01', 'tray_sub_brands': 'Bambu PLA Matte', 'extruder_id': null},
        {'type': 'PETG', 'color': '#F55A74', 'tray_info_idx': 'GFG00', 'tray_sub_brands': 'Bambu PETG HF', 'extruder_id': null},
        {'type': 'TPU 95A', 'color': '#34C46E', 'tray_info_idx': 'GFU00', 'tray_sub_brands': 'Bambu TPU 95A', 'extruder_id': null},
      ];

  Map<String, dynamic> _queueItem({
    required int id,
    required int? printerId,
    required int position,
    required String name,
    required String status,
    required int timeSec,
    required double grams,
    required String type,
    required String color,
    required int createdDaysAgo,
    bool gcodeInjection = false,
    String slicedForModel = 'X1C',
  }) =>
      {
        'id': id,
        'printer_id': printerId,
        'archive_id': null,
        'library_file_id': null,
        'position': position,
        'status': status,
        'required_filament_types': [type],
        'ams_mapping': const <Object>[],
        'use_ams': true,
        'manual_start': false,
        'auto_off_after': false,
        'require_previous_success': false,
        'gcode_injection': gcodeInjection,
        'filament_short': false,
        // Tri-state strings, as bambuddy 1.2.5+ sends them — the shape whose
        // arrival emptied the real queue screen (docs/plans/07). Demo mode is
        // where that regression should surface first, so it speaks the current
        // contract and includes an `auto` rather than only the two easy values.
        'bed_levelling': 'auto',
        'flow_cali': 'off',
        'nozzle_offset_cali': 'auto',
        'vibration_cali': true,
        'layer_inspect': true,
        'timelapse': false,
        'created_at': _iso(_daysAgo(createdDaysAgo)),
        'archive_name': name,
        'archive_thumbnail': null,
        'archive_deleted': false,
        'printer_name': printerId == null
            ? null
            : _printers.firstWhere((p) => p['id'] == printerId)['name'],
        'print_time_seconds': timeSec,
        'filament_used_grams': grams,
        'filament_type': type,
        'filament_color': color,
        'layer_height': 0.2,
        'nozzle_diameter': 0.4,
        'sliced_for_model': slicedForModel,
      };

  DemoResult? _queueRoute(String m, List<String> s, Map<String, dynamic> body) {
    if (s.length == 1) {
      if (m == 'GET') return _ok(_queue);
      if (m == 'POST') {
        // Add from archive ("reprint").
        final archive = _archives
            .where((a) => a['id'] == body['archive_id'])
            .firstOrNull;
        _queue.add(_queueItem(
          id: _nextQueueId++,
          printerId: body['printer_id'] as int?,
          position: _queue.length + 1,
          name: (archive?['print_name'] as String?) ?? 'Reprint',
          status: 'pending',
          timeSec: (archive?['print_time_seconds'] as int?) ?? 3600,
          grams: (archive?['filament_used_grams'] as num?)?.toDouble() ?? 20,
          type: (archive?['filament_type'] as String?) ?? 'PLA',
          color: (archive?['filament_color'] as String?) ?? '#808080',
          createdDaysAgo: 0,
          gcodeInjection: body['gcode_injection'] == true,
        ));
        return _ok(_queue.last);
      }
    }
    if (s.length >= 2 && s[1] == 'reorder') {
      final items = body['items'];
      if (items is List) {
        for (final it in items.whereType<Map>()) {
          final match =
              _queue.where((e) => e['id'] == it['id']).firstOrNull;
          if (match != null) match['position'] = it['position'];
        }
        _queue.sort((a, b) =>
            (a['position'] as int).compareTo(b['position'] as int));
      }
      return _ok(const {'ok': true});
    }
    final itemId = int.tryParse(s[1]);
    if (itemId == null) return _notFound();
    final item = _queue.where((e) => e['id'] == itemId).firstOrNull;
    if (item == null) return _notFound();
    if (m == 'DELETE') {
      _queue.remove(item);
      return _ok(const {'ok': true});
    }
    if (m == 'PATCH') {
      if (body.containsKey('printer_id')) {
        item['printer_id'] = body['printer_id'];
        item['printer_name'] = _printers
            .where((p) => p['id'] == body['printer_id'])
            .firstOrNull?['name'];
      }
      if (body.containsKey('ams_mapping')) {
        item['ams_mapping'] = body['ams_mapping'];
      }
      if (body.containsKey('gcode_injection')) {
        item['gcode_injection'] = body['gcode_injection'];
      }
      return _ok(item);
    }
    if (s.length >= 3 && s[2] == 'cancel') {
      item['status'] = 'cancelled';
      return _ok(const {'ok': true});
    }
    if (s.length >= 3 && s[2] == 'start') {
      item['status'] = 'printing';
      item['started_at'] = _iso(DateTime.now());
      return _ok(const {'ok': true});
    }
    return _fallback(m);
  }

  int _nextQueueId = 200;

  // --- Archives + stats ---

  late final List<Map<String, dynamic>> _archives = _buildArchives();

  List<Map<String, dynamic>> _buildArchives() {
    var id = 40;
    Map<String, dynamic> a(
      String name,
      int printerId,
      int daysAgo, {
      required int estSec,
      required double grams,
      String type = 'PLA',
      String color = '#000000',
      String status = 'completed',
      String? failureReason,
      double? cost,
      double? energyKwh,
      int quantity = 1,
    }) {
      final started = _daysAgo(daysAgo, hours: 3);
      final actualSec = status == 'completed'
          ? (estSec * 1.06).round()
          : (estSec * 0.4).round();
      return {
        'id': id++,
        'printer_id': printerId,
        'project_id': null,
        'project_name': null,
        'filename': '$name.gcode.3mf',
        'file_path': 'archive/demo/$name.gcode.3mf',
        'file_size': 1500000 + name.length * 37000,
        'thumbnail_path': null,
        'timelapse_path': null,
        'duplicate_count': 0,
        'duplicate_sequence': 0,
        'object_count': quantity,
        'print_name': name,
        'print_time_seconds': estSec,
        'actual_time_seconds': actualSec,
        'time_accuracy':
            status == 'completed' ? _r1(estSec / actualSec * 100) : null,
        'filament_used_grams': grams,
        'filament_type': type,
        'filament_color': color,
        'layer_height': 0.2,
        'total_layers': (estSec / 40).round(),
        'nozzle_diameter': 0.4,
        'bed_type': 'Textured PEI Plate',
        'nozzle_temperature': type == 'PETG' ? 240 : 220,
        'sliced_for_model': printerId == 2 ? 'P1S' : 'X1C',
        'status': status,
        'started_at': _iso(started),
        'completed_at': _iso(started.add(Duration(seconds: actualSec))),
        'extra_data': const <String, dynamic>{},
        'is_favorite': false,
        'tags': null,
        'notes': null,
        'cost': cost ?? _r1(grams * 0.025),
        'photos': const <Object>[],
        'failure_reason': failureReason,
        'quantity': quantity,
        'energy_kwh': energyKwh ?? _r1(estSec / 3600 * 0.11),
        'energy_cost': _r1((energyKwh ?? estSec / 3600 * 0.11) * 0.3),
        'created_at': _iso(started),
        'run_count': 1,
        'last_run_at': _iso(started),
        'total_filament_actual_grams': grams,
        'successful_run_count': status == 'completed' ? 1 : 0,
        'failed_run_count': status == 'failed' ? 1 : 0,
      };
    }

    return [
      a('Drawer organizer x4', 1, 1, estSec: 5400, grams: 96.2, color: '#000000'),
      a('Benchy', 1, 2, estSec: 3540, grams: 15.8, color: '#FF6A13'),
      a('Raspberry Pi 5 case', 2, 3,
          estSec: 7920, grams: 48.4, type: 'PETG', color: '#FFFFFF'),
      a('Headphone hook', 1, 4, estSec: 4260, grams: 31.7, color: '#3B3B3B'),
      a('Spiral vase', 2, 6,
          estSec: 10680, grams: 88.1, color: '#D4AF37',
          status: 'failed', failureReason: 'Spaghetti detected'),
      a('Cable clips x8', 1, 7,
          estSec: 5520, grams: 42.3, type: 'PETG', color: '#FFFFFF', quantity: 8),
      a('Plant pot 120mm', 2, 9, estSec: 12480, grams: 132.5, color: '#0ACCB8'),
      a('SD card holder', 1, 12, estSec: 3120, grams: 22.9, color: '#FF6A13'),
      a('Phone stand', 3, 15, estSec: 8340, grams: 68.9, color: '#FF6A13'),
      a('Wall hook x4', 1, 18,
          estSec: 4980, grams: 38.2, type: 'PETG', color: '#FFFFFF',
          status: 'failed', failureReason: 'Bed adhesion'),
      a('Desk drawer divider', 2, 22, estSec: 9840, grams: 104.6, color: '#000000'),
      a('Flexi dragon', 1, 26,
          estSec: 14400, grams: 156.3, type: 'TPU', color: '#0ACC38'),
    ];
  }

  DemoResult? _archivesRoute(String m, List<String> s, Map<String, String> q) {
    if (s.length == 1 && m == 'GET') return _ok(_pageArchives(q));
    if (s.length >= 2) {
      switch (s[1]) {
        case 'search':
          final query = (q['q'] ?? '').toLowerCase();
          return _ok(_archives
              .where((a) =>
                  ('${a['print_name']}'.toLowerCase()).contains(query) ||
                  ('${a['filename']}'.toLowerCase()).contains(query))
              .toList());
        case 'stats':
          return _ok(_archiveStats());
        case 'slim':
          return _ok([
            for (final a in _pageArchives(q))
              {
                'status': a['status'],
                'created_at': a['created_at'],
                'printer_id': a['printer_id'],
                'print_name': a['print_name'],
                'print_time_seconds': a['print_time_seconds'],
                'actual_time_seconds': a['actual_time_seconds'],
                'filament_used_grams': a['filament_used_grams'],
                'filament_type': a['filament_type'],
                'filament_color': a['filament_color'],
                'started_at': a['started_at'],
                'completed_at': a['completed_at'],
                'cost': a['cost'],
                'quantity': a['quantity'],
              }
          ]);
        case 'analysis':
          return _ok(_failureAnalysis(q));
        case 'purge':
          if (s.length >= 3 && s[2] == 'preview') {
            final days = int.tryParse(q['older_than_days'] ?? '') ?? 0;
            final old = _archivesOlderThan(days);
            return _ok({
              'count': old.length,
              'total_bytes':
                  old.fold<int>(0, (sum, a) => sum + (a['file_size'] as int)),
              'sample_filenames': [
                for (final a in old.take(3)) a['filename'],
              ],
              'older_than_days': days,
            });
          }
          if (m == 'POST') return _ok(const {'deleted': 0});
      }
      final aid = int.tryParse(s[1]);
      if (aid != null) {
        final archive = _archives.where((a) => a['id'] == aid).firstOrNull;
        if (archive == null) return _notFound();
        if (m == 'DELETE') {
          _archives.remove(archive);
          return _ok(const {'ok': true});
        }
        if (s.length >= 3 && s[2] == 'capabilities') {
          return _ok(const {
            'has_model': false,
            'has_gcode': true,
            'has_source': false,
          });
        }
        if (s.length >= 3 && s[2] == 'filament-requirements') {
          return _ok(const {'filaments': <Object>[]});
        }
        if (s.length == 2 && m == 'GET') return _ok(archive);
      }
    }
    return _fallback(m);
  }

  List<Map<String, dynamic>> _pageArchives(Map<String, String> q) {
    final offset = int.tryParse(q['offset'] ?? '') ?? 0;
    final limit = int.tryParse(q['limit'] ?? '') ?? 50;
    var list = _archives;
    final printerId = int.tryParse(q['printer_id'] ?? '');
    if (printerId != null) {
      list = list.where((a) => a['printer_id'] == printerId).toList();
    }
    if (offset >= list.length) return const [];
    return list.sublist(offset, math.min(offset + limit, list.length));
  }

  List<Map<String, dynamic>> _archivesOlderThan(int days) {
    final cutoff = _daysAgo(days);
    return _archives
        .where((a) =>
            DateTime.parse(a['created_at'] as String).isBefore(cutoff))
        .toList();
  }

  Map<String, dynamic> _archiveStats() {
    final completed =
        _archives.where((a) => a['status'] == 'completed').length;
    final failed = _archives.where((a) => a['status'] == 'failed').length;
    final byType = <String, int>{};
    final byPrinter = <String, int>{};
    var hours = 0.0, grams = 0.0, cost = 0.0, kwh = 0.0;
    for (final a in _archives) {
      byType.update('${a['filament_type']}', (v) => v + 1, ifAbsent: () => 1);
      final printerName = _printers
              .where((p) => p['id'] == a['printer_id'])
              .firstOrNull?['name'] ??
          '?';
      byPrinter.update('$printerName', (v) => v + 1, ifAbsent: () => 1);
      hours += (a['actual_time_seconds'] as int) / 3600;
      grams += a['filament_used_grams'] as double;
      cost += a['cost'] as double;
      kwh += a['energy_kwh'] as double;
    }
    return {
      'total_prints': _archives.length,
      'successful_prints': completed,
      'failed_prints': failed,
      'cancelled_prints': 0,
      'total_print_time_hours': _r1(hours),
      'total_filament_grams': _r1(grams),
      'total_cost': _r1(cost),
      'prints_by_filament_type': byType,
      'prints_by_printer': byPrinter,
      'average_time_accuracy': 94.4,
      'total_energy_kwh': _r1(kwh),
      'total_energy_cost': _r1(kwh * 0.3),
      'energy_data_warming_up': false,
    };
  }

  Map<String, dynamic> _failureAnalysis(Map<String, String> q) {
    final failed = _archives.where((a) => a['status'] == 'failed');
    final byReason = <String, int>{};
    final byFilament = <String, int>{};
    final byPrinter = <String, int>{};
    for (final a in failed) {
      byReason.update('${a['failure_reason'] ?? 'Unknown'}', (v) => v + 1,
          ifAbsent: () => 1);
      byFilament.update('${a['filament_type']}', (v) => v + 1,
          ifAbsent: () => 1);
      byPrinter.update(
          '${_printers.where((p) => p['id'] == a['printer_id']).firstOrNull?['name'] ?? '?'}',
          (v) => v + 1,
          ifAbsent: () => 1);
    }
    return {
      'period_days': int.tryParse(q['days'] ?? '') ?? 30,
      'total_prints': _archives.length,
      'failed_prints': failed.length,
      'failure_rate':
          _archives.isEmpty ? 0 : _r1(failed.length * 100 / _archives.length),
      'failures_by_reason': byReason,
      'failures_by_filament': byFilament,
      'failures_by_printer': byPrinter,
      'failures_by_hour': const {'14': 1, '19': 1},
    };
  }

  // --- Smart plugs ---

  DemoResult? _plugsRoute(String m, List<String> s, Map<String, dynamic> body) {
    if (s.length == 1 && m == 'GET') {
      return _ok([
        _plug(1, 'Workshop plug', 'tasmota', 1),
        _plug(2, 'Office plug', 'homeassistant', 2),
      ]);
    }
    final plugId = int.tryParse(s.length > 1 ? s[1] : '');
    if (plugId == null || !_plugOn.containsKey(plugId)) return _notFound();
    if (s.length >= 3 && s[2] == 'status') {
      final on = _plugOn[plugId]!;
      final printing = plugId == 1 && !_stopped && !_paused;
      return _ok({
        'state': on ? 'ON' : 'OFF',
        'reachable': true,
        'device_name': plugId == 1 ? 'Workshop plug' : 'Office plug',
        'energy': {
          'power': !on ? 0.0 : (printing ? _r1(96 + _wiggle(9)) : 8.2),
          'voltage': _r1(231 + _wiggle(1.2)),
          'current': !on ? 0.0 : 0.42,
          'today': plugId == 1 ? 0.84 : 0.05,
          'yesterday': plugId == 1 ? 1.62 : 0.11,
          'total': plugId == 1 ? 143.2 : 38.6,
        },
      });
    }
    if (s.length >= 3 && s[2] == 'control' && m == 'POST') {
      final action = body['action'];
      _plugOn[plugId] = switch (action) {
        'on' => true,
        'off' => false,
        _ => !_plugOn[plugId]!,
      };
      return _ok(const {'ok': true});
    }
    if (s.length == 2 && m == 'GET') {
      return _ok(_plug(plugId, plugId == 1 ? 'Workshop plug' : 'Office plug',
          plugId == 1 ? 'tasmota' : 'homeassistant', plugId));
    }
    return _fallback(m);
  }

  Map<String, dynamic> _plug(int id, String name, String type, int printerId) => {
        'id': id,
        'name': name,
        'plug_type': type,
        'printer_id': printerId,
        'enabled': true,
        'last_state': _plugOn[id]! ? 'ON' : 'OFF',
        'show_on_printer_card': true,
        'show_in_switchbar': true,
      };

  // --- Maintenance ---

  static final List<Map<String, dynamic>> _maintenanceTypes = [
    {
      'id': 1,
      'name': 'Lubricate Carbon Rods',
      'description': 'Wipe and lubricate the X/Y carbon rods.',
      'default_interval_hours': 250.0,
      'interval_type': 'hours',
      'icon': 'Droplet',
      'wiki_url': null,
      'is_system': true,
    },
    {
      'id': 2,
      'name': 'Clean Nozzle/Hotend',
      'description': 'Remove filament residue from the nozzle and hotend.',
      'default_interval_hours': 100.0,
      'interval_type': 'hours',
      'icon': 'Flame',
      'wiki_url': null,
      'is_system': true,
    },
    {
      'id': 3,
      'name': 'Grease Lead Screws',
      'description': 'Apply grease to the Z lead screws.',
      'default_interval_hours': 500.0,
      'interval_type': 'hours',
      'icon': 'Wrench',
      'wiki_url': null,
      'is_system': true,
    },
    {
      'id': 4,
      'name': 'Deep Clean & Inspect',
      'description': 'Full cleaning pass and visual inspection.',
      'default_interval_hours': 720.0,
      'interval_type': 'hours',
      'icon': 'Search',
      'wiki_url': null,
      'is_system': true,
    },
  ];

  /// itemId → {printer_id, type_id, hours_since, enabled, last_performed_at}.
  late final Map<int, Map<String, dynamic>> _maintenanceItems = {
    10: {'printer_id': 1, 'type_id': 1, 'hours_since': 236.0, 'enabled': true},
    11: {'printer_id': 1, 'type_id': 2, 'hours_since': 112.0, 'enabled': true},
    12: {'printer_id': 1, 'type_id': 3, 'hours_since': 310.0, 'enabled': true},
    20: {'printer_id': 2, 'type_id': 1, 'hours_since': 41.0, 'enabled': true},
    21: {'printer_id': 2, 'type_id': 2, 'hours_since': 63.0, 'enabled': true},
    30: {'printer_id': 3, 'type_id': 2, 'hours_since': 12.0, 'enabled': true},
  };

  static const Map<int, double> _printerHours = {1: 412.5, 2: 96.3, 3: 44.1};

  Map<String, dynamic> _maintenanceStatus(int itemId) {
    final item = _maintenanceItems[itemId]!;
    final type = _maintenanceTypes
        .firstWhere((t) => t['id'] == item['type_id']);
    final printer =
        _printers.firstWhere((p) => p['id'] == item['printer_id']);
    final interval =
        (item['custom_interval_hours'] as double?) ??
            type['default_interval_hours'] as double;
    final since = item['hours_since'] as double;
    final until = interval - since;
    return {
      'id': itemId,
      'printer_id': printer['id'],
      'printer_name': printer['name'],
      'printer_model': printer['model'],
      'maintenance_type_id': type['id'],
      'maintenance_type_name': type['name'],
      'maintenance_type_icon': type['icon'],
      'maintenance_type_wiki_url': type['wiki_url'],
      'enabled': item['enabled'],
      'interval_hours': interval,
      'interval_type': 'hours',
      'current_hours': _printerHours[printer['id']],
      'hours_since_maintenance': _r1(since),
      'hours_until_due': _r1(until),
      'days_since_maintenance': null,
      'days_until_due': null,
      'is_due': until <= 0,
      'is_warning': until > 0 && until <= interval * 0.1,
      'last_performed_at': item['last_performed_at'],
    };
  }

  Map<String, dynamic> _maintenanceOverviewFor(int printerId) {
    final printer = _printers.firstWhere((p) => p['id'] == printerId);
    final items = [
      for (final id in _maintenanceItems.keys)
        if (_maintenanceItems[id]!['printer_id'] == printerId)
          _maintenanceStatus(id),
    ];
    return {
      'printer_id': printerId,
      'printer_name': printer['name'],
      'printer_model': printer['model'],
      'total_print_hours': _printerHours[printerId],
      'due_count': items.where((i) => i['is_due'] == true).length,
      'warning_count': items.where((i) => i['is_warning'] == true).length,
      'maintenance_items': items,
    };
  }

  DemoResult? _maintenanceRoute(
      String m, List<String> s, Map<String, dynamic> body) {
    if (s.length >= 2 && s[1] == 'overview') {
      return _ok([for (final p in _printers) _maintenanceOverviewFor(p['id'] as int)]);
    }
    if (s.length >= 3 && s[1] == 'printers') {
      final pid = int.tryParse(s[2]);
      if (pid == null) return _notFound();
      if (s.length >= 5 && s[3] == 'assign') {
        final typeId = int.tryParse(s[4]);
        if (typeId != null) {
          final newId = _maintenanceItems.keys
                  .fold<int>(0, (a, b) => math.max(a, b)) +
              1;
          _maintenanceItems[newId] = {
            'printer_id': pid,
            'type_id': typeId,
            'hours_since': 0.0,
            'enabled': true,
            'last_performed_at': _iso(DateTime.now()),
          };
        }
        return _ok(const {'ok': true});
      }
      return _ok(_maintenanceOverviewFor(pid));
    }
    if (s.length >= 2 && s[1] == 'types') {
      if (s.length == 2 && m == 'GET') return _ok(_maintenanceTypes);
      if (s.length == 2 && m == 'POST') {
        final newId =
            _maintenanceTypes.fold<int>(0, (a, t) => math.max(a, t['id'] as int)) + 1;
        final type = {
          'id': newId,
          'name': body['name'] ?? 'Custom task',
          'description': body['description'],
          'default_interval_hours':
              (body['default_interval_hours'] as num?)?.toDouble() ?? 100.0,
          'interval_type': body['interval_type'] ?? 'hours',
          'icon': body['icon'],
          'wiki_url': body['wiki_url'],
          'is_system': false,
        };
        _maintenanceTypes.add(type);
        return _ok(type);
      }
      final typeId = int.tryParse(s[2]);
      final type =
          _maintenanceTypes.where((t) => t['id'] == typeId).firstOrNull;
      if (type != null && m == 'PATCH') {
        for (final k in ['name', 'description', 'icon', 'wiki_url']) {
          if (body.containsKey(k)) type[k] = body[k];
        }
        if (body['default_interval_hours'] is num) {
          type['default_interval_hours'] =
              (body['default_interval_hours'] as num).toDouble();
        }
        return _ok(type);
      }
      if (type != null && m == 'DELETE') {
        if (type['is_system'] != true) _maintenanceTypes.remove(type);
        return _ok(const {'ok': true});
      }
      return _fallback(m);
    }
    if (s.length >= 3 && s[1] == 'items') {
      final itemId = int.tryParse(s[2]);
      final item = itemId == null ? null : _maintenanceItems[itemId];
      if (item == null) return _notFound();
      if (s.length >= 4 && s[3] == 'perform') {
        item['hours_since'] = 0.0;
        item['last_performed_at'] = _iso(DateTime.now());
        return _ok(_maintenanceStatus(itemId!));
      }
      if (s.length >= 4 && s[3] == 'history') {
        final last = item['last_performed_at'];
        return _ok([
          if (last != null)
            {
              'id': 1,
              'printer_maintenance_id': itemId,
              'performed_at': last,
              'notes': null,
              'hours_at_maintenance': _printerHours[item['printer_id']],
            },
        ]);
      }
      if (m == 'PATCH') {
        if (body.containsKey('enabled')) item['enabled'] = body['enabled'];
        if (body.containsKey('custom_interval_hours')) {
          final v = body['custom_interval_hours'];
          item['custom_interval_hours'] = (v as num?)?.toDouble();
        }
        return _ok(_maintenanceStatus(itemId!));
      }
      if (m == 'DELETE') {
        _maintenanceItems.remove(itemId);
        return _ok(const {'ok': true});
      }
    }
    return _fallback(m);
  }

  // --- Inventory (native) ---

  late final List<Map<String, dynamic>> _spools = _buildSpools();
  int _nextSpoolId = 100;

  List<Map<String, dynamic>> _buildSpools() {
    var id = 1;
    Map<String, dynamic> spool(
      String material,
      String? subtype,
      String colorName,
      String rgba, {
      String brand = 'Bambu Lab',
      int label = 1000,
      double used = 0,
      double cost = 25.99,
      String? location,
      String? effect,
      String? archivedAt,
      int? lowStockPct,
      double baseline = 0,
    }) =>
        {
          'id': id++,
          'material': material,
          'subtype': subtype,
          'color_name': colorName,
          'rgba': rgba,
          'extra_colors': null,
          'effect_type': effect,
          'brand': brand,
          'label_weight': label,
          'core_weight': 250,
          'weight_used': used,
          'weight_used_baseline': baseline,
          'cost_per_kg': cost,
          'low_stock_threshold_pct': lowStockPct,
          'storage_location': location,
          'category': null,
          'note': null,
          'nozzle_temp_min': material == 'PETG' ? 230 : 190,
          'nozzle_temp_max': material == 'PETG' ? 260 : 230,
          'tag_uid': null,
          'archived_at': archivedAt,
          'last_used': _iso(_daysAgo(id % 6)),
          'created_at': _iso(_daysAgo(30 + id)),
          'k_profiles': const <Object>[],
        };

    return [
      spool('PLA', 'Basic', 'Black', '000000FF', used: 340, location: 'Shelf A'),
      spool('PLA', 'Basic', 'Orange', 'FF6A13FF', used: 120, location: 'Shelf A'),
      spool('PLA', 'Matte', 'Charcoal', '3B3B3BFF', used: 610, location: 'Shelf B'),
      spool('PETG', 'HF', 'White', 'FFFFFFFF', used: 220, cost: 29.99, location: 'Dry box'),
      spool('PETG', 'Translucent', 'Teal', '0ACCB8FF', used: 80, cost: 29.99, location: 'Dry box'),
      spool('TPU', '95A', 'Green', '0ACC38FF',
          used: 445, cost: 34.99, location: 'Shelf B', lowStockPct: 20),
      // The one spool whose counter has been reset before: consumed (405 g)
      // reads lower than used (905 g), which is the split the reset action
      // makes and the only way to see it without pressing the button.
      spool('PLA', 'Silk', 'Gold', 'D4AF37FF',
          used: 905, baseline: 500, effect: 'silk', location: 'Shelf A'),
      spool('ABS', null, 'Red', 'C12E1FFF',
          used: 380, archivedAt: _iso(_daysAgo(10))),
    ];
  }

  late final List<Map<String, dynamic>> _assignments = [
    {'spool_id': 1, 'printer_id': 1, 'ams_id': 0, 'tray_id': 0, 'printer_name': 'X1 Carbon'},
    {'spool_id': 2, 'printer_id': 1, 'ams_id': 0, 'tray_id': 1, 'printer_name': 'X1 Carbon'},
    {'spool_id': 4, 'printer_id': 1, 'ams_id': 0, 'tray_id': 2, 'printer_name': 'X1 Carbon'},
    {'spool_id': 5, 'printer_id': 2, 'ams_id': 0, 'tray_id': 0, 'printer_name': 'P1S'},
    {'spool_id': 7, 'printer_id': 2, 'ams_id': 0, 'tray_id': 1, 'printer_name': 'P1S'},
  ];

  static final List<Map<String, dynamic>> _coreWeights = [
    {'id': 1, 'name': 'Bambu Lab – Plastic', 'weight': 250, 'is_default': true},
    {'id': 2, 'name': 'Generic – Plastic', 'weight': 200, 'is_default': false},
    {'id': 3, 'name': 'Cardboard', 'weight': 140, 'is_default': false},
  ];

  static final List<Map<String, dynamic>> _colorCatalog = [
    {'id': 1, 'manufacturer': 'Bambu Lab', 'color_name': 'Black', 'hex_color': '#000000', 'material': 'PLA', 'is_default': true},
    {'id': 2, 'manufacturer': 'Bambu Lab', 'color_name': 'Jade White', 'hex_color': '#FFFFFF', 'material': 'PLA', 'is_default': true},
    {'id': 3, 'manufacturer': 'Bambu Lab', 'color_name': 'Orange', 'hex_color': '#FF6A13', 'material': 'PLA', 'is_default': true},
    {'id': 4, 'manufacturer': 'Bambu Lab', 'color_name': 'Bambu Green', 'hex_color': '#00AE42', 'material': 'PLA', 'is_default': true},
    {'id': 5, 'manufacturer': 'Bambu Lab', 'color_name': 'Red', 'hex_color': '#C12E1F', 'material': 'PLA', 'is_default': true},
    {'id': 6, 'manufacturer': 'Bambu Lab', 'color_name': 'Blue Grey', 'hex_color': '#5B6579', 'material': 'PETG', 'is_default': true},
    {'id': 7, 'manufacturer': 'Bambu Lab', 'color_name': 'Gold', 'hex_color': '#D4AF37', 'material': 'PLA', 'is_default': true, 'effect_type': 'silk'},
  ];

  static final List<Map<String, dynamic>> _filamentPresets = [
    {'id': 1, 'name': 'Bambu PLA Basic', 'type': 'PLA', 'brand': 'Bambu Lab', 'color_hex': '#000000', 'cost_per_kg': 25.99, 'spool_weight_g': 1000.0, 'print_temp_min': 190, 'print_temp_max': 230},
    {'id': 2, 'name': 'Bambu PLA Matte', 'type': 'PLA', 'brand': 'Bambu Lab', 'color_hex': '#3B3B3B', 'cost_per_kg': 26.99, 'spool_weight_g': 1000.0, 'print_temp_min': 190, 'print_temp_max': 230},
    {'id': 3, 'name': 'Bambu PETG HF', 'type': 'PETG', 'brand': 'Bambu Lab', 'color_hex': '#FFFFFF', 'cost_per_kg': 29.99, 'spool_weight_g': 1000.0, 'print_temp_min': 230, 'print_temp_max': 260},
    {'id': 4, 'name': 'Bambu TPU 95A', 'type': 'TPU', 'brand': 'Bambu Lab', 'color_hex': '#0ACC38', 'cost_per_kg': 34.99, 'spool_weight_g': 1000.0, 'print_temp_min': 200, 'print_temp_max': 250},
  ];

  DemoResult? _inventoryRoute(
    String m,
    List<String> s,
    Map<String, String> q,
    Map<String, dynamic> body,
  ) {
    if (s.length < 2) return _notFound();
    switch (s[1]) {
      case 'spools':
        if (s.length == 2) {
          if (m == 'GET') {
            final includeArchived = q['include_archived'] == 'true';
            return _ok(includeArchived
                ? _spools
                : _spools.where((x) => x['archived_at'] == null).toList());
          }
          if (m == 'POST') return _ok(_createSpool(body));
        }
        if (s.length >= 3 && s[2] == 'from-slot' && m == 'POST') {
          return _createSpoolFromSlot(body);
        }
        if (s.length >= 3 && s[2] == 'bulk' && m == 'POST') {
          final quantity = (body['quantity'] as num?)?.toInt() ?? 1;
          final draft = body['spool'];
          return _ok([
            for (var i = 0; i < quantity; i++)
              _createSpool(draft is Map<String, dynamic> ? draft : const {}),
          ]);
        }
        // Before the id lookup below: `bulk-archive` and friends are siblings
        // of `{spool_id}` in the path, and would otherwise be read as an id.
        if (s.length == 3 && m == 'POST') {
          final bulk = _bulkSpools(s[2], body);
          if (bulk != null) return bulk;
        }
        final spoolId = int.tryParse(s.length > 2 ? s[2] : '');
        final spool = _spools.where((x) => x['id'] == spoolId).firstOrNull;
        if (spool == null) return _notFound();
        if (s.length == 3) {
          if (m == 'GET') return _ok(spool);
          if (m == 'PATCH') {
            body.forEach((k, v) => spool[k] = v);
            return _ok(spool);
          }
          if (m == 'DELETE') {
            _spools.remove(spool);
            _assignments.removeWhere((a) => a['spool_id'] == spoolId);
            return _ok(const {'ok': true});
          }
        }
        if (s.length >= 4) {
          switch (s[3]) {
            case 'archive':
              spool['archived_at'] = _iso(DateTime.now());
              return _ok(spool);
            case 'restore':
              spool['archived_at'] = null;
              return _ok(spool);
            // Stamps the baseline the "Total Consumed" display counts from,
            // and leaves `weight_used` — so remaining does NOT jump back to
            // the label weight. That is what the route does since it was
            // renamed from `/reset-usage`, which zeroed the weight instead
            // (server issue #1644); the old name is gone there, so it is gone
            // here too and the app's fallback to it stays honest.
            case 'reset-consumed-counter':
              spool['weight_used_baseline'] = spool['weight_used'] ?? 0.0;
              return _ok(spool);
            case 'usage':
              return _ok(_spoolUsage(spoolId!));
            case 'k-profiles':
              return _ok(const <Object>[]);
          }
        }
        return _fallback(m);

      case 'assignments':
        if (s.length == 2) {
          if (m == 'GET') return _ok(_assignments);
          if (m == 'POST') {
            _assignments.removeWhere((a) =>
                a['printer_id'] == body['printer_id'] &&
                a['ams_id'] == body['ams_id'] &&
                a['tray_id'] == body['tray_id']);
            _assignments.add({
              'spool_id': body['spool_id'],
              'printer_id': body['printer_id'],
              'ams_id': body['ams_id'],
              'tray_id': body['tray_id'],
              'printer_name': _printers
                  .where((p) => p['id'] == body['printer_id'])
                  .firstOrNull?['name'],
            });
            return _ok(_assignments.last);
          }
        }
        if (s.length == 5 && m == 'DELETE') {
          _assignments.removeWhere((a) =>
              '${a['printer_id']}' == s[2] &&
              '${a['ams_id']}' == s[3] &&
              '${a['tray_id']}' == s[4]);
          return _ok(const {'ok': true});
        }
        return _fallback(m);

      case 'catalog':
        return _ok(_coreWeights);
      case 'colors':
        return _ok(_colorCatalog);
      case 'locations':
        return _ok(const [
          {'id': 1, 'name': 'Shelf A', 'spool_count': 3},
          {'id': 2, 'name': 'Shelf B', 'spool_count': 2},
          {'id': 3, 'name': 'Dry box', 'spool_count': 2},
        ]);
    }
    return _fallback(m);
  }

  /// The `/inventory/spools/bulk-*` routes plus `reset-consumed-counter-bulk`,
  /// answering in the shapes the native backend answers in: a count, the ids it
  /// could not find, and — for archive/restore — the ids that were already in
  /// the state asked for. Returns null for a path segment that is not one of
  /// them, so the caller can go on reading it as a spool id.
  ///
  /// The refusals are copied deliberately, like [_createSpoolFromSlot]'s: an
  /// empty selection and an empty patch are both 400 on the server, and a demo
  /// that accepted them would leave the app's wording for them untried.
  DemoResult? _bulkSpools(String action, Map<String, dynamic> body) {
    // `reset-consumed-counter-bulk` is the one route keyed on `spool_ids`.
    final isReset = action == 'reset-consumed-counter-bulk';
    if (!isReset && !const {
      'bulk-update',
      'bulk-delete',
      'bulk-archive',
      'bulk-restore',
    }.contains(action)) {
      return null;
    }

    final key = isReset ? 'spool_ids' : 'ids';
    final ids = [
      for (final raw in body[key] as List? ?? const [])
        if (raw is num) raw.toInt(),
    ];
    if (ids.isEmpty) {
      return (status: 400, body: {'detail': '$key must be a non-empty list'});
    }
    if (ids.length > 500) {
      return (
        status: 422,
        body: {'detail': '$key accepts at most 500 entries'},
      );
    }

    final found = [
      for (final id in ids)
        ?_spools.where((x) => x['id'] == id).firstOrNull,
    ];
    final foundIds = {for (final spool in found) spool['id']};
    final notFound = [
      for (final id in ids)
        if (!foundIds.contains(id)) id,
    ];

    switch (action) {
      case 'bulk-update':
        final update = body['update'];
        if (update is! Map || update.isEmpty) {
          return (
            status: 400,
            body: {'detail': 'update must include at least one field'},
          );
        }
        for (final spool in found) {
          update.forEach((k, v) => spool['$k'] = v);
        }
        return _ok({'updated': found.length, 'not_found': notFound});

      case 'bulk-delete':
        for (final spool in found) {
          _spools.remove(spool);
          _assignments.removeWhere((a) => a['spool_id'] == spool['id']);
        }
        return _ok({'deleted': found.length, 'not_found': notFound});

      case 'bulk-archive':
        final already = [
          for (final spool in found)
            if (spool['archived_at'] != null) spool['id'],
        ];
        final now = _iso(DateTime.now());
        for (final spool in found) {
          spool['archived_at'] ??= now;
        }
        return _ok({
          'archived': found.length - already.length,
          'already_archived': already,
          'not_found': notFound,
        });

      case 'bulk-restore':
        final already = [
          for (final spool in found)
            if (spool['archived_at'] == null) spool['id'],
        ];
        for (final spool in found) {
          spool['archived_at'] = null;
        }
        return _ok({
          'restored': found.length - already.length,
          'already_active': already,
          'not_found': notFound,
        });

      default:
        // Reset counts the rows it found and reports nothing else, exactly as
        // the server does — the app reads the gap against what it asked for.
        for (final spool in found) {
          spool['weight_used_baseline'] = spool['weight_used'] ?? 0.0;
        }
        return _ok({'reset': found.length});
    }
  }

  /// `POST /inventory/spools/from-slot` — registers what the AMS reports in one
  /// slot and pins it there, in one call, like the server does.
  ///
  /// The two refusals are copied from it deliberately: they are what the app's
  /// wording for this action is built on, and a demo that always succeeded
  /// would leave both untested by hand.
  DemoResult _createSpoolFromSlot(Map<String, dynamic> body) {
    final printerId = (body['printer_id'] as num?)?.toInt();
    final amsId = (body['ams_id'] as num?)?.toInt();
    final trayId = (body['tray_id'] as num?)?.toInt();
    if (printerId == null || amsId == null || trayId == null) {
      return (status: 400, body: {'detail': 'Provide printer_id, ams_id and tray_id'});
    }

    final units = statusData(printerId)['ams'];
    Map<String, dynamic>? tray;
    if (units is List) {
      for (final unit in units) {
        if (unit is! Map || (unit['id'] as num?)?.toInt() != amsId) continue;
        for (final t in (unit['tray'] as List? ?? const [])) {
          if (t is Map && (t['id'] as num?)?.toInt() == trayId) {
            tray = Map<String, dynamic>.from(t);
            break;
          }
        }
        if (tray != null) break;
      }
    }

    final material = (tray?['tray_type'] as String?)?.trim() ?? '';
    if (tray == null || material.isEmpty) {
      return (
        status: 400,
        body: {'detail': 'Slot is empty or has no readable tray data'},
      );
    }
    final tagUid = tray['tag_uid'] as String?;
    final trayUuid = tray['tray_uuid'] as String?;
    if ((tagUid ?? '').isEmpty && (trayUuid ?? '').isEmpty) {
      return (status: 400, body: {'detail': 'Slot has no RFID tag'});
    }

    // "PLA Basic" → subtype "Basic", the same split the server makes.
    final subBrands = (tray['tray_sub_brands'] as String?)?.trim() ?? '';
    final subtype = subBrands.toUpperCase().startsWith('${material.toUpperCase()} ')
        ? subBrands.substring(material.length + 1)
        : null;

    // The AMS reports RRGGBBAA; the colour catalogue is keyed on #RRGGBB.
    final rgba = (tray['tray_color'] as String?) ?? 'FFFFFFFF';
    final hex = rgba.length >= 6 ? '#${rgba.substring(0, 6)}' : null;

    final spool = _createSpool({
      'material': material,
      'subtype': ?subtype,
      'brand': 'Bambu Lab',
      'color_name': _colorCatalog
          .where((c) => c['hex_color'] == hex)
          .firstOrNull?['color_name'],
      'rgba': rgba,
      'label_weight': 1000,
      'tag_uid': tagUid,
      'tray_uuid': trayUuid,
    });

    _assignments.removeWhere((a) =>
        a['printer_id'] == printerId &&
        a['ams_id'] == amsId &&
        a['tray_id'] == trayId);
    _assignments.add({
      'spool_id': spool['id'],
      'printer_id': printerId,
      'ams_id': amsId,
      'tray_id': trayId,
      'printer_name':
          _printers.where((p) => p['id'] == printerId).firstOrNull?['name'],
    });
    return _ok(spool);
  }

  Map<String, dynamic> _createSpool(Map<String, dynamic> draft) {
    final spool = <String, dynamic>{
      'id': _nextSpoolId++,
      'material': draft['material'] ?? 'PLA',
      'label_weight': draft['label_weight'] ?? 1000,
      'core_weight': draft['core_weight'] ?? 250,
      'weight_used': draft['weight_used'] ?? 0.0,
      'created_at': _iso(DateTime.now()),
      'k_profiles': const <Object>[],
      ...draft,
    };
    _spools.add(spool);
    return spool;
  }

  List<Map<String, dynamic>> _spoolUsage(int spoolId) {
    // A couple of plausible usage rows tied to real archive names.
    if (spoolId > 4) return const [];
    return [
      {
        'id': spoolId * 10 + 1,
        'print_name': 'Drawer organizer x4',
        'weight_used': 96.2,
        'percent_used': 10,
        'status': 'completed',
        'cost': 2.4,
        'created_at': _iso(_daysAgo(1)),
      },
      {
        'id': spoolId * 10 + 2,
        'print_name': 'Benchy',
        'weight_used': 15.8,
        'percent_used': 2,
        'status': 'completed',
        'cost': 0.4,
        'created_at': _iso(_daysAgo(2)),
      },
    ];
  }

  // --- Firmware ---

  static final List<Map<String, dynamic>> _firmware = [
    {
      'printer_id': 1,
      'printer_name': 'X1 Carbon',
      'model': 'X1C',
      'current_version': '01.08.02.00',
      'latest_version': '01.08.02.00',
      'update_available': false,
    },
    {
      'printer_id': 2,
      'printer_name': 'P1S',
      'model': 'P1S',
      'current_version': '01.07.01.00',
      'latest_version': '01.07.02.00',
      'update_available': true,
    },
    {
      'printer_id': 3,
      'printer_name': 'A1 mini',
      'model': 'A1 mini',
      'current_version': '01.04.00.00',
      'latest_version': '01.04.00.00',
      'update_available': false,
    },
  ];

  // --- Library ---

  late final List<Map<String, dynamic>> _libraryFolders = [
    {'id': 1, 'name': 'Calibration', 'parent_id': null, 'file_count': 3, 'children': <Object>[]},
    {'id': 2, 'name': 'Household', 'parent_id': null, 'file_count': 2, 'children': <Object>[]},
  ];

  late final List<Map<String, dynamic>> _libraryFiles = [
    _libFile(1, 'Benchy.gcode.3mf', 1, 2108509, printCount: 3, timeSec: 3540, grams: 15.8),
    _libFile(2, 'Calibration cube.gcode.3mf', 1, 812340, printCount: 1, timeSec: 1620, grams: 6.1),
    _libFile(3, 'Temp tower PLA.gcode.3mf', 1, 1430200, printCount: 1, timeSec: 5340, grams: 21.4),
    _libFile(4, 'Drawer organizer x4.gcode.3mf', 2, 4318208, printCount: 2, timeSec: 5400, grams: 96.2),
    _libFile(5, 'Cable clips x8.gcode.3mf', 2, 1524736, printCount: 1, timeSec: 5520, grams: 42.3),
    _libFile(6, 'SD card adapter.3mf', null, 634212, fileType: '3mf'),
  ];

  final List<Map<String, dynamic>> _libraryTrash = [];
  int _nextFolderId = 10;

  Map<String, dynamic> _libFile(
    int id,
    String filename,
    int? folderId,
    int size, {
    int printCount = 0,
    int? timeSec,
    double? grams,
    String fileType = 'gcode.3mf',
  }) =>
      {
        'id': id,
        'folder_id': folderId,
        'filename': filename,
        'file_type': fileType,
        'file_size': size,
        'thumbnail_path': null,
        'print_count': printCount,
        'duplicate_count': 0,
        'created_by_username': DemoConfig.username,
        'created_at': _iso(_daysAgo(id * 2)),
        'print_name': filename.split('.').first,
        'print_time_seconds': timeSec,
        'filament_used_grams': grams,
        'sliced_for_model': 'X1C',
      };

  DemoResult? _libraryRoute(
    String m,
    List<String> s,
    Map<String, String> q,
    Map<String, dynamic> body,
  ) {
    if (s.length < 2) return _notFound();
    switch (s[1]) {
      case 'files':
        if (s.length == 2 && m == 'GET') {
          if (q.containsKey('project_id')) return _ok(const <Object>[]);
          final folderId = int.tryParse(q['folder_id'] ?? '');
          if (folderId != null) {
            return _ok(_libraryFiles
                .where((f) => f['folder_id'] == folderId)
                .toList());
          }
          // include_root=false → whole library; otherwise root level only.
          return _ok(q['include_root'] == 'false'
              ? _libraryFiles
              : _libraryFiles.where((f) => f['folder_id'] == null).toList());
        }
        if (s.length == 2 && m == 'POST') {
          return (status: 501, body: {'detail': 'Upload unavailable in demo'});
        }
        if (s.length >= 3 && s[2] == 'move' && m == 'POST') {
          final ids = (body['file_ids'] as List?) ?? const [];
          for (final f in _libraryFiles) {
            if (ids.contains(f['id'])) f['folder_id'] = body['folder_id'];
          }
          return _ok(const {'ok': true});
        }
        if (s.length >= 3 && s[2] == 'add-to-queue' && m == 'POST') {
          final ids = (body['file_ids'] as List?) ?? const [];
          for (final f in _libraryFiles) {
            if (!ids.contains(f['id'])) continue;
            _queue.add(_queueItem(
              id: _nextQueueId++,
              printerId: null,
              position: _queue.length + 1,
              name: '${f['print_name']}',
              status: 'pending',
              timeSec: (f['print_time_seconds'] as int?) ?? 3600,
              grams: (f['filament_used_grams'] as num?)?.toDouble() ?? 20,
              type: 'PLA',
              color: '#808080',
              createdDaysAgo: 0,
            ));
          }
          return _ok(const {'ok': true});
        }
        final fileId = int.tryParse(s.length > 2 ? s[2] : '');
        final file =
            _libraryFiles.where((f) => f['id'] == fileId).firstOrNull;
        if (file == null) return _fallback(m);
        if (s.length == 3) {
          if (m == 'GET') return _ok(file);
          if (m == 'PUT') {
            if (body.containsKey('filename')) file['filename'] = body['filename'];
            return _ok(file);
          }
          if (m == 'DELETE') {
            _libraryFiles.remove(file);
            _libraryTrash.add({
              'id': file['id'],
              'filename': file['filename'],
              'file_size': file['file_size'],
              'thumbnail_path': null,
              'deleted_at': _iso(DateTime.now()),
            });
            return _ok(const {'ok': true});
          }
        }
        if (s.length >= 4 && s[3] == 'print') {
          return _ok(const {'ok': true});
        }
        return _fallback(m);

      case 'folders':
        if (s.length == 2 && m == 'GET') return _ok(_libraryFolders);
        if (s.length == 2 && m == 'POST') {
          final folder = {
            'id': _nextFolderId++,
            'name': body['name'] ?? 'New folder',
            'parent_id': body['parent_id'],
            'file_count': 0,
            'children': const <Object>[],
          };
          _libraryFolders.add(folder);
          return _ok(folder);
        }
        if (s.length >= 3 && s[2] == 'by-project') return _ok(const <Object>[]);
        final folderId = int.tryParse(s.length > 2 ? s[2] : '');
        final folder =
            _libraryFolders.where((f) => f['id'] == folderId).firstOrNull;
        if (folder == null) return _fallback(m);
        if (m == 'PUT') {
          if (body.containsKey('name')) folder['name'] = body['name'];
          return _ok(folder);
        }
        if (m == 'DELETE') {
          _libraryFolders.remove(folder);
          _libraryFiles.removeWhere((f) => f['folder_id'] == folderId);
          return _ok(const {'ok': true});
        }
        return _fallback(m);

      case 'stats':
        return _ok({
          'total_files': _libraryFiles.length,
          'total_folders': _libraryFolders.length,
          'total_size': _libraryFiles.fold<int>(
              0, (sum, f) => sum + (f['file_size'] as int)),
          'free_bytes': 52 * 1024 * 1024 * 1024,
        });

      case 'bulk-delete':
        final fileIds = (body['file_ids'] as List?) ?? const [];
        _libraryFiles.removeWhere((f) => fileIds.contains(f['id']));
        return _ok(const {'ok': true});

      case 'trash':
        if (s.length == 2 && m == 'GET') {
          return _ok({'items': _libraryTrash, 'total': _libraryTrash.length, 'retention_days': 30});
        }
        if (s.length == 2 && m == 'DELETE') {
          _libraryTrash.clear();
          return _ok(const {'ok': true});
        }
        if (s.length >= 4 && s[3] == 'restore') {
          final tid = int.tryParse(s[2]);
          final t = _libraryTrash.where((f) => f['id'] == tid).firstOrNull;
          if (t != null) {
            _libraryTrash.remove(t);
            _libraryFiles.add(_libFile(
                t['id'] as int, t['filename'] as String, null, t['file_size'] as int));
          }
          return _ok(const {'ok': true});
        }
        if (s.length == 3 && m == 'DELETE') {
          _libraryTrash.removeWhere((f) => '${f['id']}' == s[2]);
          return _ok(const {'ok': true});
        }
        return _fallback(m);
    }
    return _fallback(m);
  }

  // --- Projects ---

  late final List<Map<String, dynamic>> _projects = [
    {
      'id': 1,
      'name': 'Workshop organizers',
      'description': 'Drawer and wall organizers for the workshop.',
      'color': '#2196F3',
      'status': 'active',
      'target_count': 12,
      'target_parts_count': null,
      'budget': 60.0,
      'priority': 'normal',
      'tags': 'organization,workshop',
      'notes': 'Match the 25 mm grid on the tool wall.',
      'created_at': _iso(_daysAgo(20)),
      'updated_at': _iso(_daysAgo(1)),
    },
    {
      'id': 2,
      'name': 'Birthday gifts',
      'description': 'Flexi animals for the kids.',
      'color': '#9C27B0',
      'status': 'completed',
      'target_count': 5,
      'target_parts_count': null,
      'budget': null,
      'priority': 'high',
      'tags': 'gifts',
      'notes': null,
      'created_at': _iso(_daysAgo(40)),
      'updated_at': _iso(_daysAgo(25)),
    },
  ];

  late final Map<int, List<Map<String, dynamic>>> _projectBom = {
    1: [
      {
        'id': 1,
        'project_id': 1,
        'name': 'M3x12 screws',
        'quantity_needed': 24,
        'quantity_acquired': 24,
        'unit_price': 0.05,
        'sort_order': 0,
        'is_complete': true,
      },
      {
        'id': 2,
        'project_id': 1,
        'name': 'Rubber feet',
        'quantity_needed': 12,
        'quantity_acquired': 4,
        'unit_price': 0.2,
        'sort_order': 1,
        'is_complete': false,
      },
    ],
  };
  int _nextBomId = 10;
  int _nextProjectId = 10;

  Map<String, dynamic> _projectListJson(Map<String, dynamic> p) {
    final isFirst = p['id'] == 1;
    final previews = isFirst
        ? _archives
            .take(3)
            .map((a) => {
                  'id': a['id'],
                  'print_name': a['print_name'],
                  'thumbnail_path': null,
                  'status': a['status'],
                  'filament_type': a['filament_type'],
                  'filament_color': a['filament_color'],
                })
            .toList()
        : const <Object>[];
    return {
      ...p,
      'archive_count': isFirst ? 8 : 5,
      'total_items': isFirst ? 8 : 5,
      'completed_count': isFirst ? 7 : 5,
      'failed_count': isFirst ? 1 : 0,
      'queue_count': isFirst ? 2 : 0,
      'progress_percent': isFirst ? 58.3 : 100.0,
      'archives': previews,
      'url': null,
      'cover_image_filename': null,
    };
  }

  Map<String, dynamic> _projectDetailJson(Map<String, dynamic> p) {
    final isFirst = p['id'] == 1;
    final bom = _projectBom[p['id']] ?? const [];
    return {
      ..._projectListJson(p),
      'attachments': const <Object>[],
      'due_date': null,
      'is_template': false,
      'parent_id': null,
      'parent_name': null,
      'children': const <Object>[],
      'stats': {
        'total_archives': isFirst ? 8 : 5,
        'total_items': isFirst ? 8 : 5,
        'completed_prints': isFirst ? 7 : 5,
        'failed_prints': isFirst ? 1 : 0,
        'queued_prints': isFirst ? 2 : 0,
        'in_progress_prints': isFirst ? 1 : 0,
        'total_print_time_hours': isFirst ? 14.6 : 9.2,
        'total_filament_grams': isFirst ? 512.4 : 341.0,
        'progress_percent': isFirst ? 58.3 : 100.0,
        'parts_progress_percent': null,
        'estimated_cost': isFirst ? 12.8 : 8.5,
        'total_energy_kwh': isFirst ? 1.6 : 1.0,
        'total_energy_cost': isFirst ? 0.5 : 0.3,
        'remaining_prints': isFirst ? 5 : 0,
        'remaining_parts': null,
        'bom_total_items': bom.length,
        'bom_completed_items':
            bom.where((b) => b['is_complete'] == true).length,
        'bom_cost': 2.6,
      },
    };
  }

  DemoResult? _projectsRoute(
    String m,
    List<String> s,
    Map<String, String> q,
    Map<String, dynamic> body,
  ) {
    if (s.length == 1) {
      if (m == 'GET') {
        var list = _projects;
        final status = q['status'];
        if (status != null && status.isNotEmpty) {
          list = list.where((p) => p['status'] == status).toList();
        }
        return _ok([for (final p in list) _projectListJson(p)]);
      }
      if (m == 'POST') {
        final project = <String, dynamic>{
          'id': _nextProjectId++,
          'status': 'active',
          'priority': body['priority'] ?? 'normal',
          'created_at': _iso(DateTime.now()),
          'updated_at': _iso(DateTime.now()),
          ...body,
        };
        _projects.add(project);
        return _ok(_projectDetailJson(project));
      }
    }
    if (s.length >= 2 && s[1] == 'templates') return _ok(const <Object>[]);
    final pid = int.tryParse(s.length > 1 ? s[1] : '');
    final project = _projects.where((p) => p['id'] == pid).firstOrNull;
    if (project == null) return _fallback(m);
    if (s.length == 2) {
      if (m == 'GET') return _ok(_projectDetailJson(project));
      if (m == 'PATCH') {
        body.forEach((k, v) => project[k] = v);
        project['updated_at'] = _iso(DateTime.now());
        return _ok(_projectDetailJson(project));
      }
      if (m == 'DELETE') {
        _projects.remove(project);
        return _ok(const {'ok': true});
      }
    }
    if (s.length >= 3) {
      switch (s[2]) {
        case 'archives':
          return _ok((_projectListJson(project)['archives'] as List?) ?? const []);
        case 'queue':
          return _ok(const <Object>[]);
        case 'timeline':
          return _ok(const <Object>[]);
        case 'bom':
          final bom = _projectBom.putIfAbsent(pid!, () => []);
          if (s.length == 3) {
            if (m == 'GET') return _ok(bom);
            if (m == 'POST') {
              bom.add({
                'id': _nextBomId++,
                'project_id': pid,
                'name': body['name'] ?? 'Item',
                'quantity_needed': body['quantity_needed'] ?? 1,
                'quantity_acquired': body['quantity_acquired'] ?? 0,
                'unit_price': body['unit_price'],
                'sort_order': bom.length,
                'is_complete': false,
              });
              return _ok(bom.last);
            }
          }
          final bomId = int.tryParse(s.length > 3 ? s[3] : '');
          final item = bom.where((b) => b['id'] == bomId).firstOrNull;
          if (item != null && m == 'PATCH') {
            body.forEach((k, v) => item[k] = v);
            final needed = (item['quantity_needed'] as num?) ?? 1;
            final acquired = (item['quantity_acquired'] as num?) ?? 0;
            item['is_complete'] = acquired >= needed;
            return _ok(item);
          }
          if (item != null && m == 'DELETE') {
            bom.remove(item);
            return _ok(const {'ok': true});
          }
          return _fallback(m);
        case 'add-archives':
        case 'remove-archives':
        case 'add-queue':
        case 'create-template':
          return _ok(const {'ok': true});
      }
    }
    return _fallback(m);
  }

  // --- Helpers ---

  static DateTime _daysAgo(int days, {int hours = 0}) =>
      DateTime.now().subtract(Duration(days: days, hours: hours));

  static String _iso(DateTime t) => t.toUtc().toIso8601String();
}
