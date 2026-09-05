import 'dart:math' as math;
import 'dart:typed_data';

import '../models/json_utils.dart';
import 'demo_config.dart';

/// Result of a routed demo request: HTTP status + JSON-encodable body.
typedef DemoResult = ({int status, Object? body});

/// A response that is a file rather than a document.
///
/// Carried as the result's `body` so every other route keeps its two-field
/// shape; `DemoHttpClientAdapter` serves this one as bytes with its own content
/// type instead of JSON-encoding it.
class DemoFile {
  const DemoFile(this.bytes, this.contentType);

  final Uint8List bytes;
  final String contentType;
}

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
  // Runs the demo "scheduler" is holding. Nothing dispatches them — the demo
  // has no clock the printer answers to — so a row stays pending until it is
  // cancelled, which is exactly the state the card's banner is there to show.
  final List<Map<String, dynamic>> _scheduledDryings = [];
  int _nextScheduledDryingId = 1;
  final Map<int, bool> _plugOn = {1: true, 2: false};
  // What the slot-configuration sheet wrote, keyed `printer:ams:tray`. Applied
  // over the generated status so a demo write shows on the card, the way the
  // printer's own push would.
  final Map<String, Map<String, dynamic>> _slotConfig = {};
  // Which preset each slot was given, keyed the same way — the mapping the real
  // server keeps so a configured slot can be named, not just shown.
  final Map<String, Map<String, dynamic>> _slotPreset = {};

  // Saved pipelines and the runs they dispatched. Mutable because the whole
  // point of the screens is authoring: targeting one, running it, cancelling
  // and retrying. Seeded lazily so the fixtures below can be built once the
  // instance exists.
  List<Map<String, dynamic>>? _pipelinesStore;
  List<Map<String, dynamic>>? _pipelineRunsStore;
  int _nextPipelineId = 3;
  int _nextPipelineRunId = 100;
  int _nextPipelineJobId = 500;

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
  DemoResult _file(Uint8List bytes, String contentType) =>
      (status: 200, body: DemoFile(bytes, contentType));
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
        // The version has to match what this backend actually serves, or a
        // gated control appears over data that is not there — and the queue
        // form would offer two states over three-state calibrations.
        //
        // 1.2.6 is what serves the print log's cost and energy and its sortable
        // columns; the beta suffix because that is where the contract really
        // lives today, 1.2.5.2 being the newest release. It is also the version
        // that gates `process_overrides` and `auto_orient`/`auto_arrange` on a
        // slice, both of which the routes below accept — the users listing is
        // the one thing 1.2.6 gates that is decided by probing instead.
        if (at(1, 'version')) {
          return _ok(const {
            'version': '1.2.6b1',
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
          if (s.length == 3 && m == 'GET') {
            return _ok(_printerFiles(q['path'] ?? '/', pid));
          }
          // Downloading is the one printer-file action with something to hand
          // back, so demo mode serves it rather than falling through: without
          // this a tap answered 404 for a single file and, because the fallback
          // says yes to a POST, handed the ZIP button two bytes of JSON.
          if (s.length == 4 && at(3, 'download') && m == 'GET') {
            final path = q['path'] ?? '';
            if (path.isEmpty) return _notFound();
            return _file(_printerFileBytes(path, pid), _demoContentType(path));
          }
          if (s.length == 4 && at(3, 'download-zip') && m == 'POST') {
            final paths = (body['paths'] as List?)?.whereType<String>().toList();
            if (paths == null || paths.isEmpty) {
              return (status: 400, body: {'detail': 'No files specified'});
            }
            return _file(_emptyZip(), 'application/zip');
          }
          if (s.length == 4 && at(3, 'download-job') && m == 'POST') {
            return _startDownloadJob(pid, body);
          }
          if (s.length == 5 && at(3, 'download-jobs')) {
            return _downloadJobRoute(m, pid, s[4]);
          }
          if (s.length == 6 && at(3, 'dl')) {
            return _preparedDownload(pid, s[4]);
          }
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

      case 'scheduled-dryings':
        return _scheduledDryingRoute(m, s, q, body);

      case 'slicer-pipelines':
        return _pipelineRoute(m, s, body);

      case 'pipeline-runs':
        return _pipelineRunsRoute(m, s, q);

      case 'location-ha-sensors':
        if (s.length == 1) return _ok(_locationSensors);
        if (at(1, 'by-location') && at(3, 'readings')) {
          return _ok(_locationSensorReadings(id(2) ?? 0));
        }
        return _notFound();

      case 'queue':
        return _queueRoute(m, s, body);

      case 'archives':
        return _archivesRoute(m, s, q, body);

      case 'print-log':
        return _printLogRoute(m, s, q, body);

      case 'smart-plugs':
        return _plugsRoute(m, s, body);

      case 'maintenance':
        return _maintenanceRoute(m, s, body);

      case 'inventory':
        return _inventoryRoute(m, s, q, body, rawBody);

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
          // On, so the slice form is reachable at all: it gates every Slice
          // button in the app, and with it off the pipelines feature showed
          // only its read-only half.
          'use_slicer_api': true,
          'currency': 'USD',
          // Auto-print snippets, as the real server stores them: a JSON string
          // keyed by printer model. Only the A1 mini has one, so demo shows both
          // halves of the gate — the injection checkbox appears, and picking the
          // X1C or the P1S says out loud that nothing would be injected.
          'gcode_snippets':
              '{"A1 mini":{"start_gcode":"G4 S1\\nM106 P1 S255",'
                  '"end_gcode":"G4 S1\\nG0 Y5 F500\\nG0 Y100 F5000\\n;plate-swap start"}}',
          // Drying presets as the real server stores them: a JSON string, not
          // an object. Two rows differ from the built-in defaults (PETG 70 °C /
          // 8 h) so demo shows the customisation actually reaching the sheet
          // rather than the bundled table that would look identical.
          'drying_presets':
              '{"PLA":{"n3f":45,"n3s":45,"n3f_hours":12,"n3s_hours":12},'
                  '"PETG":{"n3f":70,"n3s":70,"n3f_hours":8,"n3s_hours":8},'
                  '"ABS":{"n3f":65,"n3s":80,"n3f_hours":12,"n3s_hours":8}}',
          // The server's own drying automation, which the sheet reports and
          // never offers to change — writing these is settings:update, denied
          // to every API key.
          'ambient_drying_enabled': true,
          'queue_drying_enabled': true,
          'print_drying_enabled': false,
          // The ceiling the run form's copies stepper stops at. Deliberately
          // not the server's own default of 50: a demo that agreed with the
          // fallback would not show whether the setting is read at all.
          'pipeline_max_copies': 12,
        });

      case 'slice-jobs':
        return _sliceJobRoute(id(1));

      case 'slicer':
        if (at(1, 'printer-models')) return _ok(_printerModels);
        // The catalogue both features read: the slice form's three pickers,
        // and the pipeline cards resolving their stored `PresetRef`s (without
        // it every row read "No longer in the catalog").
        if (at(1, 'presets')) return _ok(_slicerPresets);
        if (at(1, 'preset-values')) return _presetValues(q);
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

  /// `/slicer/presets` — the tiers the unified picker merges, holding exactly
  /// the presets the demo pipelines point at plus a couple more so a picker has
  /// something to choose between.
  static const _slicerPresets = {
    'local': {
      'printer': [
        {'source': 'local', 'id': 'p-x1c-04', 'name': 'X1C 0.4 nozzle'},
        {'source': 'local', 'id': 'p-p1s-04', 'name': 'P1S 0.4 nozzle'},
      ],
      'process': [
        {'source': 'local', 'id': 'q-020-std', 'name': '0.20mm Standard @X1C'},
        {'source': 'local', 'id': 'q-028-draft', 'name': '0.28mm Draft @X1C'},
      ],
      'filament': [
        {
          'source': 'local',
          'id': 'f-petg-white',
          'name': 'Generic PETG @X1C',
          'filament_type': 'PETG',
          'filament_colour': '#FFFFFF',
        },
        {
          'source': 'local',
          'id': 'f-asa-black',
          'name': 'Fiberlogy ASA @X1C',
          'filament_type': 'ASA',
          'filament_colour': '#1A1A1A',
        },
      ],
    },
    'standard': {
      'printer': <Object>[],
      'process': [
        {
          'source': 'standard',
          'id': '0.20mm Standard @BBL X1C',
          'name': '0.20mm Standard @BBL X1C',
        },
      ],
      'filament': [
        {
          'source': 'standard',
          'id': 'Bambu PLA Basic @BBL X1C',
          'name': 'Bambu PLA Basic @BBL X1C',
          'filament_type': 'PLA',
        },
      ],
    },
  };

  // --- Server-side slicing ---

  /// The two-tone source, which is the only demo file that needs more than one
  /// filament slot. Named rather than inlined because three routes have to
  /// agree about which file that is.
  static const _multiSlotFileId = 7;

  /// The one archive that kept the project file it was sliced from, so its card
  /// can offer a re-slice. Found by print name rather than id: the ids are
  /// handed out in fixture order and would move if a print were inserted above.
  int get _sliceableArchiveId =>
      _archives.firstWhere((a) => a['print_name'] == 'Benchy')['id'] as int;

  /// `/slicer/preset-values` — the picked process preset's effective values,
  /// flattened, as the sidecar answers them.
  ///
  /// The standard tier deliberately has no entry: on a real install a sidecar
  /// older than the endpoint is the common cause of an unresolved answer, and
  /// it is the only way to reach the panel's "opened on the schema's own
  /// defaults, and here is why" state.
  DemoResult _presetValues(Map<String, String> q) {
    if ((q['slot'] ?? 'process') != 'process') {
      return (
        status: 400,
        body: {'detail': "Only the 'process' slot is supported"},
      );
    }
    final values = _processPresetValues[q['id']];
    if (values == null) {
      return _ok(const {
        'resolved': false,
        'values': <String, Object>{},
        'reason': 'sidecar_outdated',
      });
    }
    return _ok({'resolved': true, 'values': values, 'reason': 'ok'});
  }

  /// Effective process values per local preset id, spelled as a process JSON
  /// spells them — every scalar a string, booleans `1`/`0`, percents with the
  /// sign, vectors as arrays. A number here would make the settings panel read
  /// the field as user-modified the moment it opened.
  ///
  /// The two presets differ in more than the layer height so that switching
  /// between them visibly re-baselines the panel rather than moving one row.
  static const _processPresetValues = {
    'q-020-std': {
      'layer_height': '0.2',
      'initial_layer_print_height': '0.2',
      'wall_loops': '2',
      'top_shell_layers': '5',
      'bottom_shell_layers': '3',
      'sparse_infill_density': '15%',
      'sparse_infill_pattern': 'grid',
      'enable_support': '0',
      'brim_type': 'auto_brim',
      'outer_wall_speed': ['200'],
    },
    'q-028-draft': {
      'layer_height': '0.28',
      'initial_layer_print_height': '0.28',
      'wall_loops': '2',
      'top_shell_layers': '4',
      'bottom_shell_layers': '3',
      'sparse_infill_density': '10%',
      'sparse_infill_pattern': 'gyroid',
      'enable_support': '0',
      'brim_type': 'auto_brim',
      'outer_wall_speed': ['250'],
    },
  };

  /// Layer height a picked process preset slices at, as a number. Falls back to
  /// the demo's own 0.20 for the standard tier, whose values this backend does
  /// not claim to know.
  double _layerHeightOf(String presetId) =>
      double.tryParse('${_processPresetValues[presetId]?['layer_height']}') ??
      0.2;

  /// `/library/files/{id}/plates` — the plates to choose between, plus the
  /// presets the 3MF names in its own project settings.
  ///
  /// A non-3MF gets the short shape the server gives it, with no
  /// `design_overrides` key at all: its absence is what tells the app that
  /// "slice as designed" is not on offer here, as against being empty.
  Map<String, dynamic> _libraryPlates(Map<String, dynamic> file) {
    final filename = '${file['filename']}';
    if (!filename.toLowerCase().endsWith('.3mf')) {
      return {
        'file_id': file['id'],
        'filename': filename,
        'plates': const <Object>[],
        'is_multi_plate': false,
      };
    }
    final count = file['id'] == _multiSlotFileId ? 2 : 1;
    return {
      'file_id': file['id'],
      'filename': filename,
      'plates': [
        for (var i = 1; i <= count; i++)
          {
            'index': i,
            'name': null,
            'objects': <String>[],
            'object_count': 1,
            'has_thumbnail': false,
            'thumbnail_url': null,
            // Both estimates come out of the metadata a slice writes, so they
            // are null on an un-sliced source and read off the row on output
            // this backend produced itself.
            'print_time_seconds': toIntOrNull(file['print_time_seconds']),
            'filament_used_grams': toDoubleOrNull(file['filament_used_grams']),
            'filaments': <Object>[],
          },
      ],
      'is_multi_plate': count > 1,
      // Verbatim preset names, matched against the catalogue by name — so these
      // have to be spelled as `/slicer/presets` spells them or the switch never
      // appears.
      'embedded_printer': 'X1C 0.4 nozzle',
      'embedded_process': '0.20mm Standard @X1C',
      'design_overrides': const [
        {
          'key': 'wall_loops',
          'value': '3',
          'printer_coupled': false,
          'preset_defining': false,
        },
        {
          'key': 'sparse_infill_density',
          'value': '25%',
          'printer_coupled': false,
          'preset_defining': false,
        },
      ],
    };
  }

  /// The two-tone source's project slots. Four of them, two materials, so the
  /// per-slot pickers have something to auto-pick from by type and colour.
  static const _twoToneSlots = [
    {'slot_id': 1, 'type': 'PLA', 'color': '#FFFFFF'},
    {'slot_id': 2, 'type': 'PLA', 'color': '#1A1A1A'},
    {'slot_id': 3, 'type': 'PETG', 'color': '#FF6A13'},
    {'slot_id': 4, 'type': 'PETG', 'color': '#0ACCB8'},
  ];

  /// Which of [_twoToneSlots] each plate actually prints from. The point of the
  /// table: the file declares four slots and no plate uses all four, so the
  /// answer genuinely depends on `plate_id` — which is the trap the slice form
  /// avoids by asking about the same plate it is going to slice.
  static const _twoTonePlateSlots = {
    1: [1, 2],
    2: [3, 4],
  };

  /// `/library/files/{id}/filament-requirements`.
  ///
  /// `full_slots` is the difference between the two callers: the slice form
  /// wants one row per **project** slot, because `filament_presets` is
  /// positional, while print-time AMS matching wants only the slots the plate
  /// consumes. A source with no filament table answers none, and the slice form
  /// falls back to a single generic picker.
  Map<String, dynamic> _libraryFilaments(
    Map<String, dynamic> file,
    Map<String, String> q,
  ) {
    final plateId = int.tryParse(q['plate_id'] ?? '') ?? 1;
    final rows = <Map<String, dynamic>>[];
    if ('${file['filename']}'.toLowerCase().endsWith('.3mf')) {
      final used = file['id'] == _multiSlotFileId
          ? (_twoTonePlateSlots[plateId] ?? const <int>[])
          : const [1];
      final slots = file['id'] == _multiSlotFileId
          ? _twoToneSlots
          : const [
              {'slot_id': 1, 'type': 'PLA', 'color': '#0ACCB8'}
            ];
      for (final slot in slots) {
        final inPlate = used.contains(slot['slot_id']);
        if (!inPlate && q['full_slots'] != 'true') continue;
        rows.add({
          ...slot,
          // No measured figure on a source that has never been sliced.
          'used_grams': 0,
          'used_meters': 0,
          'used_in_plate': inPlate,
        });
      }
    }
    return {
      'file_id': file['id'],
      'filename': file['filename'],
      'plate_id': plateId,
      'filaments': rows,
    };
  }

  /// `/archives/{id}/filament-requirements` — one slot, holding what the print
  /// actually ran with. A sliced file's table is the used-only one, so every
  /// row it can offer is used by definition.
  Map<String, dynamic> _archiveFilaments(Map<String, dynamic> archive) {
    final grams = toDouble(archive['filament_used_grams']);
    return {
      'archive_id': archive['id'],
      'filename': archive['filename'],
      'filaments': [
        {
          'slot_id': 1,
          'type': archive['filament_type'],
          'color': archive['filament_color'],
          'used_grams': grams,
          'used_meters': _r1(grams * 0.33),
          'used_in_plate': true,
        },
      ],
    };
  }

  /// Slice jobs this backend has handed out, by id. Never swept: the demo has
  /// no retention window to model, and a job the dialog is still polling is the
  /// only one anybody asks about.
  final Map<int, Map<String, dynamic>> _sliceJobs = {};
  int _nextSliceJobId = 700;

  /// How long a demo slice takes. Comfortably longer than the dialog's 1.5 s
  /// poll: a job already finished by the first poll would never show a stage or
  /// a percentage, which is most of what that dialog is. Settable so a contract
  /// test can watch a whole run without spending nine seconds on it.
  static double sliceSeconds = 9;

  /// `POST …/slice` — enqueue, exactly as the server does: 202 carrying the id
  /// to poll and nothing else. What the slicer would produce is decided here,
  /// from the source and the picked process preset, and handed out by
  /// [_sliceJobRoute] once enough time has passed for it to be believable.
  DemoResult _startSlice({
    required bool isArchive,
    required Map<String, dynamic> source,
    required Map<String, dynamic> body,
  }) {
    final filename = '${source['filename']}'.toLowerCase();
    if (!isArchive) {
      // Both refusals land before a byte is read, and the STEP one is its own
      // message because neither slicer CLI can load the format at all — read as
      // a corrupt model, it would send the user looking in the wrong place.
      if (filename.endsWith('.step') || filename.endsWith('.stp')) {
        return (
          status: 400,
          body: {
            'detail': 'STEP files cannot be sliced. The OrcaSlicer and Bambu '
                'Studio command-line slicers load only STL and 3MF -- open the '
                'STEP in your slicer and export it as one of those first.',
          },
        );
      }
      if (!filename.endsWith('.stl') && !filename.endsWith('.3mf')) {
        return (
          status: 400,
          body: {'detail': 'Source file must be STL or 3MF'},
        );
      }
    }
    final jobId = _nextSliceJobId++;
    final process = body['process_preset'];
    _sliceJobs[jobId] = {
      'kind': isArchive ? 'archive' : 'library_file',
      'source': source,
      'started_ms': DateTime.now().millisecondsSinceEpoch,
      'created_at': _iso(DateTime.now()),
      'embedded': body['use_embedded_settings'] == true,
      'layer_height': _layerHeightOf(
          process is Map ? '${process['id']}' : ''),
      'printer_preset': body['printer_preset'],
      'result': null,
    };
    return (
      status: 202,
      body: {
        'job_id': jobId,
        'status': 'pending',
        'status_url': '/api/v1/slice-jobs/$jobId',
      },
    );
  }

  /// `GET /slice-jobs/{id}` — the status the progress dialog polls.
  ///
  /// Time-based like the print simulation: the phase and the percentage come
  /// out of how long ago the job was enqueued, so it advances between polls
  /// with nothing running in between.
  DemoResult _sliceJobRoute(int? jobId) {
    final job = _sliceJobs[jobId];
    if (job == null) {
      return (status: 404, body: {'detail': 'Slice job not found or expired'});
    }
    final elapsed =
        (DateTime.now().millisecondsSinceEpoch - (job['started_ms'] as int)) /
            1000;
    final done = elapsed >= sliceSeconds;
    // The sidecar publishes nothing for the first moment of a slice, which is
    // what puts the dialog on an indeterminate bar instead of a 0%.
    final started = elapsed >= 1;
    final body = <String, dynamic>{
      'job_id': jobId,
      'status': done
          ? 'completed'
          : started
              ? 'running'
              : 'pending',
      'kind': job['kind'],
      'source_id': (job['source'] as Map)['id'],
      'source_name': (job['source'] as Map)['filename'],
      'created_at': job['created_at'],
      'started_at': job['created_at'],
      'progress': done || !started ? null : _sliceProgress(elapsed),
    };
    if (done) {
      // Stamped alongside the result, so both are decided on the first poll
      // that finds the job over rather than moving with each later one.
      job['completed_at'] ??= _iso(DateTime.now());
      body['result'] = _sliceResult(job);
    }
    body['completed_at'] = job['completed_at'];
    return _ok(body);
  }

  /// The sidecar's own snapshot, which the server forwards verbatim: a stage
  /// name and a whole-slice percentage.
  static Map<String, dynamic> _sliceProgress(double elapsed) {
    final percent = (elapsed / sliceSeconds * 100).clamp(1, 99).round();
    final stage = switch (percent) {
      < 25 => 'Processing triangulated mesh',
      < 45 => 'Generating perimeters',
      < 65 => 'Preparing infill',
      < 85 => 'Generating G-code',
      _ => 'Exporting G-code',
    };
    return {'stage': stage, 'total_percent': percent};
  }

  /// What the slice produced, filed where the server would have filed it.
  ///
  /// Built on the first poll that finds the job finished and kept on the job
  /// afterwards: the row it adds to the library or the archives must be added
  /// once, and this is polled repeatedly.
  Map<String, dynamic> _sliceResult(Map<String, dynamic> job) {
    final cached = job['result'];
    if (cached is Map<String, dynamic>) return cached;

    final source = job['source'] as Map<String, dynamic>;
    final bytes = toInt(source['file_size']);
    // A source that has been through a slicer already knows what it costs — an
    // archive always does — and only an un-sliced upload has to be guessed at
    // from its size. Either way the picked process preset moves the time, so
    // the two presets do not produce the same estimate.
    final known = toIntOrNull(source['print_time_seconds']);
    final seconds =
        ((known ?? bytes / 520) * (0.2 / (job['layer_height'] as double)))
            .round();
    final grams =
        toDoubleOrNull(source['filament_used_grams']) ?? _r1(bytes / 26000);
    final base = '${source['print_name'] ?? source['filename']}';
    final result = <String, dynamic>{
      'print_time_seconds': seconds,
      'filament_used_g': grams,
      // 1.75 mm filament runs about 330 mm to the gram.
      'filament_used_mm': _r1(grams * 330),
      'used_embedded_settings': job['embedded'] == true,
      'external_write_fallback': null,
    };
    final printerPreset = job['printer_preset'];
    final model = _modelOfPrinterPreset(
        printerPreset is Map ? '${printerPreset['id']}' : '');
    if (job['kind'] == 'archive') {
      final archive = _resliceArchive(source, base, seconds, grams, model);
      result['archive_id'] = archive['id'];
      result['name'] = archive['print_name'];
    } else {
      final file = _slicedLibraryFile(source, base, seconds, grams, model);
      result['library_file_id'] = file['id'];
      result['name'] = file['filename'];
    }
    job['result'] = result;
    return result;
  }

  /// The sliced output, filed in the library beside its source — which is where
  /// the user goes looking for it, and the reason this is a row rather than a
  /// number in a dialog.
  Map<String, dynamic> _slicedLibraryFile(
    Map<String, dynamic> source,
    String base,
    int seconds,
    double grams,
    String? model,
  ) {
    final file = _libFile(
      _nextLibraryFileId++,
      '$base.gcode.3mf',
      source['folder_id'] as int?,
      (grams * 21000).round(),
      timeSec: seconds,
      grams: grams,
      model: model,
    );
    _libraryFiles.add(file);
    return file;
  }

  /// The re-sliced output as an archive row: sliced but never printed, so it
  /// carries the estimates and no run of its own.
  Map<String, dynamic> _resliceArchive(
    Map<String, dynamic> source,
    String base,
    int seconds,
    double grams,
    String? model,
  ) {
    // The output is for whatever printer was just picked, not for the one the
    // source happened to print on — copying the source's model is what left a
    // cross-printer re-slice wearing the old badge (server #2636 follow-up).
    final printer =
        _printers.where((p) => p['model'] == model).firstOrNull?['id'];
    final archive = {
      ...source,
      'id': _archives.map((a) => toInt(a['id'])).reduce(math.max) + 1,
      'filename': '$base.gcode.3mf',
      'print_name': '$base (re-sliced)',
      'printer_id': printer ?? source['printer_id'],
      'sliced_for_model': model ?? source['sliced_for_model'],
      'print_time_seconds': seconds,
      'filament_used_grams': grams,
      // Nothing ran, so there is nothing measured: no run, no accuracy, no
      // energy. The demo's own statistics coerce these rather than assume a
      // print behind every archive row.
      'actual_time_seconds': 0,
      'time_accuracy': null,
      'total_filament_actual_grams': null,
      'started_at': null,
      'completed_at': null,
      'run_count': 0,
      'last_run_at': null,
      'successful_run_count': 0,
      'failed_run_count': 0,
      'cost': _r1(grams * 0.025),
      'energy_kwh': 0.0,
      'energy_cost': 0.0,
      'created_at': _iso(DateTime.now()),
    };
    _archives.insert(0, archive);
    return archive;
  }

  /// Short model code for a printer preset the slice was sent with, so the
  /// output row says which printer it is for. Matched the way the app matches
  /// it — the code as a whole token in the preset's name — rather than by a
  /// table of preset ids that would have to be kept in step with the catalogue.
  String? _modelOfPrinterPreset(String presetId) {
    final printers = (_slicerPresets['local']?['printer'] ?? const []) as List;
    final name = printers
        .whereType<Map<String, Object>>()
        .where((p) => p['id'] == presetId)
        .map((p) => '${p['name']}'.toUpperCase())
        .firstOrNull;
    if (name == null) return null;
    for (final code in _printerModels.values) {
      if (RegExp('(?<![A-Z0-9])$code(?![A-Z0-9])').hasMatch(name)) return code;
    }
    return null;
  }

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
    // The second X1C, and the only reason the fleet is five rather than four:
    // a pipeline targeting a *class* matches on `Printer.model`, so with four
    // distinct models every class has exactly one member and the whole of
    // fanout — the per-printer eligibility breakdown, "1 of 2 ready", copies
    // spread over two machines — is unreachable. It carries PLA where printer 1
    // carries PETG, which is what makes the mismatch in that breakdown real
    // rather than fabricated.
    {
      'id': 5,
      'name': 'X1 Carbon #2',
      'serial_number': '01P00A390800001',
      'ip_address': '192.168.4.25',
      'access_code': '55019473',
      'model': 'X1C',
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
        5 => _statusSecondX1c(),
        // Printer 3, and anything the fleet does not list. Written as the
        // fallback rather than as `3 =>` because an id that reached here at all
        // is one nothing should have asked about.
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

  /// The second X1C: idle, and loaded with PLA only.
  ///
  /// The filament is the point. Printer 1 is the other X1C and carries PETG,
  /// so a pipeline whose filament preset is PETG makes the class report read
  /// "1 of 2 ready" with this machine's own `filament_type_mismatch` under it —
  /// the state the per-printer breakdown exists for, and one that needs two
  /// machines of one model to reach.
  Map<String, dynamic> _statusSecondX1c() => {
        'name': 'X1 Carbon #2',
        'model': 'X1C',
        'connected': true,
        'state': 'IDLE',
        'current_print': null,
        'gcode_file': null,
        'progress': 0,
        'remaining_time': 0,
        'layer_num': 0,
        'total_layers': 0,
        'temperatures': {
          'nozzle': _r1(24.1 + _wiggle(0.3, phase: 25)),
          'nozzle_target': 0.0,
          'bed': _r1(23.9 + _wiggle(0.2, phase: 60)),
          'bed_target': 0.0,
          'chamber': _r1(25.0 + _wiggle(0.3, phase: 80)),
        },
        'cooling_fan_speed': 0,
        'big_fan1_speed': 0,
        'big_fan2_speed': 0,
        'heatbreak_fan_speed': 0,
        'speed_level': _speedLevel[5] ?? 2,
        'chamber_light': _chamberLight[5] ?? false,
        'wifi_signal': -54,
        'door_open': false,
        'ams_exists': true,
        'ams': [_amsUnitPlaOnly()],
        'vt_tray': const <Object>[],
        'tray_now': 255,
        'active_extruder': 0,
        'hms_errors': const <Object>[],
        'firmware_version': '01.08.02.00',
        'cover_url': null,
        'supports_drying': true,
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

  /// PLA in every filled slot — no PETG anywhere, which is what gives the
  /// second X1C a real filament mismatch against a PETG pipeline.
  Map<String, dynamic> _amsUnitPlaOnly() => {
        'id': 0,
        'humidity': 29,
        'temp': _r1(24.5 + _wiggle(0.4, periodSec: 380)),
        'is_ams_ht': false,
        'module_type': 'ams',
        'dry_time': 0,
        'dry_status': 0,
        'tray': [
          _tray(0, '2F4F9AFF', 'PLA',
              subBrand: 'PLA Matte', infoIdx: 'GFA01', remain: 64),
          _tray(1, 'E8E8E8FF', 'PLA',
              subBrand: 'PLA Basic', infoIdx: 'GFA00', remain: 88),
          _tray(2, null, null),
          _tray(3, null, null),
        ],
      };

  // --- Printer files (on-device storage) ---

  /// Filler standing in for a printer's file: the same size the listing claims,
  /// capped so a demo download stays a download rather than a memory test.
  ///
  /// Deliberately not a real 3MF. Demo mode fabricates the whole dataset, and
  /// what this exercises is the transfer — the progress it reports, the save
  /// dialog it ends in — not the contents, which no demo screen opens.
  Uint8List _printerFileBytes(String path, int printerId) {
    const cap = 2 * 1024 * 1024;
    final listed = _listedSize(path, printerId);
    final size = listed <= 0 ? 64 * 1024 : (listed > cap ? cap : listed);
    // A repeating pattern rather than zeroes, so a saved file is recognisably
    // this and not an empty allocation.
    return Uint8List.fromList(
      List<int>.generate(size, (i) => 0x30 + (i % 10)),
    );
  }

  /// Size the listing gives [path], or 0 when nothing lists it.
  int _listedSize(String path, int printerId) {
    final parent = path.contains('/')
        ? path.substring(0, path.lastIndexOf('/'))
        : '';
    final listing = _printerFiles(parent.isEmpty ? '/' : parent, printerId);
    final files = (listing as Map)['files'] as List;
    for (final file in files.whereType<Map>()) {
      if (file['path'] == path) return (file['size'] as int?) ?? 0;
    }
    return 0;
  }

  /// One download preparation the demo server is holding, mirroring
  /// `PrinterFilesJobStatus`.
  ///
  /// Real preparations run in the background and are polled; here the polling
  /// *is* the clock — each `GET` stages one more file — so the demo shows the
  /// counter moving and the Cancel button doing something without a timer that
  /// would keep running after the screen is gone.
  final Map<String, _DemoDownloadJob> _downloadJobs = {};

  /// Tokens minted by finished jobs, each good for exactly one download, as on
  /// the real server.
  final Map<String, _DemoDownloadJob> _downloadTokens = {};

  /// Never reused, unlike a count of live jobs: cancelling one and starting
  /// another would otherwise hand out an id a job still on the map holds.
  int _downloadJobSeq = 0;

  DemoResult _startDownloadJob(int printerId, Map<String, dynamic> body) {
    final paths = (body['paths'] as List?)?.whereType<String>().toList();
    if (paths == null || paths.isEmpty) {
      return (status: 400, body: {'detail': 'No files specified'});
    }
    final asZip = body['as_zip'] != false;
    if (!asZip && paths.length != 1) {
      return (
        status: 400,
        body: {'detail': 'Native downloads require exactly one file'},
      );
    }
    final job = _DemoDownloadJob(
      jobId: 'demo-job-${++_downloadJobSeq}',
      printerId: printerId,
      paths: paths,
      asZip: asZip,
      filename: toStringOrNull(body['filename']) ?? 'printer-files.zip',
    );
    _downloadJobs[job.jobId] = job;
    return _ok(job.toJson());
  }

  DemoResult _downloadJobRoute(String method, int printerId, String jobId) {
    final job = _downloadJobs[jobId];
    if (job == null || job.printerId != printerId) return _notFound();
    if (method == 'DELETE') {
      _downloadJobs.remove(jobId);
      _downloadTokens.remove(job.token);
      return _ok(const {'status': 'cancelled'});
    }
    if (method != 'GET') return _fallback(method);
    job.advance();
    if (job.token case final token?) _downloadTokens[token] = job;
    return _ok(job.toJson());
  }

  DemoResult _preparedDownload(int printerId, String token) {
    final job = _downloadTokens.remove(token);
    if (job == null || job.printerId != printerId) return _notFound();
    _downloadJobs.remove(job.jobId);
    return job.asZip
        ? _file(_emptyZip(), 'application/zip')
        : _file(
            _printerFileBytes(job.paths.first, printerId),
            _demoContentType(job.paths.first),
          );
  }

  /// The 22 bytes of an empty ZIP — a valid archive every tool opens, which is
  /// the honest answer for a bundle of files that do not exist.
  Uint8List _emptyZip() => Uint8List.fromList([
        0x50, 0x4B, 0x05, 0x06, // end-of-central-directory signature
        ...List<int>.filled(18, 0),
      ]);

  String _demoContentType(String path) {
    final name = path.toLowerCase();
    if (name.endsWith('.3mf')) return 'model/3mf';
    if (name.endsWith('.gcode')) return 'text/x.gcode';
    if (name.endsWith('.mp4')) return 'video/mp4';
    return 'application/octet-stream';
  }

  Object _printerFiles(String path, int printerId) {
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
            'name': 'ipcam',
            'path': '/ipcam',
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
      // The two video directories are what a print leaves behind, so they are
      // generated from the demo's own prints rather than listed by hand: the
      // file the media sheet offers for an archive is then the same file this
      // listing shows, at the same path and the same size.
      '/timelapse' => [
          for (final print in _archives)
            if (print['printer_id'] == printerId)
              ?_printVideos(print).timelapse,
        ],
      '/ipcam' => [
          for (final print in _archives)
            if (print['printer_id'] == printerId) ..._printVideos(print).ipcam,
        ],
      _ => const <Object>[],
    };
    return {'path': path, 'files': files};
  }

  /// What one demo print left on its printer's storage.
  ///
  /// Three outcomes, keyed on the print's own id so a given archive always
  /// answers the same way — between them they are every face the media sheet
  /// has, which is the point of varying it at all:
  ///
  ///  * **0** — the card has been cleared since. Nothing, and nothing to
  ///    explain: the sheet says so and offers no download.
  ///  * **1** — the whole thing: the timelapse nobody attached, plus the camera
  ///    chunks either side of the halfway mark.
  ///  * **2** — the printer's camera recording is off, so there is a timelapse
  ///    and the sheet also has to say why there are no clips.
  ({
    Map<String, dynamic>? timelapse,
    List<Map<String, dynamic>> ipcam,
    List<String> warnings,
  }) _printVideos(Map<String, dynamic> archive) {
    final started = DateTime.tryParse('${archive['started_at']}');
    final ran = archive['actual_time_seconds'];
    if (started == null || ran is! int) {
      return (timelapse: null, ipcam: const [], warnings: const []);
    }
    switch (((archive['id'] as int?) ?? 0) % 3) {
      case 0:
        return (timelapse: null, ipcam: const [], warnings: const []);
      case 2:
        return (
          timelapse: _video(started, 'timelapse'),
          ipcam: const [],
          warnings: const ['ipcam_unavailable'],
        );
      default:
        return (
          timelapse: _video(started, 'timelapse'),
          ipcam: [
            for (var i = 0; i < 2; i++)
              _video(started.add(Duration(seconds: ran ~/ 2 * i)), 'ipcam'),
          ],
          warnings: const [],
        );
    }
  }

  /// One recording, named the way a printer names them: `<kind>_<stamp>.mp4`
  /// under the directory of its kind.
  Map<String, dynamic> _video(DateTime at, String kind) {
    final name = '${kind == 'ipcam' ? 'ipcam' : 'video'}_${_stamp(at)}.mp4';
    return {
      'name': name,
      'path': '/$kind/$name',
      'is_directory': false,
      // Roughly what a printer writes: a rendered timelapse is a few tens of
      // megabytes, a camera chunk a few.
      'size': kind == 'ipcam' ? 6_291_456 : 18_446_592,
      'mtime': _iso(at),
      'kind': kind,
    };
  }

  /// `YYYYMMDD_HHMMSS`, the shape a printer stamps its recordings with.
  String _stamp(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.year}${two(at.month)}${two(at.day)}_'
        '${two(at.hour)}${two(at.minute)}${two(at.second)}';
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
    List<Map<String, dynamic>> variants = const [],
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
        // Non-empty only for a cross-model job: the candidates the scheduler
        // may pick between, in priority order (server #671).
        'variants': variants,
      };

  DemoResult? _queueRoute(String m, List<String> s, Map<String, dynamic> body) {
    if (s.length == 1) {
      if (m == 'GET') return _ok(_queue);
      if (m == 'POST') {
        // A cross-model job names itself after its first candidate and carries
        // the rest; anything else is an "add from archive" (reprint).
        final variantIds = [
          for (final v in (body['variants'] as List?)?.whereType<Map>() ??
              const <Map>[])
            v['library_file_id'] as int?,
        ].nonNulls.toList();
        final variantFiles = [
          for (final id in variantIds)
            ..._libraryFiles.where((f) => f['id'] == id),
        ];
        final archive = _archives
            .where((a) => a['id'] == body['archive_id'])
            .firstOrNull;
        final lead = variantFiles.firstOrNull;
        _queue.add(_queueItem(
          id: _nextQueueId++,
          printerId: body['printer_id'] as int?,
          position: _queue.length + 1,
          name: (lead?['print_name'] as String?) ??
              (archive?['print_name'] as String?) ??
              'Reprint',
          status: 'pending',
          timeSec: (lead?['print_time_seconds'] as int?) ??
              (archive?['print_time_seconds'] as int?) ??
              3600,
          grams: (lead?['filament_used_grams'] as num?)?.toDouble() ??
              (archive?['filament_used_grams'] as num?)?.toDouble() ??
              20,
          type: (archive?['filament_type'] as String?) ?? 'PLA',
          color: (archive?['filament_color'] as String?) ?? '#808080',
          createdDaysAgo: 0,
          gcodeInjection: body['gcode_injection'] == true,
          slicedForModel: '${lead?['sliced_for_model'] ?? 'X1C'}',
          variants: [
            for (final (position, f) in variantFiles.indexed)
              {
                'library_file_id': f['id'],
                'filename': f['filename'],
                'target_model': f['sliced_for_model'],
                'position': position,
              },
          ],
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
      int? plateId,
      // What the run actually drew — what the print log stores and every
      // statistic sums, as against the whole-file estimate in [grams]. The two
      // are the same figure for a print that ran to the end without a tracked
      // spool, which is the usual case and the default here. [actualGrams] is
      // for one that stopped partway; [noUsageRecorded] for one that stopped
      // before it drew anything, where the server keeps no figure at all rather
      // than a zero.
      double? actualGrams,
      bool noUsageRecorded = false,
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
        'plate_id': plateId,
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
        'total_filament_actual_grams':
            noUsageRecorded ? null : (actualGrams ?? grams),
        'successful_run_count': status == 'completed' ? 1 : 0,
        'failed_run_count': status == 'failed' ? 1 : 0,
      };
    }

    return [
      // The one multi-plate print in the demo: without it the plate line on the
      // detail sheet and the plate picker in the print form have nothing to
      // stand on, and both are part of what the demo is showing off.
      a('Drawer organizer x4', 1, 1,
          estSec: 5400, grams: 96.2, color: '#000000', plateId: 2),
      a('Benchy', 1, 2, estSec: 3540, grams: 15.8, color: '#FF6A13'),
      a('Raspberry Pi 5 case', 2, 3,
          estSec: 7920, grams: 48.4, type: 'PETG', color: '#FFFFFF'),
      a('Headphone hook', 1, 4, estSec: 4260, grams: 31.7, color: '#3B3B3B'),
      a('Spiral vase', 2, 6,
          estSec: 10680, grams: 88.1, color: '#D4AF37',
          status: 'failed', failureReason: 'Spaghetti detected',
          actualGrams: 35.2),
      a('Cable clips x8', 1, 7,
          estSec: 5520, grams: 42.3, type: 'PETG', color: '#FFFFFF', quantity: 8),
      a('Plant pot 120mm', 2, 9, estSec: 12480, grams: 132.5, color: '#0ACCB8'),
      a('SD card holder', 1, 12, estSec: 3120, grams: 22.9, color: '#FF6A13'),
      a('Phone stand', 3, 15, estSec: 8340, grams: 68.9, color: '#FF6A13'),
      // Stopped on the first layer, so there is no measured figure at all —
      // the case the archive sheet has a line for.
      a('Wall hook x4', 1, 18,
          estSec: 4980, grams: 38.2, type: 'PETG', color: '#FFFFFF',
          status: 'failed', failureReason: 'Bed adhesion',
          noUsageRecorded: true),
      a('Desk drawer divider', 2, 22, estSec: 9840, grams: 104.6, color: '#000000'),
      a('Flexi dragon', 1, 26,
          estSec: 14400, grams: 156.3, type: 'TPU', color: '#0ACC38'),
    ];
  }

  // --- Print log ---

  /// One row per run, built from the archives plus the runs whose archive is
  /// gone — the orphans are the half of this table nothing else in the app can
  /// reach, so the demo would misrepresent the screen without them.
  ///
  /// Carries `cost` / `energy_kwh` / `energy_cost` because the reported version
  /// is 1.2.6, which sends them (server #2636). The archives already hold both
  /// figures, so a run reads the same here as it does in the statistics.
  late final List<Map<String, dynamic>> _printLog = _buildPrintLog();

  List<Map<String, dynamic>> _buildPrintLog() {
    var id = 900;
    Map<String, dynamic> row(
      Map<String, dynamic> archive, {
      String? failureReason,
    }) =>
        {
          'id': id++,
          'archive_id': archive['id'],
          'print_name': archive['print_name'],
          'printer_name': _printerName(archive['printer_id'] as int?),
          'printer_id': archive['printer_id'],
          'status': archive['status'],
          'started_at': archive['started_at'],
          'completed_at': archive['completed_at'],
          'duration_seconds': archive['actual_time_seconds'],
          'filament_type': archive['filament_type'],
          'filament_color': archive['filament_color'],
          // The run's own figure, not the file's estimate — the same
          // distinction the server keeps, and what makes the archive sheet's
          // second line agree with this table.
          'filament_used_grams': archive['total_filament_actual_grams'],
          'cost': archive['cost'],
          'energy_kwh': archive['energy_kwh'],
          'energy_cost': archive['energy_cost'],
          'failure_reason': failureReason ?? archive['failure_reason'],
          'thumbnail_path': null,
          'created_by_id': 1,
          'created_by_username': DemoConfig.username,
          'created_at': archive['created_at'],
        };

    Map<String, dynamic> orphan(
      String name,
      int printerId,
      int daysAgo, {
      required String status,
      String? failureReason,
      int durationSeconds = 1800,
      double? energyKwh,
    }) {
      final started = _daysAgo(daysAgo, hours: 5);
      return {
        'id': id++,
        // The archive is gone; the run survived it (`ON DELETE SET NULL`).
        'archive_id': null,
        'print_name': name,
        'printer_name': _printerName(printerId),
        'printer_id': printerId,
        'status': status,
        'started_at': _iso(started),
        'completed_at': _iso(started.add(Duration(seconds: durationSeconds))),
        'duration_seconds': durationSeconds,
        'filament_type': 'PLA',
        'filament_color': '#0ACCB8',
        'filament_used_grams': 18.4,
        'cost': _r1(18.4 * 0.025),
        // A run on a printer with a smart plug behind it. The orphan below is
        // deliberately left without one — a null there is "no plug", and the
        // screen has to read differently from a zero.
        'energy_kwh': energyKwh,
        'energy_cost': energyKwh == null ? null : _r1(energyKwh * 0.3),
        'failure_reason': failureReason,
        'thumbnail_path': null,
        'created_by_id': null,
        'created_by_username': null,
        'created_at': _iso(started),
      };
    }

    return [
      // Newest first, the order the server sorts by.
      orphan('Bracket v3 (deleted archive)', 1, 0,
          status: 'failed', failureReason: 'cloggedNozzle', energyKwh: 0.06),
      for (final a in _archives) row(a),
      orphan('Test cube', 2, 30, status: 'cancelled', durationSeconds: 420),
    ];
  }

  String? _printerName(int? printerId) {
    for (final p in _printers) {
      if (p['id'] == printerId) return '${p['name']}';
    }
    return null;
  }

  /// Mirrors `print_log.py::_FAILURE_REASON_KEYS` / `_STATUS_KEYS` — the demo
  /// refuses what the real server refuses, or the editor would look like it
  /// accepts anything.
  static const _printLogReasons = {
    '',
    'adhesionFailure',
    'spaghettiDetached',
    'layerShift',
    'cloggedNozzle',
    'filamentRunout',
    'warping',
    'stringing',
    'underExtrusion',
    'powerFailure',
    'userCancelled',
    'other',
  };
  static const _printLogStatuses = {
    'completed',
    'failed',
    'stopped',
    'cancelled',
    'skipped',
  };

  DemoResult? _printLogRoute(
    String m,
    List<String> s,
    Map<String, String> q,
    Map<String, dynamic> body,
  ) {
    if (s.length == 1) {
      if (m == 'GET') {
        final matched = _sortPrintLog(_filterPrintLog(q), q);
        final offset = int.tryParse(q['offset'] ?? '') ?? 0;
        final limit = int.tryParse(q['limit'] ?? '') ?? 50;
        final page = offset >= matched.length
            ? const <Map<String, dynamic>>[]
            : matched.sublist(offset, math.min(offset + limit, matched.length));
        return _ok({'items': page, 'total': matched.length});
      }
      if (m == 'DELETE') {
        // Clears every row, ignoring the filters above — as the route does.
        final deleted = _printLog.length;
        _printLog.clear();
        return _ok({'deleted': deleted});
      }
      return _fallback(m);
    }

    final entryId = int.tryParse(s[1]);
    final entry = _printLog.where((e) => e['id'] == entryId).firstOrNull;
    if (s.length >= 3 && s[2] == 'thumbnail') return _notFound();
    if (entry == null) return _notFound();

    if (m == 'DELETE') {
      _printLog.remove(entry);
      return _ok({'status': 'deleted', 'id': entryId});
    }
    if (m == 'PATCH') {
      if (body.containsKey('failure_reason')) {
        final reason = '${body['failure_reason'] ?? ''}';
        if (!_printLogReasons.contains(reason)) {
          return (
            status: 400,
            body: {'detail': "Unknown failure_reason: '$reason'"},
          );
        }
        entry['failure_reason'] = reason.isEmpty ? null : reason;
      }
      if (body['status'] != null) {
        final status = '${body['status']}';
        if (!_printLogStatuses.contains(status)) {
          return (status: 400, body: {'detail': "Unknown status: '$status'"});
        }
        entry['status'] = status;
      }
      return _ok(entry);
    }
    return _fallback(m);
  }

  /// Orders a filtered log the way `_SORTABLE_COLUMNS` does, nulls last in both
  /// directions.
  ///
  /// Served rather than ignored because the app only shows the sort control on
  /// a server that honours it — a demo that took the parameters and returned
  /// the same order would be exactly the silent drop the version gate exists to
  /// avoid.
  List<Map<String, dynamic>> _sortPrintLog(
    List<Map<String, dynamic>> rows,
    Map<String, String> q,
  ) {
    final column = q['sort_by'];
    if (column == null) return rows;
    Comparable<Object>? key(Map<String, dynamic> e) => switch (column) {
          'date' => '${e['started_at'] ?? e['created_at']}',
          'print_name' => '${e['print_name'] ?? ''}'.toLowerCase(),
          'printer' => '${e['printer_name'] ?? ''}'.toLowerCase(),
          'user' => '${e['created_by_username'] ?? ''}'.toLowerCase(),
          'status' => '${e['status']}',
          'duration' => e['duration_seconds'] as int?,
          'completed_at' => e['completed_at'] as String?,
          'filament' => '${e['filament_type'] ?? ''}',
          'filament_used' => (e['filament_used_grams'] as num?)?.toDouble(),
          'cost' => (e['cost'] as num?)?.toDouble(),
          'energy' => (e['energy_kwh'] as num?)?.toDouble(),
          'energy_cost' => (e['energy_cost'] as num?)?.toDouble(),
          _ => null,
        };
    final descending = q['sort_dir'] != 'asc';
    final sorted = [...rows]..sort((a, b) {
        final ka = key(a);
        final kb = key(b);
        // Nulls last whichever way the column is pointing, as the server does:
        // an empty column must not bury the rows that do have a value.
        if (ka == null) return kb == null ? 0 : 1;
        if (kb == null) return -1;
        final cmp = ka.compareTo(kb as Object);
        return descending ? -cmp : cmp;
      });
    return sorted;
  }

  /// A `date_from` / `date_to` query value as the instant it means.
  ///
  /// The app sends those without a zone marker on purpose — the real server's
  /// columns are naive UTC and a tz-aware bind param compares against them
  /// differently per database. Dart reads a zoneless string as **local**, so
  /// taking it as written moved the filter boundary by the device's offset
  /// against the demo's own timestamps, which are tagged UTC.
  static DateTime? _utcQueryInstant(String? value) {
    if (value == null || value.isEmpty) return null;
    final zoned = RegExp(r'([Zz]|[+-]\d{2}:?\d{2})$').hasMatch(value);
    return DateTime.tryParse(zoned ? value : '${value}Z');
  }

  List<Map<String, dynamic>> _filterPrintLog(Map<String, String> q) {
    final search = (q['search'] ?? '').toLowerCase();
    final printerId = int.tryParse(q['printer_id'] ?? '');
    final status = q['status'];
    final username = q['created_by_username'];
    final from = _utcQueryInstant(q['date_from']);
    final to = _utcQueryInstant(q['date_to']);
    return _printLog.where((e) {
      if (search.isNotEmpty &&
          !'${e['print_name'] ?? ''}'.toLowerCase().contains(search)) {
        return false;
      }
      if (printerId != null && e['printer_id'] != printerId) return false;
      if (status != null && e['status'] != status) return false;
      if (username != null && e['created_by_username'] != username) {
        return false;
      }
      final created = DateTime.tryParse('${e['created_at']}');
      if (created == null) return true;
      if (from != null && created.isBefore(from)) return false;
      if (to != null && created.isAfter(to)) return false;
      return true;
    }).toList();
  }

  DemoResult? _archivesRoute(
    String m,
    List<String> s,
    Map<String, String> q,
    Map<String, dynamic> body,
  ) {
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
          return _ok({
            'has_model': false,
            'has_gcode': true,
            // Only the one archive kept the project file it was sliced from,
            // which is the whole of what `sliceable` asks about — every other
            // demo archive is a plain `gcode.3mf` print output, and the server
            // answers false for those too.
            'has_source': aid == _sliceableArchiveId,
          });
        }
        if (s.length >= 3 && s[2] == 'slice' && m == 'POST') {
          if (aid != _sliceableArchiveId) {
            return (
              status: 400,
              body: {'detail': 'Archive has no source file to slice'},
            );
          }
          return _startSlice(isArchive: true, source: archive, body: body);
        }
        if (s.length >= 3 && s[2] == 'filament-requirements') {
          return _ok(_archiveFilaments(archive));
        }
        if (s.length >= 3 && s[2] == 'plates') {
          return _ok(_demoPlates(archive));
        }
        if (s.length == 3 && s[2] == 'printer-media' && m == 'GET') {
          return _ok(_archiveMedia(archive));
        }
        if (s.length == 2 && m == 'GET') return _ok(archive);
        // The demo stands in for a current server, so it knows the key and
        // answers with the row as stored — which is what tells the app the
        // edit landed. `containsKey`, not a null check: a present null is how
        // the weight is cleared.
        if (s.length == 2 && m == 'PATCH') {
          if (body.containsKey('filament_used_grams')) {
            archive['filament_used_grams'] = body['filament_used_grams'];
          }
          return _ok(archive);
        }
      }
    }
    return _fallback(m);
  }

  /// Recordings the demo offers for one print.
  ///
  /// No `local_timelapse` and no photos on any demo archive: both would be
  /// rows that open a viewer, and a viewer loads its image or video straight
  /// over the network — which in demo mode goes to `http://demo` and resolves
  /// nowhere. So the demo shows the half it can actually serve, and the
  /// printer half is the new one anyway.
  ///
  /// The files come from [_printVideos], the same generator the printer's own
  /// `/timelapse` and `/ipcam` listings use, so what the sheet offers here can
  /// be found in the file manager at the same path and the same size.
  Map<String, dynamic> _archiveMedia(Map<String, dynamic> archive) {
    final printerId = archive['printer_id'];
    if (printerId == null) {
      return {
        'archive_id': archive['id'],
        'printer_id': null,
        'local_timelapse': null,
        'remote_files': const <Object>[],
        'warnings': const <String>[],
      };
    }
    final videos = _printVideos(archive);
    return {
      'archive_id': archive['id'],
      'printer_id': printerId,
      'local_timelapse': null,
      'remote_files': [?videos.timelapse, ...videos.ipcam],
      'warnings': videos.warnings,
    };
  }

  /// Plates of a demo archive. Three for the one print that carries a
  /// `plate_id`, one for everything else — a single-plate answer is what the
  /// picker reads as "nothing to choose", which is the state most prints are in.
  Map<String, dynamic> _demoPlates(Map<String, dynamic> archive) {
    final multi = archive['plate_id'] != null;
    final grams = (archive['filament_used_grams'] as num).toDouble();
    final seconds = archive['print_time_seconds'] as int;
    final count = multi ? 3 : 1;
    return {
      'archive_id': archive['id'],
      'filename': archive['filename'],
      'plates': [
        for (var i = 1; i <= count; i++)
          {
            'index': i,
            'name': null,
            'objects': <String>[],
            'object_count': i,
            'has_thumbnail': false,
            'thumbnail_url': null,
            'print_time_seconds': (seconds / count).round(),
            'filament_used_grams': _r1(grams / count),
            'filaments': <Object>[],
            'bed_type': archive['bed_type'],
          },
      ],
      'is_multi_plate': multi,
      'has_gcode': true,
      'embedded_printer': null,
      'embedded_process': null,
      'design_overrides': <Object>[],
    };
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
      // Coerced, not cast: a re-sliced archive has never run, so the fields a
      // completed print fills are null on it — and the server sends that row
      // in the same list as every other.
      hours += toDouble(a['actual_time_seconds']) / 3600;
      grams += toDouble(a['filament_used_grams']);
      cost += toDouble(a['cost']);
      kwh += toDouble(a['energy_kwh']);
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

  /// `/location-ha-sensors/` — the Home Assistant sensors bound to a storage
  /// location. Read-only here as in the app: the demo has no Home Assistant to
  /// pick an entity from.
  ///
  /// Bound to "Dry box" (location 3), the one demo location the reading is
  /// about, and the three rows cover the three states the pills draw
  /// differently: a plain reading, one over its threshold, and one the poller
  /// could not reach.
  static const _locationSensors = [
    {
      'id': 1,
      'location_id': 3,
      'name': 'Temperature',
      'entity_id': 'sensor.dry_box_temperature',
      'kind': 'numeric',
      'device_class': 'temperature',
      'unit': '°C',
      'show_on_card': true,
      'sort_order': 0,
    },
    {
      'id': 2,
      'location_id': 3,
      'name': 'Humidity',
      'entity_id': 'sensor.dry_box_humidity',
      'kind': 'numeric',
      'device_class': 'humidity',
      'unit': '%',
      'alert_above': 45.0,
      'show_on_card': true,
      'sort_order': 1,
    },
    {
      'id': 3,
      'location_id': 3,
      'name': 'Battery',
      'entity_id': 'sensor.dry_box_battery',
      'kind': 'numeric',
      'device_class': 'battery',
      'unit': '%',
      'show_on_card': true,
      'sort_order': 2,
    },
  ];

  List<Map<String, dynamic>> _locationSensorReadings(int locationId) => [
        for (final sensor in _locationSensors)
          if (sensor['location_id'] == locationId)
            {
              ...sensor,
              'state': switch (sensor['id']) {
                1 => '24.4',
                2 => '47.2',
                _ => '78',
              },
              'value': switch (sensor['id']) {
                1 => 24.4,
                2 => 47.2,
                _ => 78.0,
              },
              'alerting': sensor['id'] == 2,
              // The battery sensor is the one the demo leaves unreachable, so
              // its last value is shown under the struck-through sensor icon
              // instead of passing for a current one.
              'reachable': sensor['id'] != 3,
              'last_changed': _iso(_minutesAgo(sensor['id'] == 3 ? 240 : 6)),
            },
      ];

  // --- Slicer pipelines + runs ---

  /// The saved bundles, seeded on first read.
  ///
  /// Two, chosen for the two states the screen has to show: one fully targeted
  /// at the X1C **class** (which is why the fleet carries two X1Cs), and one
  /// with no target at all — what every pipeline saved from the slice form
  /// looks like, and the only way to reach the amber "set a target" line and
  /// the edit screen behind it.
  List<Map<String, dynamic>> get _pipelines =>
      _pipelinesStore ??= [
        {
          'id': 1,
          'name': 'Gridfinity PETG',
          'description': 'Bins and baseplates, 0.20mm, engineering plate.',
          'printer_preset': {'source': 'local', 'id': 'p-x1c-04'},
          'process_preset': {'source': 'local', 'id': 'q-020-std'},
          'filament_presets': [
            {'source': 'local', 'id': 'f-petg-white'},
          ],
          'bed_type': 'Engineering Plate',
          'target_kind': 'printer_class',
          'target_printer_id': null,
          'target_model_class': 'X1C',
          'fanout_strategy': 'max_parallel',
          'created_by': 1,
          'created_at': _iso(_daysAgo(21)),
          'updated_at': _iso(_daysAgo(3)),
        },
        {
          'id': 2,
          'name': 'Nightly ASA brackets',
          'description': null,
          'printer_preset': {'source': 'local', 'id': 'p-x1c-04'},
          'process_preset': {'source': 'local', 'id': 'q-028-draft'},
          'filament_presets': [
            {'source': 'local', 'id': 'f-asa-black'},
          ],
          'bed_type': null,
          // Untargeted, as `SlicerPipelineCreate` leaves every new bundle: the
          // create schema declares none of these four fields.
          'target_kind': 'printer_class',
          'target_printer_id': null,
          'target_model_class': null,
          'fanout_strategy': 'max_parallel',
          'created_by': 1,
          'created_at': _iso(_daysAgo(2)),
          'updated_at': _iso(_daysAgo(2)),
        },
      ];

  /// `/slicer-pipelines` — CRUD, the pre-flight, and dispatch.
  DemoResult? _pipelineRoute(
    String m,
    List<String> s,
    Map<String, dynamic> body,
  ) {
    if (s.length == 1) {
      if (m == 'GET') return _ok({'pipelines': _pipelines});
      if (m == 'POST') {
        // Only the bundle: the real create schema declares no target fields and
        // Pydantic drops what it does not declare, so echoing them back would
        // tell the app a write happened that did not.
        final row = <String, dynamic>{
          'id': _nextPipelineId++,
          'name': '${body['name'] ?? 'Pipeline'}'.trim(),
          'description': body['description'],
          'printer_preset': body['printer_preset'],
          'process_preset': body['process_preset'],
          'filament_presets': body['filament_presets'] ?? const <Object>[],
          'bed_type': body['bed_type'],
          'target_kind': 'printer_class',
          'target_printer_id': null,
          'target_model_class': null,
          'fanout_strategy': 'max_parallel',
          'created_by': 1,
          'created_at': _iso(DateTime.now()),
          'updated_at': _iso(DateTime.now()),
        };
        _pipelines.insert(0, row);
        return (status: 201, body: row);
      }
      return _fallback(m);
    }

    final pipelineId = int.tryParse(s[1]);
    if (pipelineId == null) return _notFound();
    final row = _pipelines.where((p) => p['id'] == pipelineId).firstOrNull;

    if (s.length == 2) {
      if (row == null) return _notFound();
      if (m == 'GET') return _ok(row);
      if (m == 'PUT') {
        // Field by field under an `is not None` guard, like the real route: a
        // key the caller omitted and a key sent as null are the same request,
        // which is why the app clears a target with the sentinels below.
        for (final key in const [
          'name',
          'description',
          'printer_preset',
          'process_preset',
          'filament_presets',
          'bed_type',
          'target_kind',
          'fanout_strategy',
        ]) {
          if (body[key] != null) row[key] = body[key];
        }
        // `0` clears the pinned printer and `''` clears the class — the two
        // sentinels the API defines, because null cannot reach the column.
        if (body['target_printer_id'] != null) {
          row['target_printer_id'] =
              body['target_printer_id'] == 0 ? null : body['target_printer_id'];
        }
        if (body['target_model_class'] != null) {
          final asked = '${body['target_model_class']}';
          row['target_model_class'] = asked.isEmpty ? null : asked;
        }
        row['updated_at'] = _iso(DateTime.now());
        return _ok(row);
      }
      if (m == 'DELETE') {
        // Soft, like the server: the row leaves the listing and every run that
        // referenced it keeps its name.
        _pipelines.remove(row);
        return (status: 204, body: null);
      }
      return _fallback(m);
    }

    if (s.length == 3 && m == 'POST' && s[2] == 'check-eligibility') {
      if (row == null) return _notFound();
      return _ok(_eligibility(row));
    }
    if (s.length == 3 && m == 'POST' && s[2] == 'run') {
      if (row == null) return _notFound();
      return _startRun(row, body);
    }
    if (s.length == 3 && m == 'GET' && s[2] == 'runs') {
      return _ok({
        'runs': [
          for (final r in _pipelineRuns)
            if (r['pipeline_id'] == pipelineId) r,
        ],
        'total': _pipelineRuns.where((r) => r['pipeline_id'] == pipelineId).length,
      });
    }
    return _fallback(m);
  }

  /// The pre-flight, computed against the fleet rather than fabricated.
  ///
  /// A class target enumerates every printer whose `model` matches and reports
  /// each one; the specific-printer path answers for that one machine in
  /// `issues` and sends no `printer_reports`, which is the split the real
  /// matcher makes.
  Map<String, dynamic> _eligibility(Map<String, dynamic> pipeline) {
    final kind = '${pipeline['target_kind']}';
    final wanted = _pipelineFilamentType(pipeline);

    if (kind == 'specific_printer') {
      final id = pipeline['target_printer_id'];
      if (id == null) {
        return {
          'ok': false,
          'target_kind': kind,
          'issues': [
            {'kind': 'printer_not_set'},
          ],
          'printer_reports': const <Object>[],
        };
      }
      final printer = _printers.where((p) => p['id'] == id).firstOrNull;
      if (printer == null) {
        return {
          'ok': false,
          'target_kind': kind,
          'target_printer_id': id,
          'issues': [
            {'kind': 'printer_not_found'},
          ],
          'printer_reports': const <Object>[],
        };
      }
      final issues = _printerIssues(printer, wanted);
      return {
        'ok': issues.isEmpty,
        'target_kind': kind,
        'target_printer_id': id,
        'target_printer_name': printer['name'],
        'issues': issues,
        'printer_reports': const <Object>[],
      };
    }

    final modelClass = pipeline['target_model_class'];
    if (modelClass == null) {
      return {
        'ok': false,
        'target_kind': kind,
        'issues': [
          {'kind': 'class_not_set'},
        ],
        'printer_reports': const <Object>[],
      };
    }
    final candidates =
        _printers.where((p) => p['model'] == modelClass).toList();
    if (candidates.isEmpty) {
      return {
        'ok': false,
        'target_kind': kind,
        'target_model_class': modelClass,
        'issues': [
          {'kind': 'no_class_matches'},
        ],
        'printer_reports': const <Object>[],
      };
    }
    final reports = [
      for (final p in candidates)
        {
          'printer_id': p['id'],
          'printer_name': p['name'],
          'ok': _printerIssues(p, wanted).isEmpty,
          'issues': _printerIssues(p, wanted),
        },
    ];
    return {
      'ok': reports.any((r) => r['ok'] == true),
      'target_kind': kind,
      'target_model_class': modelClass,
      // Empty on the class path, exactly as the matcher leaves it: every
      // problem belongs to a printer, so pooling them here would lose which.
      'issues': const <Object>[],
      'printer_reports': reports,
    };
  }

  /// What the pipeline's first filament slot asks for, by type.
  String? _pipelineFilamentType(Map<String, dynamic> pipeline) {
    final slots = pipeline['filament_presets'];
    if (slots is! List || slots.isEmpty) return null;
    final first = slots.first;
    if (first is! Map) return null;
    final filaments = (_slicerPresets['local']?['filament'] ?? const []) as List;
    for (final preset in filaments) {
      if (preset is Map && preset['id'] == first['id']) {
        return preset['filament_type'] as String?;
      }
    }
    return null;
  }

  /// One printer measured against a wanted filament type — offline first,
  /// because a machine that cannot be reached says nothing about its trays.
  List<Map<String, dynamic>> _printerIssues(
    Map<String, dynamic> printer,
    String? wantedType,
  ) {
    final id = printer['id'] as int;
    if (printer['is_active'] != true) {
      return [
        {'kind': 'printer_disabled'},
      ];
    }
    final status = statusData(id);
    if (status['connected'] != true) {
      return [
        {'kind': 'printer_offline'},
      ];
    }
    if (wantedType == null) return [];
    final loaded = <String>[];
    for (final unit in (status['ams'] as List? ?? const [])) {
      if (unit is! Map) continue;
      for (final tray in (unit['tray'] as List? ?? const [])) {
        if (tray is Map && tray['tray_type'] is String) {
          loaded.add(tray['tray_type'] as String);
        }
      }
    }
    if (loaded.contains(wantedType)) return [];
    return [
      {
        'kind': 'filament_type_mismatch',
        'slot_index': 0,
        'expected': wantedType,
        'actual': loaded.isEmpty ? null : loaded.first,
      },
    ];
  }

  /// `POST /{id}/run` — 409 with the report when the pre-flight blocks and the
  /// caller did not force, otherwise a 202 and a live run.
  DemoResult _startRun(Map<String, dynamic> pipeline, Map<String, dynamic> body) {
    final report = _eligibility(pipeline);
    final forced = body['force'] == true;
    if (report['ok'] != true && !forced) {
      return (status: 409, body: {'detail': report});
    }
    final copies = (body['copies'] as num?)?.toInt() ?? 1;
    final assigned = _pipelineAssignments(pipeline, copies);
    final run = <String, dynamic>{
      'id': _nextPipelineRunId++,
      'pipeline_id': pipeline['id'],
      'pipeline_name': pipeline['name'],
      'source_library_file_id': body['source_library_file_id'],
      'source_archive_id': body['source_archive_id'],
      'source_filename': _pipelineSourceName(body),
      'parent_run_id': null,
      'copies': copies,
      // Dispatching, with nothing finished: the demo has no clock a printer
      // answers to, so a fresh run stays here — which is the state the screen's
      // poll exists for, and the one Cancel acts on.
      'status': 'dispatching',
      'slice_job_id': _nextPipelineRunId,
      'sliced_library_file_id': null,
      'eligibility_overridden': forced && report['ok'] != true,
      'error_message': null,
      'created_by': 1,
      'created_at': _iso(DateTime.now()),
      'started_at': _iso(DateTime.now()),
      'completed_at': null,
      'jobs': [
        for (var i = 0; i < copies; i++)
          {
            'id': _nextPipelineJobId++,
            'pipeline_run_id': _nextPipelineRunId - 1,
            'copy_index': i,
            'assigned_printer_id': assigned[i].$1,
            'assigned_printer_name': assigned[i].$2,
            'queue_entry_id': null,
            'status': 'queued',
            'error_message': null,
            'dispatched_at': _iso(DateTime.now()),
            'completed_at': null,
          },
      ],
      'target_kind': pipeline['target_kind'],
      'target_printer_id': pipeline['target_printer_id'],
      'target_model_class': pipeline['target_model_class'],
      'fanout_strategy': pipeline['fanout_strategy'],
    };
    _pipelineRuns.insert(0, run);
    return (status: 202, body: run);
  }

  /// Which printer each copy went to, per the pipeline's fanout strategy.
  ///
  /// `max_parallel` pins nothing — the real scheduler hands each queue item to
  /// whichever matching printer frees up first, so the copy has no printer name
  /// until it does.
  List<(int?, String?)> _pipelineAssignments(
    Map<String, dynamic> pipeline,
    int copies,
  ) {
    if (pipeline['target_kind'] == 'specific_printer') {
      final id = pipeline['target_printer_id'] as int?;
      final name =
          _printers.where((p) => p['id'] == id).firstOrNull?['name'] as String?;
      return [for (var i = 0; i < copies; i++) (id, name)];
    }
    final candidates = _printers
        .where((p) => p['model'] == pipeline['target_model_class'])
        .toList();
    return switch ('${pipeline['fanout_strategy']}') {
      'round_robin' => [
          for (var i = 0; i < copies; i++)
            candidates.isEmpty
                ? (null, null)
                : (
                    candidates[i % candidates.length]['id'] as int,
                    candidates[i % candidates.length]['name'] as String,
                  ),
        ],
      'fill_one_first' => [
          for (var i = 0; i < copies; i++)
            candidates.isEmpty
                ? (null, null)
                : (
                    candidates.first['id'] as int,
                    candidates.first['name'] as String,
                  ),
        ],
      _ => [for (var i = 0; i < copies; i++) (null, null)],
    };
  }

  String? _pipelineSourceName(Map<String, dynamic> body) {
    final libraryId = body['source_library_file_id'];
    if (libraryId != null) {
      return _libraryFiles.where((f) => f['id'] == libraryId).firstOrNull?['filename']
          as String?;
    }
    final archiveId = body['source_archive_id'];
    if (archiveId == null) return null;
    final archive = _archives.where((a) => a['id'] == archiveId).firstOrNull;
    return (archive?['print_name'] ?? archive?['filename']) as String?;
  }

  /// The run history, seeded on first read.
  ///
  /// Four hand-written runs for the four states the card renders differently,
  /// then filler so `total` passes the 25-row page and the paginator is
  /// reachable at all:
  ///
  /// * one **in flight** across both X1Cs — the progress bar, per-copy rows and
  ///   Cancel;
  /// * one **partial failure** with a copy to re-attempt — Retry;
  /// * one partial failure whose **source has been deleted** (both source ids
  ///   null, as `ondelete="SET NULL"` leaves them) — the run that must *not*
  ///   offer Retry, because the server would answer 400;
  /// * one **failed at the slice**, carrying the error the card shows.
  List<Map<String, dynamic>> get _pipelineRuns =>
      _pipelineRunsStore ??= [
        _runRow(
          id: 91,
          status: 'in_progress',
          copies: 4,
          jobStatuses: const ['completed', 'printing', 'queued', 'queued'],
          printerIds: const [1, 5, null, null],
          minutesAgo: 26,
        ),
        _runRow(
          id: 90,
          status: 'partial_failure',
          copies: 3,
          jobStatuses: const ['completed', 'failed', 'completed'],
          printerIds: const [1, 5, 1],
          minutesAgo: 190,
          completed: true,
        ),
        _runRow(
          id: 89,
          status: 'partial_failure',
          copies: 2,
          jobStatuses: const ['completed', 'failed'],
          printerIds: const [1, 5],
          minutesAgo: 1450,
          completed: true,
          sourceGone: true,
        ),
        _runRow(
          id: 88,
          status: 'failed',
          copies: 2,
          jobStatuses: const ['failed', 'failed'],
          printerIds: const [null, null],
          minutesAgo: 2880,
          completed: true,
          error: 'Slicing failed: filament preset is not compatible with the '
              'selected printer',
        ),
        // Filler: enough finished runs that the list crosses one page, so
        // "load more" and the row count under it are reachable.
        for (var i = 0; i < 26; i++)
          _runRow(
            id: 62 - i,
            status: 'completed',
            copies: 1,
            jobStatuses: const ['completed'],
            printerIds: const [1],
            minutesAgo: 4320 + i * 180,
            completed: true,
          ),
      ];

  /// One run row, with the roll-up counted from the per-copy statuses the way
  /// `_materialise_run` counts it — so the card's progress and the numbers
  /// under it cannot disagree.
  Map<String, dynamic> _runRow({
    required int id,
    required String status,
    required int copies,
    required List<String> jobStatuses,
    required List<int?> printerIds,
    required int minutesAgo,
    bool completed = false,
    bool sourceGone = false,
    String? error,
  }) {
    final created = _minutesAgo(minutesAgo);
    int count(String s) => jobStatuses.where((j) => j == s).length;
    return {
      'id': id,
      'pipeline_id': 1,
      'pipeline_name': 'Gridfinity PETG',
      // File 6 is the demo library's only un-sliced `.3mf` — the one thing in
      // it a pipeline could actually re-slice. Its name is read back rather
      // than repeated so the two cannot drift.
      'source_library_file_id': sourceGone ? null : _pipelineSourceFileId,
      'source_archive_id': null,
      'source_filename': sourceGone
          ? null
          : _libraryFiles
              .where((f) => f['id'] == _pipelineSourceFileId)
              .firstOrNull?['filename'],
      'parent_run_id': null,
      'copies': copies,
      'copies_completed': count('completed'),
      'copies_failed': count('failed'),
      'copies_cancelled': count('cancelled'),
      'copies_in_progress': count('printing') + count('queued'),
      'status': status,
      'slice_job_id': 400 + id,
      'sliced_library_file_id': sourceGone ? null : 1,
      'eligibility_overridden': id == 90,
      'error_message': error,
      'created_by': 1,
      'created_at': _iso(created),
      'started_at': _iso(created.add(const Duration(seconds: 12))),
      'completed_at':
          completed ? _iso(created.add(const Duration(minutes: 74))) : null,
      'jobs': [
        for (var i = 0; i < jobStatuses.length; i++)
          {
            'id': id * 10 + i,
            'pipeline_run_id': id,
            'copy_index': i,
            'assigned_printer_id': printerIds[i],
            'assigned_printer_name': printerIds[i] == null
                ? null
                : _printers
                    .where((p) => p['id'] == printerIds[i])
                    .firstOrNull?['name'],
            'queue_entry_id': null,
            'status': jobStatuses[i],
            'error_message':
                jobStatuses[i] == 'failed' ? 'Print failed on layer 41' : null,
            'dispatched_at': _iso(created),
            'completed_at': jobStatuses[i] == 'completed' || jobStatuses[i] == 'failed'
                ? _iso(created.add(const Duration(minutes: 68)))
                : null,
          },
      ],
      'target_kind': 'printer_class',
      'target_printer_id': null,
      'target_model_class': 'X1C',
      'fanout_strategy': 'max_parallel',
    };
  }

  /// The source every seeded run was sliced from.
  static const _pipelineSourceFileId = 6;

  static const _terminalRunStatuses = {
    'completed',
    'failed',
    'cancelled',
    'partial_failure',
  };

  /// `/pipeline-runs` — the dashboard's list with its four filters, one run,
  /// cancel, retry-failed and the history purge.
  DemoResult? _pipelineRunsRoute(
    String m,
    List<String> s,
    Map<String, String> q,
  ) {
    if (s.length == 1 && m == 'GET') {
      final pipelineId = int.tryParse(q['pipeline_id'] ?? '');
      final status = q['status'];
      final targetPrinterId = int.tryParse(q['target_printer_id'] ?? '');
      final targetModelClass = q['target_model_class'];
      // Filtered on the pipeline's *current* target, joined the way the route
      // joins it — so re-targeting a pipeline moves its whole history, and a
      // run whose pipeline is gone drops out of a target-filtered query.
      Map<String, dynamic>? pipelineOf(Map<String, dynamic> run) =>
          _pipelines.where((p) => p['id'] == run['pipeline_id']).firstOrNull;
      final matched = [
        for (final run in _pipelineRuns)
          if ((pipelineId == null || run['pipeline_id'] == pipelineId) &&
              (status == null || run['status'] == status) &&
              (targetPrinterId == null ||
                  pipelineOf(run)?['target_printer_id'] == targetPrinterId) &&
              (targetModelClass == null ||
                  pipelineOf(run)?['target_model_class'] == targetModelClass))
            run,
      ];
      // Clamped 1..100 silently, like the route — a caller asking for more gets
      // the cap and a `total` that still describes the whole filtered set.
      final limit = (int.tryParse(q['limit'] ?? '') ?? 25).clamp(1, 100);
      final offset = (int.tryParse(q['offset'] ?? '') ?? 0).clamp(0, 1 << 30);
      return _ok({
        'runs': matched.skip(offset).take(limit).toList(),
        'total': matched.length,
      });
    }

    if (s.length == 2 && m == 'POST' && s[1] == 'clear') {
      final before = _pipelineRuns.length;
      _pipelineRuns.removeWhere(
          (r) => _terminalRunStatuses.contains(r['status']));
      return _ok({'deleted': before - _pipelineRuns.length});
    }

    final runId = int.tryParse(s.length > 1 ? s[1] : '');
    if (runId == null) return _notFound();
    final run = _pipelineRuns.where((r) => r['id'] == runId).firstOrNull;
    if (run == null) return _notFound();

    if (s.length == 2 && m == 'GET') return _ok(run);

    if (s.length == 3 && m == 'POST' && s[2] == 'cancel') {
      // Idempotent: a run already finished comes back untouched rather than
      // refused, which is what lets the button be pressed twice safely.
      if (_terminalRunStatuses.contains(run['status'])) return _ok(run);
      run['status'] = 'cancelled';
      run['completed_at'] = _iso(DateTime.now());
      run['error_message'] ??= 'Cancelled by operator';
      for (final job in (run['jobs'] as List)) {
        if (job is Map && !_terminalRunStatuses.contains(job['status'])) {
          job['status'] = 'cancelled';
        }
      }
      run['copies_cancelled'] = (run['jobs'] as List)
          .where((j) => j is Map && j['status'] == 'cancelled')
          .length;
      run['copies_in_progress'] = 0;
      return _ok(run);
    }

    if (s.length == 3 && m == 'POST' && s[2] == 'retry-failed') {
      // The three preconditions the route checks, each a 400 — the source one
      // is why run 89 exists in the seed.
      if (run['pipeline_id'] == null) {
        return (
          status: 400,
          body: {'detail': 'Original pipeline was deleted; cannot retry'},
        );
      }
      if (run['source_library_file_id'] == null &&
          run['source_archive_id'] == null) {
        return (
          status: 400,
          body: {'detail': 'Original source was deleted; cannot retry'},
        );
      }
      final failed = (run['jobs'] as List)
          .where((j) => j is Map && (j['status'] == 'failed' || j['status'] == 'cancelled'))
          .length;
      if (failed == 0) {
        return (status: 400, body: {'detail': 'No failed copies to retry'});
      }
      final retry = _runRow(
        id: _nextPipelineRunId++,
        status: 'dispatching',
        copies: failed,
        jobStatuses: [for (var i = 0; i < failed; i++) 'queued'],
        printerIds: [for (var i = 0; i < failed; i++) null],
        minutesAgo: 0,
      );
      retry['parent_run_id'] = run['id'];
      // Forced past the pre-flight: the operator already accepted it on the
      // parent, which is what the route does too.
      retry['eligibility_overridden'] = true;
      _pipelineRuns.insert(0, retry);
      return (status: 202, body: retry);
    }
    return _fallback(m);
  }

  /// `/scheduled-dryings` — list, schedule, cancel. Served because the demo
  /// reports 1.2.6b1, which is the release the route shipped in: a version that
  /// offers the sheet's "later" modes over a 404 would be the one thing the
  /// gate exists to prevent.
  DemoResult? _scheduledDryingRoute(
    String m,
    List<String> s,
    Map<String, String> q,
    Map<String, dynamic> body,
  ) {
    if (s.length == 1 && m == 'GET') {
      final printerId = int.tryParse(q['printer_id'] ?? '');
      return _ok([
        for (final row in _scheduledDryings)
          if (printerId == null || row['printer_id'] == printerId) row,
      ]);
    }
    if (s.length == 1 && m == 'POST') {
      // Echoed with the `Z` the real schema appends, not as the app sent it:
      // the client writes naive UTC because that is what the column compares
      // against, and reading its own spelling back would hide a parser that
      // only handles one of the two.
      final asked = dateTimeFromJson(body['start_after']);
      final row = <String, dynamic>{
        'id': _nextScheduledDryingId++,
        'printer_id': body['printer_id'] ?? 1,
        'ams_id': body['ams_id'] ?? 0,
        'temp': body['temp'] ?? 45,
        'duration_hours': body['duration_hours'] ?? 4,
        'filament': body['filament'] ?? '',
        'rotate_tray': body['rotate_tray'] ?? false,
        'start_after': asked == null ? null : _iso(asked),
        'status': 'pending',
        'waiting_reason': null,
        'error_message': null,
        'created_at': _iso(DateTime.now()),
        'started_at': null,
        'completed_at': null,
      };
      _scheduledDryings.add(row);
      return _ok(row);
    }
    final rowId = int.tryParse(s.length > 1 ? s[1] : '');
    if (rowId != null && m == 'DELETE') {
      final before = _scheduledDryings.length;
      _scheduledDryings.removeWhere((row) => row['id'] == rowId);
      if (_scheduledDryings.length == before) return _notFound();
      return _ok({'status': 'cancelled', 'id': rowId});
    }
    return _fallback(m);
  }

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

  /// Per-printer-model preset overrides, by spool id — written by the spool
  /// form's PUT and read back by its next open, so the demo shows the replace
  /// semantics the real route has rather than a list that never changes.
  final Map<int, List<Map<String, dynamic>>> _presetOverrides = {};

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
    Object? rawBody,
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
            _presetOverrides.remove(spoolId);
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
            case 'filament-presets':
              if (m == 'GET') {
                return _ok(_presetOverrides[spoolId] ?? const <Object>[]);
              }
              if (m == 'PUT') {
                // A replace, like the route: whatever arrives becomes the whole
                // list, and an empty body clears it.
                final sent = rawBody is List ? rawBody : const [];
                final rows = <Map<String, dynamic>>[
                  for (final (i, row) in sent.whereType<Map>().indexed)
                    {
                      'id': i + 1,
                      'spool_id': spoolId,
                      'printer_model': row['printer_model'],
                      'nozzle_diameter': row['nozzle_diameter'] ?? '',
                      'slicer_filament': row['slicer_filament'],
                      'slicer_filament_name': row['slicer_filament_name'],
                      'created_at': _iso(DateTime.now()),
                    },
                ];
                _presetOverrides[spoolId!] = rows;
                return _ok(rows);
              }
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

  /// The models are spread across the demo fleet on purpose: a variant group is
  /// the same job sliced for *different* printers, and the server refuses two
  /// members that target the same one — so a library sliced entirely for the
  /// X1C could never demonstrate the feature.
  late final List<Map<String, dynamic>> _libraryFiles = [
    _libFile(1, 'Benchy.gcode.3mf', 1, 2108509, printCount: 3, timeSec: 3540, grams: 15.8),
    _libFile(2, 'Calibration cube.gcode.3mf', 1, 812340, printCount: 1, timeSec: 1620, grams: 6.1),
    _libFile(3, 'Temp tower PLA.gcode.3mf', 1, 1430200, printCount: 1, timeSec: 5340, grams: 21.4,
        model: 'P1S'),
    _libFile(4, 'Drawer organizer x4.gcode.3mf', 2, 4318208, printCount: 2, timeSec: 5400, grams: 96.2,
        model: 'P1S'),
    _libFile(5, 'Cable clips x8.gcode.3mf', 2, 1524736, printCount: 1, timeSec: 5520, grams: 42.3,
        model: 'P2S'),
    // The un-sliced sources — the only files the Slice button is offered on,
    // since anything already `gcode.3mf` is printable and cannot be re-sliced.
    // Three of them because the form looks different for each: a plain 3MF
    // fills one filament slot, the two-tone one fills four (two of which its
    // plates never touch), and an STL has no plates and so no "as designed".
    _libFile(6, 'SD card adapter.3mf', null, 634212, fileType: '3mf', model: null),
    _libFile(7, 'Hue dial two-tone.3mf', null, 2204160, fileType: '3mf', model: null),
    _libFile(8, 'Lamp shade.stl', null, 1841664, fileType: 'stl', model: null),
    // Uploaded straight from CAD, and refused before a byte is read: neither
    // slicer CLI loads STEP. The button is still offered — the file is not
    // printable — which is exactly the state the server's own message is for.
    _libFile(9, 'Motor bracket.step', null, 412160, fileType: 'step', model: null),
  ];

  final List<Map<String, dynamic>> _libraryTrash = [];
  int _nextFolderId = 10;

  /// Ids for the rows a slice files in the library. Above the fixtures so a
  /// sliced output never collides with one.
  int _nextLibraryFileId = 20;

  Map<String, dynamic> _libFile(
    int id,
    String filename,
    int? folderId,
    int size, {
    int printCount = 0,
    int? timeSec,
    double? grams,
    String fileType = 'gcode.3mf',
    // Null for a source that has never been through a slicer — the field
    // records which printer the *output* was built for, so an un-sliced
    // upload has no answer to give.
    String? model = 'X1C',
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
        'sliced_for_model': model,
        'variant_group_id': null,
        'variant_count': 0,
      };

  /// Cross-model variant groups (server #671), served because the demo now
  /// reports 1.2.6 — the file manager's grouping button appears at that version
  /// and a button that answers nothing is worse than one that is absent.
  ///
  /// Refuses what the real route refuses: fewer than two members, a file that
  /// is already grouped, a file that is not sliced output, and two members
  /// sliced for the same printer — the last one being the whole point, since a
  /// group of two X1C files expresses no choice for the scheduler.
  final List<Map<String, dynamic>> _variantGroups = [];
  int _nextVariantGroupId = 1;

  DemoResult _variantGroupRoute(
    String m,
    List<String> s,
    Map<String, dynamic> body,
  ) {
    if (s.length == 2 && m == 'POST') {
      final members = (body['members'] as List?) ?? const [];
      final ids = [
        for (final member in members.whereType<Map>())
          member['library_file_id'] as int?,
      ].nonNulls.toList();
      if (ids.length < 2) {
        return (status: 400, body: {'detail': 'A variant group needs at least 2 members'});
      }
      final files = [
        for (final id in ids)
          ..._libraryFiles.where((f) => f['id'] == id),
      ];
      if (files.length != ids.length) {
        return (status: 404, body: {'detail': 'Library file not found'});
      }
      final models = <String, String>{};
      for (final f in files) {
        if (f['file_type'] != 'gcode.3mf' && f['file_type'] != 'gcode') {
          return (
            status: 400,
            body: {
              'detail': '${f['filename']} is not a sliced file — only sliced '
                  'output can be a print variant',
            },
          );
        }
        if (f['variant_group_id'] != null) {
          return (
            status: 409,
            body: {'detail': '${f['filename']} already belongs to a variant group'},
          );
        }
        final model = '${f['sliced_for_model']}';
        final clash = models[model];
        if (clash != null) {
          return (
            status: 400,
            body: {
              'detail': '${f['filename']} and $clash are both sliced for '
                  '$model — variants must target different printers',
            },
          );
        }
        models[model] = '${f['filename']}';
      }

      final group = {
        'id': _nextVariantGroupId++,
        'name': body['name'] ?? files.first['filename'],
        'members': [
          for (final (position, f) in files.indexed)
            {
              'library_file_id': f['id'],
              'filename': f['filename'],
              'target_model': f['sliced_for_model'],
              'position': position,
            },
        ],
      };
      _variantGroups.add(group);
      for (final f in files) {
        f['variant_group_id'] = group['id'];
        f['variant_count'] = files.length;
      }
      return _ok(group);
    }

    if (s.length == 4 && s[2] == 'by-file' && m == 'GET') {
      final fileId = int.tryParse(s[3]);
      final file = _libraryFiles.where((f) => f['id'] == fileId).firstOrNull;
      final groupId = file?['variant_group_id'];
      final group =
          _variantGroups.where((g) => g['id'] == groupId).firstOrNull;
      // 404 is the ordinary answer for an ungrouped file, not an error.
      return group == null ? _notFound() : _ok(group);
    }

    final groupId = int.tryParse(s.length > 2 ? s[2] : '');
    final group = _variantGroups.where((g) => g['id'] == groupId).firstOrNull;
    if (group == null) return _notFound();
    if (s.length == 3 && m == 'GET') return _ok(group);
    if (s.length == 3 && m == 'DELETE') {
      _variantGroups.remove(group);
      for (final f in _libraryFiles) {
        if (f['variant_group_id'] != groupId) continue;
        f['variant_group_id'] = null;
        f['variant_count'] = 0;
      }
      return _ok(const {'ok': true});
    }
    return _fallback(m);
  }

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
        if (s.length >= 4 && s[3] == 'plates') return _ok(_libraryPlates(file));
        if (s.length >= 4 && s[3] == 'filament-requirements') {
          return _ok(_libraryFilaments(file, q));
        }
        if (s.length >= 4 && s[3] == 'slice' && m == 'POST') {
          return _startSlice(isArchive: false, source: file, body: body);
        }
        if (s.length >= 4 && s[3] == 'print') {
          return _ok(const {'ok': true});
        }
        return _fallback(m);

      case 'variant-groups':
        return _variantGroupRoute(m, s, body);

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

  static DateTime _minutesAgo(int minutes) =>
      DateTime.now().subtract(Duration(minutes: minutes));

  static String _iso(DateTime t) => t.toUtc().toIso8601String();
}

/// State of one demo download preparation. Advanced by polling it — see
/// [DemoBackend._downloadJobs].
class _DemoDownloadJob {
  _DemoDownloadJob({
    required this.jobId,
    required this.printerId,
    required this.paths,
    required this.asZip,
    required this.filename,
  });

  final String jobId;
  final int printerId;
  final List<String> paths;
  final bool asZip;
  final String filename;

  int staged = 0;
  String? token;

  /// Stages one more file, and mints the token once every file is in.
  void advance() {
    if (staged < paths.length) staged++;
    if (staged >= paths.length) token ??= 'demo-token-$jobId';
  }

  String get state => token == null ? 'preparing' : 'ready';

  Map<String, dynamic> toJson() => {
        'job_id': jobId,
        'printer_id': printerId,
        'state': state,
        'requested': paths.length,
        'successful': staged,
        'failed': 0,
        'token': token,
        'filename': filename,
        'message': null,
      };
}
