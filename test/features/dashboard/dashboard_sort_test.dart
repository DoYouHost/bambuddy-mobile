import 'package:bambuddy_mobile/core/models/printer.dart';
import 'package:bambuddy_mobile/core/models/printer_status.dart';
import 'package:bambuddy_mobile/core/notifications/hms_catalog.dart';
import 'package:flutter/widgets.dart';
import 'package:bambuddy_mobile/data/printers_repository.dart';
import 'package:bambuddy_mobile/features/dashboard/dashboard_filters.dart';
import 'package:bambuddy_mobile/features/dashboard/dashboard_sort.dart';
import 'package:bambuddy_mobile/features/dashboard/dashboard_view_store.dart';
import 'package:flutter_test/flutter_test.dart';

PrinterWithStatus _p(
  int id,
  String name, {
  String? location,
  String? model,
  bool connected = true,
  String? state = 'IDLE',
  int? left,
}) => PrinterWithStatus(
  printer: Printer(id: id, name: name, location: location, model: model),
  status: PrinterStatus(
    id: id,
    connected: connected,
    state: state,
    remainingTime: left,
  ),
);

List<String> _names(Iterable<PrinterWithStatus> ps) => [
  for (final p in ps) p.printer.name,
];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await HmsCatalog.instance.load(const Locale('en'));
  });

  final farm = [
    _p(1, 'bravo', location: 'Workshop', model: 'X1C'),
    _p(2, 'Alpha', model: 'P1S'),
    _p(3, 'charlie', location: 'Attic', model: 'X1C'),
    _p(4, 'Delta', location: 'Workshop'),
  ];

  group('sortPrinters', () {
    test('the sort a fresh install starts with is status, ascending', () {
      const fresh = DashboardSort();
      expect(fresh.by, PrinterSort.status);
      expect(fresh.ascending, isTrue);
    });

    test('by name ignores case; descending turns the list round', () {
      expect(
        _names(sortPrinters(farm, const DashboardSort(by: PrinterSort.name))),
        ['Alpha', 'bravo', 'charlie', 'Delta'],
      );
      expect(
        _names(
          sortPrinters(
            farm,
            const DashboardSort(by: PrinterSort.name, ascending: false),
          ),
        ),
        ['Delta', 'charlie', 'bravo', 'Alpha'],
      );
    });

    test('by location puts printers without one last, then goes by name', () {
      const by = DashboardSort(by: PrinterSort.location);
      expect(_names(sortPrinters(farm, by)), [
        'charlie',
        'bravo',
        'Delta',
        'Alpha',
      ]);
      expect(
        _names(sortPrinters(farm, by.copyWith(ascending: false))).first,
        'Alpha',
      );
    });

    test('by model keeps the server\'s order among equal models', () {
      expect(
        _names(sortPrinters(farm, const DashboardSort(by: PrinterSort.model))),
        // '' (Delta) < P1S < X1C, and bravo stays before charlie.
        ['Delta', 'Alpha', 'bravo', 'charlie'],
      );
    });

    test('by status: printing, then idle, then offline, ties as listed', () {
      final mixed = [
        _p(1, 'off', connected: false, state: null),
        _p(2, 'idle-a'),
        _p(3, 'run', state: 'RUNNING'),
        _p(4, 'idle-b'),
      ];
      expect(
        _names(
          sortPrinters(mixed, const DashboardSort(by: PrinterSort.status)),
        ),
        ['run', 'idle-a', 'idle-b', 'off'],
      );
    });

    test('by status a displayable HMS error comes first, a failed or preparing '
        'printer is idle', () {
      PrinterWithStatus withHms(int id, String name) => PrinterWithStatus(
        printer: Printer(id: id, name: name),
        status: PrinterStatus(
          id: id,
          connected: true,
          state: 'IDLE',
          hmsErrors: const [
            HmsError(
              code: '0x8004',
              attr: 0x03008004,
              module: 3,
              severity: 3,
              fullCode: '03008004',
            ),
          ],
        ),
      );
      final mixed = [
        _p(1, 'idle'),
        _p(2, 'failed', state: 'FAILED'),
        _p(3, 'preparing', state: 'PREPARE'),
        _p(4, 'run', state: 'RUNNING'),
        withHms(5, 'hms'),
      ];
      expect(
        _names(
          sortPrinters(mixed, const DashboardSort(by: PrinterSort.status)),
        ),
        ['hms', 'run', 'idle', 'failed', 'preparing'],
      );
    });

    test('names that differ only in case keep one order whichever way they '
        'arrive', () {
      final a = [_p(1, 'alpha'), _p(2, 'Alpha')];
      expect(
        _names(sortPrinters(a, const DashboardSort(by: PrinterSort.name))),
        _names(
          sortPrinters(
            a.reversed.toList(),
            const DashboardSort(by: PrinterSort.name),
          ),
        ),
      );
    });

    test('by time left: soonest first, then printing without an estimate, '
        'idle, offline', () {
      final mixed = [
        _p(1, 'off', connected: false, state: null),
        _p(2, 'idle'),
        _p(3, 'long', state: 'RUNNING', left: 90),
        _p(4, 'unknown', state: 'RUNNING'),
        _p(5, 'soon', state: 'RUNNING', left: 5),
      ];
      expect(
        _names(sortPrinters(mixed, const DashboardSort(by: PrinterSort.eta))),
        ['soon', 'long', 'unknown', 'idle', 'off'],
      );
    });

    test('an empty roster and a single printer come back as they are', () {
      expect(
        sortPrinters(const [], const DashboardSort(by: PrinterSort.name)),
        isEmpty,
      );
      expect(
        _names(
          sortPrinters([
            _p(1, 'only'),
          ], const DashboardSort(by: PrinterSort.name)),
        ),
        ['only'],
      );
    });
  });

  group('groupPrinters', () {
    List<PrinterGroup> groups(DashboardSort by) =>
        groupPrinters(sortPrinters(farm, by), by)!;

    test('a name or a time left is not grouped', () {
      expect(
        groupPrinters(farm, const DashboardSort(by: PrinterSort.eta)),
        isNull,
      );
      expect(
        groupPrinters(farm, const DashboardSort(by: PrinterSort.name)),
        isNull,
      );
    });

    test('by location: a section per location, none last', () {
      final g = groups(const DashboardSort(by: PrinterSort.location));
      expect(g.map((x) => x.name), ['Attic', 'Workshop', null]);
      expect(g.map((x) => x.key), [
        'location:Attic',
        'location:Workshop',
        'location:',
      ]);
      expect(_names(g[1].printers), ['bravo', 'Delta']);
    });

    test('a location really called "Ungrouped" is not the section of printers '
        'with none', () {
      final odd = [_p(1, 'a', location: 'Ungrouped'), _p(2, 'b')];
      const by = DashboardSort(by: PrinterSort.location);

      final g = groupPrinters(sortPrinters(odd, by), by)!;

      expect(g.map((x) => x.key), ['location:Ungrouped', 'location:']);
      expect(g.map((x) => x.name), ['Ungrouped', null]);
    });

    test('descending turns the sections round with the printers', () {
      final g = groups(
        const DashboardSort(by: PrinterSort.location, ascending: false),
      );
      expect(g.map((x) => x.name), [null, 'Workshop', 'Attic']);
    });

    test('by model: printers without one share the unknown section', () {
      final g = groups(const DashboardSort(by: PrinterSort.model));
      expect(g.map((x) => x.key), ['model:', 'model:P1S', 'model:X1C']);
    });

    test('by status: the fixed order, error to offline, empty ones left '
        'out; descending turns it round', () {
      final mixed = [
        _p(1, 'off', connected: false, state: null),
        _p(2, 'idle'),
        _p(3, 'run', state: 'RUNNING'),
        _p(4, 'done', state: 'FINISH'),
      ];
      const by = DashboardSort(by: PrinterSort.status);
      expect(groupPrinters(sortPrinters(mixed, by), by)!.map((g) => g.bucket), [
        PrinterStatusBucket.printing,
        PrinterStatusBucket.finished,
        PrinterStatusBucket.idle,
        PrinterStatusBucket.offline,
      ]);
      final down = by.copyWith(ascending: false);
      expect(
        groupPrinters(sortPrinters(mixed, down), down)!.first.bucket,
        PrinterStatusBucket.offline,
      );
    });
  });

  group('DashboardFilters', () {
    test(
      'a location matches exactly; a printer with none is the empty one',
      () {
        const only = DashboardFilters(location: 'Workshop');
        expect(only.matches(PrinterStatusBucket.idle, 'Workshop'), isTrue);
        expect(only.matches(PrinterStatusBucket.idle, 'workshop'), isFalse);
        expect(only.matches(PrinterStatusBucket.idle), isFalse);
        expect(
          const DashboardFilters().matches(PrinterStatusBucket.idle),
          isTrue,
        );
      },
    );

    test(
      'a location counts as an active filter, and copyWith can clear it',
      () {
        const f = DashboardFilters(location: 'Attic');
        expect(f.activeCount, 1);
        expect(f.copyWith(hideOffline: true).location, 'Attic');
        expect(f.copyWith(location: null).location, isNull);
      },
    );

    test('printerLocationsOf drops blanks and duplicates and sorts', () {
      expect(printerLocationsOf(['b', null, '', 'a', 'b']), ['a', 'b']);
    });
  });

  group('DashboardView', () {
    test('round-trips what it saved', () {
      const view = DashboardView(
        filters: DashboardFilters(
          status: PrinterStatusBucket.printing,
          hideOffline: true,
          location: 'Workshop',
        ),
        sort: DashboardSort(by: PrinterSort.location, ascending: false),
        collapsed: {'location:Attic'},
      );

      final back = DashboardView.fromJson(view.toJson());

      expect(back.filters.status, PrinterStatusBucket.printing);
      expect(back.filters.hideOffline, isTrue);
      expect(back.filters.location, 'Workshop');
      expect(back.sort.by, PrinterSort.location);
      expect(back.sort.ascending, isFalse);
      expect(back.collapsed, {'location:Attic'});
    });

    test(
      'nothing saved, or a value the app no longer knows, is the default',
      () {
        for (final json in [
          const <String, dynamic>{},
          {'status': 'gone', 'sort': 'gone', 'location': 7, 'collapsed': 'x'},
        ]) {
          final view = DashboardView.fromJson(json);
          expect(view.filters.status, PrinterStatusBucket.all);
          expect(view.filters.location, isNull);
          expect(view.sort.by, PrinterSort.status);
          expect(view.sort.ascending, isTrue);
          expect(view.collapsed, isEmpty);
        }
      },
    );
  });
}
