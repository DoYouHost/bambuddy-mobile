import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/library_file.dart';
import '../core/models/library_folder.dart';
import '../core/models/library_stats.dart';
import '../core/models/trash_file.dart';

/// REST-owe źródło danych menedżera plików / biblioteki.
///
/// Auth dokłada [AuthInterceptor] na współdzielonym Dio (miniatura idzie
/// osobno przez `?token=` — patrz `LibraryThumbnail`). Każda metoda mapuje
/// [DioException] na [AppApiException].
class LibraryRepository {
  LibraryRepository(this._dio);

  final Dio _dio;

  /// GET /library/files — pliki w folderze [folderId] (null = root).
  /// Defensywne parsowanie: niesparsowalny wpis jest pomijany.
  Future<List<LibraryFile>> listFiles({int? folderId}) async {
    final query = <String, dynamic>{
      'folder_id': folderId,
      'include_root': folderId == null,
    }..removeWhere((_, v) => v == null);
    final List<dynamic> body;
    try {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.libraryFiles,
        queryParameters: query,
      );
      body = res.data ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
    final files = <LibraryFile>[];
    for (final item in body) {
      if (item is! Map<String, dynamic>) continue;
      try {
        files.add(LibraryFile.fromJson(item));
      } on Object {
        continue;
      }
    }
    return files;
  }

  /// GET /library/files?include_root=false — WSZYSTKIE pliki z całej biblioteki
  /// (ze wszystkich folderów), do wyszukiwania globalnego. Defensywne parsowanie.
  Future<List<LibraryFile>> listAllFiles() async {
    final List<dynamic> body;
    try {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.libraryFiles,
        queryParameters: {'include_root': false},
      );
      body = res.data ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
    final files = <LibraryFile>[];
    for (final item in body) {
      if (item is! Map<String, dynamic>) continue;
      try {
        files.add(LibraryFile.fromJson(item));
      } on Object {
        continue;
      }
    }
    return files;
  }

  /// GET /library/folders — pełne drzewo folderów (zagnieżdżone). Spłaszczamy
  /// nawigację po [LibraryFolder.parentId], więc zwracamy korzenie drzewa.
  Future<List<LibraryFolder>> listFolders() async {
    final List<dynamic> body;
    try {
      final res = await _dio.get<List<dynamic>>(Endpoints.libraryFolders);
      body = res.data ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
    final folders = <LibraryFolder>[];
    for (final item in body) {
      if (item is! Map<String, dynamic>) continue;
      try {
        folders.add(LibraryFolder.fromJson(item));
      } on Object {
        continue;
      }
    }
    return folders;
  }

  /// GET /library/stats — statystyki biblioteki (best-effort; braki tolerowane).
  Future<LibraryStats> stats() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(Endpoints.libraryStats);
      return LibraryStats.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  // --- Foldery: CRUD ---

  /// POST /library/folders — utworzenie folderu o nazwie [name] w [parentId]
  /// (null = root).
  Future<void> createFolder(String name, {int? parentId}) async {
    try {
      await _dio.post<dynamic>(
        Endpoints.libraryFolders,
        data: <String, dynamic>{
          'name': name,
          'parent_id': ?parentId,
        },
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// PUT /library/folders/{id} — zmiana nazwy folderu.
  Future<void> renameFolder(int folderId, String name) async {
    try {
      await _dio.put<dynamic>(
        Endpoints.libraryFolder(folderId),
        data: <String, dynamic>{'name': name},
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// DELETE /library/folders/{id} — usunięcie folderu wraz z zawartością.
  Future<void> deleteFolder(int folderId) async {
    try {
      await _dio.delete<dynamic>(Endpoints.libraryFolder(folderId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  // --- Pliki: edycja / przenoszenie / usuwanie ---

  /// PUT /library/files/{id} — zmiana nazwy pliku.
  Future<void> renameFile(int fileId, String filename) async {
    try {
      await _dio.put<dynamic>(
        Endpoints.libraryFile(fileId),
        data: <String, dynamic>{'filename': filename},
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// POST /library/files/move — przeniesienie plików do folderu [folderId]
  /// (null = root).
  Future<void> moveFiles(List<int> fileIds, {int? folderId}) async {
    try {
      await _dio.post<dynamic>(
        Endpoints.libraryFilesMove,
        data: <String, dynamic>{'file_ids': fileIds, 'folder_id': folderId},
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// DELETE /library/files/{id} — przeniesienie pliku do kosza.
  Future<void> deleteFile(int fileId) async {
    try {
      await _dio.delete<dynamic>(Endpoints.libraryFile(fileId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// POST /library/bulk-delete — zbiorcze usunięcie plików i folderów do kosza.
  Future<void> bulkDelete({
    List<int> fileIds = const [],
    List<int> folderIds = const [],
  }) async {
    try {
      await _dio.post<dynamic>(
        Endpoints.libraryBulkDelete,
        data: <String, dynamic>{
          'file_ids': fileIds,
          'folder_ids': folderIds,
        },
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  // --- Druk / kolejka ---

  /// POST /library/files/{id}/print?printer_id=… — wysłanie pliku do druku.
  /// Body puste (domyślne ustawienia slicera po stronie serwera).
  Future<void> printFile(int fileId, {required int printerId}) async {
    try {
      await _dio.post<dynamic>(
        Endpoints.libraryFilePrint(fileId),
        queryParameters: {'printer_id': printerId},
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// POST /library/files/add-to-queue — dodanie plików do kolejki.
  Future<void> addToQueue(List<int> fileIds) async {
    try {
      await _dio.post<dynamic>(
        Endpoints.libraryFilesAddToQueue,
        data: <String, dynamic>{'file_ids': fileIds},
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  // --- Upload ---

  /// POST /library/files — wgranie pliku do folderu [folderId] (null = root).
  /// [onProgress] dostaje ułamek 0..1 (lub null, gdy rozmiar nieznany).
  Future<void> uploadFile({
    required String filePath,
    required String filename,
    int? folderId,
    void Function(double? progress)? onProgress,
  }) async {
    final query = <String, dynamic>{
      'folder_id': ?folderId,
      'generate_stl_thumbnails': true,
    };
    try {
      final form = FormData.fromMap(<String, dynamic>{
        'file': await MultipartFile.fromFile(filePath, filename: filename),
      });
      await _dio.post<dynamic>(
        Endpoints.libraryFiles,
        data: form,
        queryParameters: query,
        // Upload bywa duży — zdejmujemy limit czasu wysyłki dla tego żądania.
        options: Options(sendTimeout: Duration.zero, receiveTimeout: Duration.zero),
        onSendProgress: onProgress == null
            ? null
            : (sent, total) =>
                onProgress(total > 0 ? sent / total : null),
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  // --- Kosz ---

  /// GET /library/trash — pliki w koszu.
  Future<List<TrashFile>> listTrash() async {
    final Map<String, dynamic> body;
    try {
      final res = await _dio.get<Map<String, dynamic>>(Endpoints.libraryTrash);
      body = res.data ?? const {};
    } on DioException catch (e) {
      throw mapDioException(e);
    }
    final items = body['items'];
    final out = <TrashFile>[];
    if (items is List) {
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        try {
          out.add(TrashFile.fromJson(item));
        } on Object {
          continue;
        }
      }
    }
    return out;
  }

  /// POST /library/trash/{id}/restore — przywrócenie pliku z kosza.
  Future<void> restoreFromTrash(int fileId) async {
    try {
      await _dio.post<dynamic>(Endpoints.libraryTrashRestore(fileId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// DELETE /library/trash/{id} — trwałe usunięcie pliku z kosza.
  Future<void> hardDelete(int fileId) async {
    try {
      await _dio.delete<dynamic>(Endpoints.libraryTrashItem(fileId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// DELETE /library/trash — opróżnienie kosza (trwałe).
  Future<void> emptyTrash() async {
    try {
      await _dio.delete<dynamic>(Endpoints.libraryTrash);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
