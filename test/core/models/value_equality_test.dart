import 'package:bambuddy_mobile/core/api/media_auth.dart';
import 'package:bambuddy_mobile/core/api/server_version.dart';
import 'package:bambuddy_mobile/core/models/ams_filament_preset.dart';
import 'package:bambuddy_mobile/core/models/calibration_option.dart';
import 'package:bambuddy_mobile/core/models/filament_requirement.dart';
import 'package:bambuddy_mobile/core/models/next_pause.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/models/value_equality.dart';
import 'package:bambuddy_mobile/core/settings/appearance_prefs.dart';
import 'package:bambuddy_mobile/core/settings/print_options.dart';
import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/core/widget/home_widget_publisher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;

class _Sample with ValueEquality {
  const _Sample(this.a, this.b, [this.list = const []]);

  final int a;
  final String? b;
  final List<int> list;

  @override
  List<Object?> get props => [a, b, list];
}

class _Twin with ValueEquality {
  const _Twin(this.a);

  final int a;

  @override
  List<Object?> get props => [a];
}

class _OtherTwin with ValueEquality {
  const _OtherTwin(this.a);

  final int a;

  @override
  List<Object?> get props => [a];
}

/// One converted class: [make] builds an instance from the base field values,
/// [variants] changes exactly one field each. A field missing from `props`
/// leaves its variant equal to the base and fails the table.
class _Case {
  _Case(this.name, this.make, this.variants);

  final String name;
  final ValueEquality Function() make;
  final Map<String, ValueEquality Function()> variants;
}

void main() {
  group('ValueEquality', () {
    test('equal props: equal and same hashCode', () {
      const x = _Sample(1, 'a', [1, 2]);
      final y = _Sample(1, 'a', [1, 2]);
      expect(x, y);
      expect(x.hashCode, y.hashCode);
      expect(x == x, isTrue);
    });

    test('each changed field breaks equality', () {
      const base = _Sample(1, 'a', [1, 2]);
      expect(base, isNot(const _Sample(2, 'a', [1, 2])));
      expect(base, isNot(const _Sample(1, 'b', [1, 2])));
      expect(base, isNot(const _Sample(1, null, [1, 2])));
      expect(base, isNot(const _Sample(1, 'a', [1, 3])));
      expect(base, isNot(const _Sample(1, 'a', [1, 2, 3])));
      expect(base, isNot(const _Sample(1, 'a')));
    });

    test('a list field compares by contents, not identity', () {
      final x = _Sample(1, null, [1, 2, 3]);
      final y = _Sample(1, null, List.of([1, 2, 3]));
      expect(identical(x.list, y.list), isFalse);
      expect(x, y);
      expect(x.hashCode, y.hashCode);
    });

    test('null fields and empty lists are legitimate values', () {
      expect(const _Sample(0, null), const _Sample(0, null));
      expect(const _Sample(0, null).hashCode, const _Sample(0, null).hashCode);
    });

    test('another runtimeType with the same props is not equal', () {
      const Object twin = _Twin(1);
      const Object other = _OtherTwin(1);
      expect(twin == other, isFalse);
      expect(other == twin, isFalse);
    });

    test('not equal to a value of an unrelated type', () {
      expect(const _Twin(1) == (1 as Object), isFalse);
    });
  });

  AmsTray tray({
    int? id = 1,
    String? color = 'FF0000FF',
    String? type = 'PLA',
    String? sub = 'PLA Basic',
    int? remain = 50,
    String? idx = 'GFA00',
    int? cali = 3,
    String? tag = 'AB',
    String? uuid = 'CD',
    int? state = 11,
    bool? exists = true,
  }) => AmsTray(
    id: id,
    trayColor: color,
    trayType: type,
    traySubBrands: sub,
    remain: remain,
    trayInfoIdx: idx,
    caliIdx: cali,
    tagUid: tag,
    trayUuid: uuid,
    state: state,
    exists: exists,
  );

  AmsUnit unit({
    int? id = 0,
    int? humidity = 4,
    double? temp = 25.5,
    List<AmsTray>? trays,
    bool? ht = false,
    int? dryTime = 10,
    int? dryStatus = 1,
    String? module = 'n3f',
    bool stalled = false,
    List<int> dryerSlots = const [2, 3],
    int? dryerHumidity = 12,
    double? dryerTemp = 55,
    int? amsType = 6,
  }) => AmsUnit(
    id: id,
    humidity: humidity,
    temp: temp,
    trays: trays ?? [tray()],
    isAmsHt: ht,
    dryTime: dryTime,
    dryStatus: dryStatus,
    moduleType: module,
    dryCountdownStalled: stalled,
    dryerSlots: dryerSlots,
    dryerHumidity: dryerHumidity,
    dryerTemp: dryerTemp,
    amsType: amsType,
  );

  HmsError hms({
    String? code = '0x20070',
    String? message = 'm',
    int? severity = 2,
    int? attr = 5,
    int? module = 7,
    List<String> actions = const ['A', 'B'],
    String? jobId = 'j',
    String? fullCode = '0C00010000020001',
    String? description = 'd',
  }) => HmsError(
    code: code,
    message: message,
    severity: severity,
    attr: attr,
    module: module,
    actions: actions,
    jobId: jobId,
    fullCode: fullCode,
    description: description,
  );

  const preset = AmsFilamentPreset(
    source: AmsPresetSource.cloud,
    id: 'P1',
    name: 'n',
  );

  ServerVersion version({
    String raw = '1.2.3',
    int major = 1,
    int minor = 2,
    int patch = 3,
    int micro = 0,
    bool pre = false,
    int preNum = 0,
  }) => ServerVersion(
    raw: raw,
    major: major,
    minor: minor,
    patch: patch,
    micro: micro,
    isPrerelease: pre,
    prereleaseNum: preNum,
  );

  PrintOptions opts({
    CalibrationOption bed = CalibrationOption.on,
    CalibrationOption flow = CalibrationOption.on,
    bool vib = true,
    bool inspect = true,
    bool timelapse = false,
    CalibrationOption nozzle = CalibrationOption.on,
    bool gcode = false,
  }) => PrintOptions(
    bedLevelling: bed,
    flowCali: flow,
    vibrationCali: vib,
    layerInspect: inspect,
    timelapse: timelapse,
    nozzleOffsetCali: nozzle,
    gcodeInjection: gcode,
  );

  WidgetPublishKey key({
    int? printer = 1,
    String status = 'RUNNING',
    int pct = 10,
    int? eta = 5,
    String layers = '1/10',
    String? cover = 'c',
  }) => WidgetPublishKey(
    printerId: printer,
    statusKey: status,
    progressPct: pct,
    etaMinutes: eta,
    layers: layers,
    coverUrl: cover,
  );

  ServerProfile profile({
    String url = 'http://a.local',
    AuthMode mode = AuthMode.jwt,
    String? label = 'L',
  }) => ServerProfile(baseUrl: url, authMode: mode, label: label);

  final cases = <_Case>[
    _Case('AmsTray', tray, {
      'id': () => tray(id: 2),
      'trayColor': () => tray(color: '00FF00FF'),
      'trayType': () => tray(type: 'PETG'),
      'traySubBrands': () => tray(sub: 'PLA Matte'),
      'remain': () => tray(remain: 51),
      'trayInfoIdx': () => tray(idx: 'GFB00'),
      'caliIdx': () => tray(cali: 4),
      'tagUid': () => tray(tag: 'EF'),
      'state': () => tray(state: 9),
      'exists': () => tray(exists: false),
      'trayUuid': () => tray(uuid: 'GH'),
    }),
    _Case('AmsUnit', unit, {
      'id': () => unit(id: 1),
      'humidity': () => unit(humidity: 5),
      'temp': () => unit(temp: 26),
      'trays': () => unit(trays: [tray(), tray(id: 2)]),
      'trays (one tray changed)': () => unit(trays: [tray(remain: 1)]),
      'isAmsHt': () => unit(ht: true),
      'dryTime': () => unit(dryTime: 11),
      'dryerSlots': () => unit(dryerSlots: const [2, 4]),
      'dryerHumidity': () => unit(dryerHumidity: 13),
      'dryerTemp': () => unit(dryerTemp: 56),
      'amsType': () => unit(amsType: 7),
      'dryStatus': () => unit(dryStatus: 2),
      'moduleType': () => unit(module: 'n3s'),
      'dryCountdownStalled': () => unit(stalled: true),
    }),
    _Case(
      'NozzleInfo',
      () => const NozzleInfo(nozzleType: 's', nozzleDiameter: '0.4'),
      {
        'nozzleType': () =>
            const NozzleInfo(nozzleType: 'h', nozzleDiameter: '0.4'),
        'nozzleDiameter': () =>
            const NozzleInfo(nozzleType: 's', nozzleDiameter: '0.6'),
      },
    ),
    _Case(
      'NozzleRackSlot',
      () => const NozzleRackSlot(
        id: 16,
        nozzleType: 'HS00',
        nozzleDiameter: '0.4',
        filamentColor: 'FF',
        filamentType: 'PLA',
        addrId: 6,
      ),
      {
        'id': () => const NozzleRackSlot(
          id: 17,
          nozzleType: 'HS00',
          nozzleDiameter: '0.4',
          filamentColor: 'FF',
          filamentType: 'PLA',
          addrId: 6,
        ),
        'nozzleType': () => const NozzleRackSlot(
          id: 16,
          nozzleType: 'HH00',
          nozzleDiameter: '0.4',
          filamentColor: 'FF',
          filamentType: 'PLA',
          addrId: 6,
        ),
        'nozzleDiameter': () => const NozzleRackSlot(
          id: 16,
          nozzleType: 'HS00',
          nozzleDiameter: '0.6',
          filamentColor: 'FF',
          filamentType: 'PLA',
          addrId: 6,
        ),
        'filamentColor': () => const NozzleRackSlot(
          id: 16,
          nozzleType: 'HS00',
          nozzleDiameter: '0.4',
          filamentColor: '00',
          filamentType: 'PLA',
          addrId: 6,
        ),
        'filamentType': () => const NozzleRackSlot(
          id: 16,
          nozzleType: 'HS00',
          nozzleDiameter: '0.4',
          filamentColor: 'FF',
          filamentType: 'PETG',
          addrId: 6,
        ),
        'addrId': () => const NozzleRackSlot(
          id: 16,
          nozzleType: 'HS00',
          nozzleDiameter: '0.4',
          filamentColor: 'FF',
          filamentType: 'PLA',
          addrId: 7,
        ),
      },
    ),
    _Case('FilaSwitch', () => const FilaSwitch(installed: true), {
      'installed': () => const FilaSwitch(),
      'ready': () => const FilaSwitch(installed: true, ready: true),
    }),
    _Case('ExtruderSlot', () => const ExtruderSlot(amsId: 0, slotId: 1), {
      'amsId': () => const ExtruderSlot(amsId: 1, slotId: 1),
      'slotId': () => const ExtruderSlot(amsId: 0, slotId: 2),
      'hasFilament': () =>
          const ExtruderSlot(amsId: 0, slotId: 1, hasFilament: true),
    }),
    _Case('HmsError', hms, {
      'code': () => hms(code: '0x20071'),
      'message': () => hms(message: 'x'),
      'severity': () => hms(severity: 3),
      'attr': () => hms(attr: 6),
      'module': () => hms(module: 8),
      'actions': () => hms(actions: const ['A']),
      'actions (order)': () => hms(actions: const ['B', 'A']),
      'jobId': () => hms(jobId: 'k'),
      'fullCode': () => hms(fullCode: '0C00010000020002'),
      'description': () => hms(description: 'e'),
    }),
    _Case('NextPause', () => const NextPause(layer: 5, minutes: 2), {
      'layer': () => const NextPause(layer: 6, minutes: 2),
      'minutes': () => const NextPause(layer: 5),
    }),
    _Case(
      'RackGroup',
      () => const RackGroup(
        onRack: true,
        nozzleDiameter: '0.40',
        volumeType: 'Standard',
        filamentColor: '#FFFFFF',
      ),
      {
        'onRack': () => const RackGroup(
          nozzleDiameter: '0.40',
          volumeType: 'Standard',
          filamentColor: '#FFFFFF',
        ),
        'nozzleDiameter': () => const RackGroup(
          onRack: true,
          nozzleDiameter: '0.60',
          volumeType: 'Standard',
          filamentColor: '#FFFFFF',
        ),
        'volumeType': () => const RackGroup(
          onRack: true,
          nozzleDiameter: '0.40',
          volumeType: 'High Flow',
          filamentColor: '#FFFFFF',
        ),
        'filamentColor': () => const RackGroup(
          onRack: true,
          nozzleDiameter: '0.40',
          volumeType: 'Standard',
          filamentColor: '#000000',
        ),
      },
    ),
    // Compares source and id only: the other fields are deliberately absent.
    _Case('AmsFilamentPreset', () => preset, {
      'source': () => const AmsFilamentPreset(
        source: AmsPresetSource.local,
        id: 'P1',
        name: 'n',
      ),
      'id': () => const AmsFilamentPreset(
        source: AmsPresetSource.cloud,
        id: 'P2',
        name: 'n',
      ),
    }),
    // `raw` is the verbatim text, not part of the version's identity.
    _Case('ServerVersion', version, {
      'major': () => version(major: 2),
      'minor': () => version(minor: 3),
      'patch': () => version(patch: 4),
      'micro': () => version(micro: 1),
      'isPrerelease': () => version(pre: true),
      'prereleaseNum': () => version(preNum: 1),
    }),
    _Case(
      'MediaAuth',
      () => const MediaAuth(queryToken: 't', headers: {'A': '1', 'B': '2'}),
      {
        'queryToken': () =>
            const MediaAuth(queryToken: 'u', headers: {'A': '1', 'B': '2'}),
        'headers value': () =>
            const MediaAuth(queryToken: 't', headers: {'A': '1', 'B': '3'}),
        'headers key': () =>
            const MediaAuth(queryToken: 't', headers: {'A': '1', 'C': '2'}),
        'headers size': () =>
            const MediaAuth(queryToken: 't', headers: {'A': '1'}),
      },
    ),
    _Case('AppearancePrefs', () => const AppearancePrefs(), {
      'accent': () => const AppearancePrefs(accent: AccentSource.blue),
      'mode': () => const AppearancePrefs(mode: ThemeMode.dark),
    }),
    _Case('WatchAppearance', () => const WatchAppearance(), {
      'source': () => const WatchAppearance(source: WatchThemeSource.face),
      'preset': () => const WatchAppearance(preset: AccentSource.pink),
    }),
    _Case('PrintOptions', opts, {
      'bedLevelling': () => opts(bed: CalibrationOption.auto),
      'flowCali': () => opts(flow: CalibrationOption.off),
      'vibrationCali': () => opts(vib: false),
      'layerInspect': () => opts(inspect: false),
      'timelapse': () => opts(timelapse: true),
      'nozzleOffsetCali': () => opts(nozzle: CalibrationOption.auto),
      'gcodeInjection': () => opts(gcode: true),
    }),
    _Case('ServerProfile', profile, {
      'baseUrl': () => profile(url: 'http://b.local'),
      'authMode': () => profile(mode: AuthMode.apiKey),
      'label': () => profile(label: null),
    }),
    _Case('WidgetPublishKey', key, {
      'printerId': () => key(printer: 2),
      'statusKey': () => key(status: 'PAUSE'),
      'progressPct': () => key(pct: 11),
      'etaMinutes': () => key(eta: 6),
      'layers': () => key(layers: '2/10'),
      'coverUrl': () => key(cover: null),
    }),
  ];

  for (final c in cases) {
    group('${c.name} equality', () {
      test(
        'a second instance with the same values is equal, hash included',
        () {
          final a = c.make();
          final b = c.make();
          expect(a, b);
          expect(a.hashCode, b.hashCode);
        },
      );

      test('there is one variant per prop, so none can be forgotten', () {
        expect(c.variants.length, greaterThanOrEqualTo(c.make().props.length));
      });

      for (final entry in c.variants.entries) {
        test('changing ${entry.key} breaks equality', () {
          final base = c.make();
          final changed = entry.value();
          expect(changed == base, isFalse);
          expect(base == changed, isFalse);
        });
      }
    });
  }

  group('behaviour kept from the hand-written pairs', () {
    test('AmsFilamentPreset ignores everything but source and id', () {
      const other = AmsFilamentPreset(
        source: AmsPresetSource.cloud,
        id: 'P1',
        name: 'another name',
        isUser: true,
        filamentType: 'PLA',
        nozzleTempMin: 1,
        nozzleTempMax: 2,
        compatiblePrinters: ['X'],
      );
      expect(other, preset);
      expect(other.hashCode, preset.hashCode);
    });

    test('ServerVersion ignores the raw text', () {
      expect(version(raw: 'v1.2.3'), version());
      expect(version(raw: 'v1.2.3').hashCode, version().hashCode);
    });

    test('MediaAuth headers compare by content, whatever the order', () {
      const a = MediaAuth(headers: {'A': '1', 'B': '2'});
      const b = MediaAuth(headers: {'B': '2', 'A': '1'});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('HmsError and AmsUnit compare their lists by content', () {
      expect(hms(actions: List.of(['A', 'B'])), hms());
      expect(hms(actions: List.of(['A', 'B'])).hashCode, hms().hashCode);
      expect(unit(trays: [tray()]), unit(trays: [tray()]));
      expect(unit(trays: [tray()]).hashCode, unit(trays: [tray()]).hashCode);
      expect(const AmsUnit(), const AmsUnit());
      expect(const AmsUnit().hashCode, const AmsUnit().hashCode);
    });
  });
}
