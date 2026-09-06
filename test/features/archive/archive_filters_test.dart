import 'package:bambuddy_mobile/core/models/archive.dart';
import 'package:bambuddy_mobile/features/archive/archive_providers.dart';
import 'package:flutter_test/flutter_test.dart';

Archive _a(
  int id, {
  String? name,
  String filename = 'file.gcode',
  String status = 'completed',
  int? printerId,
  String? filamentType,
  String? filamentColor,
  bool favorite = false,
  int? fileSize,
  int duplicateCount = 0,
  int duplicateSequence = 0,
  int? totalLayers,
  DateTime? createdAt,
}) => Archive(
  id: id,
  filename: filename,
  status: status,
  printName: name,
  printerId: printerId,
  filamentType: filamentType,
  filamentColor: filamentColor,
  isFavorite: favorite,
  fileSize: fileSize,
  duplicateCount: duplicateCount,
  duplicateSequence: duplicateSequence,
  totalLayers: totalLayers,
  createdAt: createdAt,
);

List<int> _ids(List<Archive> l) => l.map((a) => a.id).toList();

void main() {
  group('applyArchiveFilters', () {
    test('brak filtrów zwraca wszystko posortowane wg daty malejąco', () {
      final list = [
        _a(1, createdAt: DateTime(2026, 1, 1)),
        _a(2, createdAt: DateTime(2026, 3, 1)),
        _a(3, createdAt: DateTime(2026, 2, 1)),
      ];
      final out = applyArchiveFilters(list, const ArchiveFilters());
      expect(_ids(out), [2, 3, 1]);
    });

    test('search dopasowuje displayName (case-insensitive)', () {
      final list = [_a(1, name: 'Benchy Boat'), _a(2, name: 'Gridfinity Bin')];
      final out = applyArchiveFilters(
        list,
        const ArchiveFilters(query: 'bench'),
      );
      expect(_ids(out), [1]);
    });

    test('search dopasowuje filename gdy brak printName', () {
      final list = [_a(1, name: null, filename: 'voron_mount.gcode')];
      final out = applyArchiveFilters(
        list,
        const ArchiveFilters(query: 'voron'),
      );
      expect(_ids(out), [1]);
    });

    test('filtr drukarki', () {
      final list = [_a(1, printerId: 10), _a(2, printerId: 20)];
      final out = applyArchiveFilters(
        list,
        const ArchiveFilters(printerId: 20),
      );
      expect(_ids(out), [2]);
    });

    test('filtr materiału po jednym z wielu typów', () {
      final list = [
        _a(1, filamentType: 'PLA, PETG'),
        _a(2, filamentType: 'ABS'),
      ];
      final out = applyArchiveFilters(
        list,
        const ArchiveFilters(material: 'PETG'),
      );
      expect(_ids(out), [1]);
    });

    test('filtr kolorów OR: dowolny pasujący', () {
      final list = [
        _a(1, filamentColor: '#FF0000,#00FF00'),
        _a(2, filamentColor: '#0000FF'),
      ];
      final out = applyArchiveFilters(
        list,
        const ArchiveFilters(colors: {'#00FF00'}),
      );
      expect(_ids(out), [1]);
    });

    test('filtr kolorów AND: musi mieć wszystkie', () {
      final list = [
        _a(1, filamentColor: '#FF0000,#00FF00'),
        _a(2, filamentColor: '#FF0000'),
      ];
      final out = applyArchiveFilters(
        list,
        const ArchiveFilters(
          colors: {'#FF0000', '#00FF00'},
          colorMode: ColorFilterMode.and,
        ),
      );
      expect(_ids(out), [1]);
    });

    test('tylko ulubione', () {
      final list = [_a(1, favorite: true), _a(2)];
      final out = applyArchiveFilters(
        list,
        const ArchiveFilters(favoritesOnly: true),
      );
      expect(_ids(out), [1]);
    });

    test('ukryj nieudane (failed i aborted)', () {
      final list = [
        _a(1, status: 'completed'),
        _a(2, status: 'failed'),
        _a(3, status: 'aborted'),
      ];
      final out = applyArchiveFilters(
        list,
        const ArchiveFilters(hideFailed: true),
      );
      expect(_ids(out), [1]);
    });

    test('ukryj duplikaty zachowuje oryginał (sequence 0)', () {
      final list = [
        _a(1, duplicateCount: 1, duplicateSequence: 0),
        _a(2, duplicateCount: 1, duplicateSequence: 1),
        _a(3, duplicateCount: 0, duplicateSequence: 0),
      ];
      final out = applyArchiveFilters(
        list,
        const ArchiveFilters(hideDuplicates: true),
      );
      expect(_ids(out)..sort(), [1, 3]);
    });

    test('filtr typu pliku: sliced vs source', () {
      final list = [
        _a(1, filename: 'a.gcode'),
        _a(2, filename: 'b.3mf'),
        _a(3, filename: 'c.3mf', totalLayers: 50),
      ];
      expect(
        _ids(
          applyArchiveFilters(
            list,
            const ArchiveFilters(fileType: ArchiveFileType.gcode),
          ),
        )..sort(),
        [1, 3],
      );
      expect(
        _ids(
          applyArchiveFilters(
            list,
            const ArchiveFilters(fileType: ArchiveFileType.source),
          ),
        ),
        [2],
      );
    });

    test('sortowanie po nazwie i rozmiarze', () {
      final list = [
        _a(1, name: 'Bravo', fileSize: 300),
        _a(2, name: 'alpha', fileSize: 100),
        _a(3, name: 'Charlie', fileSize: 200),
      ];
      expect(
        _ids(
          applyArchiveFilters(
            list,
            const ArchiveFilters(sort: ArchiveSort.nameAsc),
          ),
        ),
        [2, 1, 3],
      );
      expect(
        _ids(
          applyArchiveFilters(
            list,
            const ArchiveFilters(sort: ArchiveSort.sizeDesc),
          ),
        ),
        [1, 3, 2],
      );
    });

    test('filtry łączą się przez AND', () {
      final list = [
        _a(1, name: 'Benchy', printerId: 10, favorite: true),
        _a(2, name: 'Benchy', printerId: 20, favorite: true),
        _a(3, name: 'Other', printerId: 10, favorite: true),
      ];
      final out = applyArchiveFilters(
        list,
        const ArchiveFilters(
          query: 'benchy',
          printerId: 10,
          favoritesOnly: true,
        ),
      );
      expect(_ids(out), [1]);
    });
  });

  group('ArchiveFilters.activeCount', () {
    test('domyślne = 0; search i sort się nie liczą', () {
      expect(const ArchiveFilters().activeCount, 0);
      expect(
        const ArchiveFilters(query: 'x', sort: ArchiveSort.nameAsc).activeCount,
        0,
      );
    });

    test('liczy aktywne filtry', () {
      expect(
        const ArchiveFilters(
          printerId: 1,
          favoritesOnly: true,
          hideFailed: true,
        ).activeCount,
        3,
      );
    });
  });

  group('ArchiveFilters.copyWith', () {
    test('clearPrinter / clearMaterial czyszczą pola nullable', () {
      const f = ArchiveFilters(printerId: 1, material: 'PLA');
      expect(f.copyWith(clearPrinter: true).printerId, isNull);
      expect(f.copyWith(clearMaterial: true).material, isNull);
      // Bez flagi clear pole zostaje.
      expect(f.copyWith(favoritesOnly: true).printerId, 1);
    });
  });
}
