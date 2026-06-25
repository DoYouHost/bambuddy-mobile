import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/library_file.dart';
import '../../core/models/library_folder.dart';
import '../../core/models/library_stats.dart';
import '../../core/models/trash_file.dart';
import '../../providers.dart';

/// Klucze sortowania listy plików (po stronie klienta — endpoint nie sortuje).
enum FileSort { dateDesc, dateAsc, nameAsc, nameDesc, sizeDesc, sizeAsc }

/// Stan menedżera plików: drzewo folderów (płaskie), bieżący folder, pliki
/// w nim oraz filtry/sortowanie i tryb zaznaczania (bulk).
class FileManagerState {
  const FileManagerState({
    this.allFolders = const [],
    this.currentFolderId,
    this.files = const [],
    this.allFiles,
    this.searching = false,
    this.query = '',
    this.typeFilter,
    this.sort = FileSort.dateDesc,
    this.selected = const {},
    this.selectionMode = false,
  });

  /// Wszystkie foldery spłaszczone (do budowy ścieżki i listy podfolderów).
  final List<LibraryFolder> allFolders;

  /// Bieżący folder; `null` = poziom root.
  final int? currentFolderId;

  /// Pliki w bieżącym folderze (surowe, przed filtrem/sortem).
  final List<LibraryFile> files;

  /// Wszystkie pliki z całej biblioteki — cache pod wyszukiwanie globalne.
  /// `null` = jeszcze niepobrane (pobierane leniwie przy pierwszym zapytaniu).
  final List<LibraryFile>? allFiles;

  /// Trwa pobieranie [allFiles] do wyszukiwania globalnego.
  final bool searching;

  final String query;

  /// Filtr po typie pliku (np. „3mf"); `null` = wszystkie.
  final String? typeFilter;

  final FileSort sort;

  /// Zaznaczone pliki (tryb bulk).
  final Set<int> selected;
  final bool selectionMode;

  FileManagerState copyWith({
    List<LibraryFolder>? allFolders,
    int? currentFolderId,
    bool clearCurrentFolder = false,
    List<LibraryFile>? files,
    List<LibraryFile>? allFiles,
    bool clearAllFiles = false,
    bool? searching,
    String? query,
    String? typeFilter,
    bool clearTypeFilter = false,
    FileSort? sort,
    Set<int>? selected,
    bool? selectionMode,
  }) =>
      FileManagerState(
        allFolders: allFolders ?? this.allFolders,
        currentFolderId:
            clearCurrentFolder ? null : (currentFolderId ?? this.currentFolderId),
        files: files ?? this.files,
        allFiles: clearAllFiles ? null : (allFiles ?? this.allFiles),
        searching: searching ?? this.searching,
        query: query ?? this.query,
        typeFilter: clearTypeFilter ? null : (typeFilter ?? this.typeFilter),
        sort: sort ?? this.sort,
        selected: selected ?? this.selected,
        selectionMode: selectionMode ?? this.selectionMode,
      );

  /// Bieżący folder jako obiekt (null na poziomie root).
  LibraryFolder? get currentFolder =>
      currentFolderId == null ? null : _byId(currentFolderId);

  LibraryFolder? _byId(int? id) {
    for (final f in allFolders) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Ścieżka okruszków od root do bieżącego folderu (bez root-a).
  List<LibraryFolder> get breadcrumb {
    final path = <LibraryFolder>[];
    var node = currentFolder;
    while (node != null) {
      path.insert(0, node);
      node = _byId(node.parentId);
    }
    return path;
  }

  /// Podfoldery bieżącego folderu (sortowane alfabetycznie).
  List<LibraryFolder> get subfolders {
    final list = allFolders
        .where((f) => f.parentId == currentFolderId)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Czy aktywne jest wyszukiwanie (zapytanie niepuste → tryb globalny).
  bool get isSearching => query.trim().isNotEmpty;

  /// Nazwa folderu po id (do etykiety lokalizacji w wynikach wyszukiwania).
  String? folderName(int? id) => _byId(id)?.name;

  /// Źródło listy plików: w trybie wyszukiwania cała biblioteka, inaczej
  /// bieżący folder.
  List<LibraryFile> get _source =>
      isSearching ? (allFiles ?? files) : files;

  /// Dostępne typy plików (do filtra) — z aktualnego źródła.
  List<String> get availableTypes {
    final set = <String>{for (final f in _source) f.fileType.toLowerCase()};
    final list = set.toList()..sort();
    return list;
  }

  /// Pliki po zastosowaniu wyszukiwania, filtra typu i sortowania.
  List<LibraryFile> get visibleFiles {
    final q = query.trim().toLowerCase();
    final filtered = _source.where((f) {
      if (typeFilter != null && f.fileType.toLowerCase() != typeFilter) {
        return false;
      }
      if (q.isEmpty) return true;
      return f.filename.toLowerCase().contains(q) ||
          (f.printName?.toLowerCase().contains(q) ?? false);
    }).toList();

    int byName(LibraryFile a, LibraryFile b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    int byDate(LibraryFile a, LibraryFile b) {
      final da = a.createdAt, db = b.createdAt;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    }

    filtered.sort((a, b) => switch (sort) {
          FileSort.nameAsc => byName(a, b),
          FileSort.nameDesc => byName(b, a),
          FileSort.sizeAsc => a.fileSize.compareTo(b.fileSize),
          FileSort.sizeDesc => b.fileSize.compareTo(a.fileSize),
          FileSort.dateAsc => byDate(a, b),
          FileSort.dateDesc => byDate(b, a),
        });
    return filtered;
  }
}

final fileManagerProvider =
    AutoDisposeAsyncNotifierProvider<FileManagerNotifier, FileManagerState>(
  FileManagerNotifier.new,
);

/// Menedżer plików: nawigacja po folderach, lista plików, filtry i akcje.
class FileManagerNotifier extends AutoDisposeAsyncNotifier<FileManagerState> {
  @override
  Future<FileManagerState> build() async {
    ref.watch(serverProfileProvider);
    final repo = ref.read(libraryRepositoryProvider);
    final folders = await repo.listFolders();
    final files = await repo.listFiles(folderId: null);
    return FileManagerState(
      allFolders: _flatten(folders),
      files: files,
    );
  }

  /// Spłaszcza zagnieżdżone drzewo folderów do jednej listy.
  List<LibraryFolder> _flatten(List<LibraryFolder> roots) {
    final out = <LibraryFolder>[];
    void walk(List<LibraryFolder> nodes) {
      for (final n in nodes) {
        out.add(n);
        if (n.children.isNotEmpty) walk(n.children);
      }
    }

    walk(roots);
    return out;
  }

  /// Wchodzi do folderu [folderId] (null = root) i pobiera jego pliki.
  /// Czyści zaznaczenie i wyszukiwanie.
  Future<void> openFolder(int? folderId) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = const AsyncValue<FileManagerState>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(() async {
      final repo = ref.read(libraryRepositoryProvider);
      final files = await repo.listFiles(folderId: folderId);
      return current.copyWith(
        currentFolderId: folderId,
        clearCurrentFolder: folderId == null,
        files: files,
        clearAllFiles: true,
        searching: false,
        query: '',
        clearTypeFilter: true,
        selected: const {},
        selectionMode: false,
      );
    });
  }

  /// Odświeża bieżący folder oraz drzewo folderów (po mutacjach).
  Future<void> refresh() async {
    final current = state.valueOrNull;
    final folderId = current?.currentFolderId;
    state = const AsyncValue<FileManagerState>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(() async {
      final repo = ref.read(libraryRepositoryProvider);
      final folders = await repo.listFolders();
      final files = await repo.listFiles(folderId: folderId);
      final flat = _flatten(folders);
      // Folder mógł zniknąć (usunięty) — wróć do root.
      final stillExists =
          folderId == null || flat.any((f) => f.id == folderId);
      return FileManagerState(
        allFolders: flat,
        currentFolderId: stillExists ? folderId : null,
        files: stillExists ? files : await repo.listFiles(folderId: null),
        sort: current?.sort ?? FileSort.dateDesc,
      );
    });
  }

  /// Ustawia zapytanie. Pierwsze niepuste zapytanie pobiera leniwie wszystkie
  /// pliki biblioteki (cache [FileManagerState.allFiles]) — wyszukiwanie jest
  /// globalne (po wszystkich folderach), nie tylko po bieżącym.
  Future<void> setQuery(String q) async {
    var current = state.valueOrNull;
    if (current == null) return;
    final needsFetch = q.trim().isNotEmpty && current.allFiles == null;
    state = AsyncValue.data(
      current.copyWith(query: q, searching: needsFetch),
    );
    if (!needsFetch) return;
    try {
      final all = await ref.read(libraryRepositoryProvider).listAllFiles();
      current = state.valueOrNull;
      if (current == null) return;
      state = AsyncValue.data(current.copyWith(allFiles: all, searching: false));
    } on Object {
      current = state.valueOrNull;
      if (current != null) {
        state = AsyncValue.data(current.copyWith(searching: false));
      }
    }
  }

  void setType(String? type) => _update(
        (s) => s.copyWith(typeFilter: type, clearTypeFilter: type == null),
      );

  void setSort(FileSort sort) => _update((s) => s.copyWith(sort: sort));

  void toggleSelect(int fileId) => _update((s) {
        final next = {...s.selected};
        next.contains(fileId) ? next.remove(fileId) : next.add(fileId);
        return s.copyWith(selected: next, selectionMode: next.isNotEmpty);
      });

  void clearSelection() =>
      _update((s) => s.copyWith(selected: const {}, selectionMode: false));

  void _update(FileManagerState Function(FileManagerState) fn) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(fn(current));
  }
}

/// Statystyki biblioteki (nagłówek). Osobny provider — odświeżany niezależnie.
final libraryStatsProvider = FutureProvider.autoDispose<LibraryStats>(
  (ref) => ref.watch(libraryRepositoryProvider).stats(),
);

/// Lista plików w koszu.
final libraryTrashProvider = FutureProvider.autoDispose<List<TrashFile>>(
  (ref) => ref.watch(libraryRepositoryProvider).listTrash(),
);
