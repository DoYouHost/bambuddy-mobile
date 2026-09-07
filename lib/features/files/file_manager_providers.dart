import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/library_file.dart';
import '../../core/models/library_folder.dart';
import '../../core/models/library_stats.dart';
import '../../core/models/library_tag.dart';
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
    this.fetchFailed = false,
    this.query = '',
    this.tagFilter = const {},
    this.tagFiles,
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

  /// Fetching a library-wide list ([allFiles] for search, [tagFiles] for the
  /// tag filter) is in progress.
  final bool searching;

  /// The last library-wide fetch failed — UI shows a gentle message instead of
  /// silently clearing the spinner into an empty-looking result.
  final bool fetchFailed;

  final String query;

  /// Tags the listing is filtered by (AND — a file must carry all of them).
  /// Non-empty switches the list to [tagFiles], which the server resolves
  /// library-wide: tags are cross-cutting, so the current folder is ignored on
  /// purpose (the same rule the web UI follows).
  final Set<int> tagFilter;

  /// Files matching [tagFilter], as answered by the server. `null` = not
  /// fetched yet for the current selection.
  final List<LibraryFile>? tagFiles;

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
    bool? fetchFailed,
    String? query,
    Set<int>? tagFilter,
    List<LibraryFile>? tagFiles,
    bool clearTagFiles = false,
    String? typeFilter,
    bool clearTypeFilter = false,
    FileSort? sort,
    Set<int>? selected,
    bool? selectionMode,
  }) => FileManagerState(
    allFolders: allFolders ?? this.allFolders,
    currentFolderId: clearCurrentFolder
        ? null
        : (currentFolderId ?? this.currentFolderId),
    files: files ?? this.files,
    allFiles: clearAllFiles ? null : (allFiles ?? this.allFiles),
    searching: searching ?? this.searching,
    fetchFailed: fetchFailed ?? this.fetchFailed,
    query: query ?? this.query,
    tagFilter: tagFilter ?? this.tagFilter,
    tagFiles: clearTagFiles ? null : (tagFiles ?? this.tagFiles),
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
    final list = allFolders.where((f) => f.parentId == currentFolderId).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Whether searching is active (non-empty query → global mode).
  bool get isSearching => query.trim().isNotEmpty;

  /// Whether the tag filter is active (→ library-wide mode, folders hidden).
  bool get isTagFiltering => tagFilter.isNotEmpty;

  /// Folder name by id (for location label in search results).
  String? folderName(int? id) => _byId(id)?.name;

  /// File list source: the tag-filtered set wins (it is already library-wide,
  /// and a query on top of it narrows within the filter), then global search,
  /// otherwise the current folder.
  List<LibraryFile> get _source => isTagFiltering
      ? (tagFiles ?? const [])
      : isSearching
      ? (allFiles ?? files)
      : files;

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

    filtered.sort(
      (a, b) => switch (sort) {
        FileSort.nameAsc => byName(a, b),
        FileSort.nameDesc => byName(b, a),
        FileSort.sizeAsc => a.fileSize.compareTo(b.fileSize),
        FileSort.sizeDesc => b.fileSize.compareTo(a.fileSize),
        FileSort.dateAsc => byDate(a, b),
        FileSort.dateDesc => byDate(b, a),
      },
    );
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
    return FileManagerState(allFolders: _flatten(folders), files: files);
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
  /// Clears selection, search and the tag filter — picking a folder is the
  /// opposite request to "show me this tag wherever it lives".
  Future<void> openFolder(int? folderId) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = const AsyncValue<FileManagerState>.loading().copyWithPrevious(
      state,
    );
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
        tagFilter: const {},
        clearTagFiles: true,
        clearTypeFilter: true,
        selected: const {},
        selectionMode: false,
      );
    });
  }

  /// Refreshes current folder and folder tree (after mutations).
  ///
  /// The tag filter survives a refresh and its list is re-fetched: re-tagging is
  /// itself a mutation, and dropping the filter here would throw the user back
  /// to the folder they happened to be standing in the moment they saved.
  Future<void> refresh() async {
    final current = state.valueOrNull;
    final folderId = current?.currentFolderId;
    final tagFilter = current?.tagFilter ?? const <int>{};
    state = const AsyncValue<FileManagerState>.loading().copyWithPrevious(
      state,
    );
    state = await AsyncValue.guard(() async {
      final repo = ref.read(libraryRepositoryProvider);
      final folders = await repo.listFolders();
      final files = await repo.listFiles(folderId: folderId);
      final flat = _flatten(folders);
      // Folder may have disappeared (deleted) — back to root.
      final stillExists = folderId == null || flat.any((f) => f.id == folderId);
      return FileManagerState(
        allFolders: flat,
        currentFolderId: stillExists ? folderId : null,
        files: stillExists ? files : await repo.listFiles(folderId: null),
        sort: current?.sort ?? FileSort.dateDesc,
        tagFilter: tagFilter,
        tagFiles: tagFilter.isEmpty
            ? null
            : await repo.listFilesByTags(tagFilter.toList()),
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
        current.copyWith(allFiles: all, searching: false, fetchFailed: false),
      );
    } on Object {
      current = state.valueOrNull;
      if (current != null) {
        state = AsyncValue.data(
          current.copyWith(searching: false, fetchFailed: true),
        );
      }
    } finally {
      _fetchingAllFiles = false;
    }
  }

  /// Filters the listing by [tagIds] (AND). Empty set clears the filter and
  /// returns to the folder listing already in [FileManagerState.files].
  ///
  /// The result is fetched per selection rather than filtered client-side: the
  /// server owns the AND semantics and the library-wide scope, and the folder
  /// listing we hold locally is only a slice of the library.
  Future<void> setTagFilter(Set<int> tagIds) async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (tagIds.isEmpty) {
      state = AsyncValue.data(
        current.copyWith(
          tagFilter: const {},
          clearTagFiles: true,
          searching: false,
          fetchFailed: false,
        ),
      );
      return;
    }
    state = AsyncValue.data(
      current.copyWith(
        tagFilter: tagIds,
        clearTagFiles: true,
        searching: true,
        fetchFailed: false,
      ),
    );
    try {
      final files = await ref
          .read(libraryRepositoryProvider)
          .listFilesByTags(tagIds.toList());
      final now = state.valueOrNull;
      // A selection changed while this was in flight — the newer call owns the
      // state, so drop this answer instead of showing the previous filter's
      // files under the current chips.
      if (now == null || !_sameTags(now.tagFilter, tagIds)) return;
      state = AsyncValue.data(
        now.copyWith(tagFiles: files, searching: false, fetchFailed: false),
      );
    } on Object {
      final now = state.valueOrNull;
      if (now == null || !_sameTags(now.tagFilter, tagIds)) return;
      state = AsyncValue.data(
        now.copyWith(searching: false, fetchFailed: true),
      );
    }
  }

  static bool _sameTags(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

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

/// Tag catalog. `null` (as a loaded value) means the server has no tag routes
/// at all — the whole tag UI hides itself then, see `LibraryRepository.listTags`.
final libraryTagsProvider = FutureProvider.autoDispose<List<LibraryTag>?>(
  (ref) => ref.watch(libraryRepositoryProvider).listTags(),
);

/// Whether tag controls should be offered at all. Unknown (still loading) counts
/// as supported so the buttons don't pop into the toolbar a moment late; only a
/// loaded `null` — the 404 gate — hides them.
bool libraryTagsSupported(AsyncValue<List<LibraryTag>?> tags) =>
    !tags.hasValue || tags.value != null;

/// List of files in trash.
final libraryTrashProvider = FutureProvider.autoDispose<List<TrashFile>>(
  (ref) => ref.watch(libraryRepositoryProvider).listTrash(),
);
