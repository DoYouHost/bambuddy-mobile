import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/library_file.dart';
import '../../core/models/library_folder.dart';
import '../../core/models/library_stats.dart';
import '../../core/models/trash_file.dart';
import '../../providers.dart';

/// File list sort keys (client-side — endpoint doesn't sort).
enum FileSort { dateDesc, dateAsc, nameAsc, nameDesc, sizeDesc, sizeAsc }

/// File manager state: folder tree (flat), current folder, files in it,
/// plus filters/sorting and selection (bulk) mode.
class FileManagerState {
  const FileManagerState({
    this.allFolders = const [],
    this.currentFolderId,
    this.files = const [],
    this.allFiles,
    this.searching = false,
    this.searchFailed = false,
    this.query = '',
    this.typeFilter,
    this.sort = FileSort.dateDesc,
    this.selected = const {},
    this.selectionMode = false,
  });

  /// All folders flattened (for breadcrumb and subfolder list).
  final List<LibraryFolder> allFolders;

  /// Current folder; `null` = root level.
  final int? currentFolderId;

  /// Files in current folder (raw, before filter/sort).
  final List<LibraryFile> files;

  /// All files from entire library — cache for global search.
  /// `null` = not yet fetched (loaded lazily on first query).
  final List<LibraryFile>? allFiles;

  /// Fetching [allFiles] for global search in progress.
  final bool searching;

  /// The last [allFiles] fetch failed — UI shows a gentle message instead of
  /// silently clearing the spinner into an empty-looking result.
  final bool searchFailed;

  final String query;

  /// File type filter (e.g. "3mf"); `null` = all.
  final String? typeFilter;

  final FileSort sort;

  /// Selected files (bulk mode).
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
    bool? searchFailed,
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
        searchFailed: searchFailed ?? this.searchFailed,
        query: query ?? this.query,
        typeFilter: clearTypeFilter ? null : (typeFilter ?? this.typeFilter),
        sort: sort ?? this.sort,
        selected: selected ?? this.selected,
        selectionMode: selectionMode ?? this.selectionMode,
      );

  /// Current folder as object (null at root level).
  LibraryFolder? get currentFolder =>
      currentFolderId == null ? null : _byId(currentFolderId);

  LibraryFolder? _byId(int? id) {
    for (final f in allFolders) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Breadcrumb path from root to current folder (without root).
  List<LibraryFolder> get breadcrumb {
    final path = <LibraryFolder>[];
    var node = currentFolder;
    while (node != null) {
      path.insert(0, node);
      node = _byId(node.parentId);
    }
    return path;
  }

  /// Subfolders of current folder (sorted alphabetically).
  List<LibraryFolder> get subfolders {
    final list = allFolders
        .where((f) => f.parentId == currentFolderId)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Whether searching is active (non-empty query → global mode).
  bool get isSearching => query.trim().isNotEmpty;

  /// Folder name by id (for location label in search results).
  String? folderName(int? id) => _byId(id)?.name;

  /// File list source: in search mode all library, otherwise current folder.
  List<LibraryFile> get _source =>
      isSearching ? (allFiles ?? files) : files;

  /// Available file types (for filter) — from current source.
  List<String> get availableTypes {
    final set = <String>{for (final f in _source) f.fileType.toLowerCase()};
    final list = set.toList()..sort();
    return list;
  }

  /// Files after search, type filter, and sorting applied.
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

/// File manager: folder navigation, file list, filters, and actions.
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

  /// Flattens nested folder tree to a single list.
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

  /// Opens folder [folderId] (null = root) and fetches its files.
  /// Clears selection and search.
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

  /// Refreshes current folder and folder tree (after mutations).
  Future<void> refresh() async {
    final current = state.valueOrNull;
    final folderId = current?.currentFolderId;
    state = const AsyncValue<FileManagerState>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(() async {
      final repo = ref.read(libraryRepositoryProvider);
      final folders = await repo.listFolders();
      final files = await repo.listFiles(folderId: folderId);
      final flat = _flatten(folders);
      // Folder may have disappeared (deleted) — back to root.
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

  /// Whether a [listAllFiles] fetch is currently in flight — guards against
  /// two quick queries (typed faster than the first fetch resolves) both
  /// seeing `allFiles == null` and firing a redundant parallel fetch.
  bool _fetchingAllFiles = false;

  /// Sets query. First non-empty query lazily fetches all library files
  /// (cache [FileManagerState.allFiles]) — search is global (all folders),
  /// not just current.
  Future<void> setQuery(String q) async {
    var current = state.valueOrNull;
    if (current == null) return;
    final needsFetch =
        q.trim().isNotEmpty && current.allFiles == null && !_fetchingAllFiles;
    state = AsyncValue.data(
      current.copyWith(query: q, searching: needsFetch || current.searching),
    );
    if (!needsFetch) return;
    _fetchingAllFiles = true;
    try {
      final all = await ref.read(libraryRepositoryProvider).listAllFiles();
      current = state.valueOrNull;
      if (current == null) return;
      state = AsyncValue.data(
        current.copyWith(allFiles: all, searching: false, searchFailed: false),
      );
    } on Object {
      current = state.valueOrNull;
      if (current != null) {
        state = AsyncValue.data(
          current.copyWith(searching: false, searchFailed: true),
        );
      }
    } finally {
      _fetchingAllFiles = false;
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

/// Library stats (header). Separate provider — refreshed independently.
final libraryStatsProvider = FutureProvider.autoDispose<LibraryStats>(
  (ref) => ref.watch(libraryRepositoryProvider).stats(),
);

/// List of files in trash.
final libraryTrashProvider = FutureProvider.autoDispose<List<TrashFile>>(
  (ref) => ref.watch(libraryRepositoryProvider).listTrash(),
);
