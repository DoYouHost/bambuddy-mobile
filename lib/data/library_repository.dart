import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/library_file.dart';
import '../core/models/library_folder.dart';
import '../core/models/library_stats.dart';
import '../core/models/trash_file.dart';

/// REST data source for file manager / library.
///
/// Auth adds [AuthInterceptor] to the shared Dio (thumbnails go separately via
/// `?token=` — see `LibraryThumbnail`). Each method maps [DioException] to
/// [AppApiException].
class LibraryRepository {
  LibraryRepository(this._dio);

  final Dio _dio;

  /// GET /library/files — files in folder [folderId] (null = root).
  /// Defensive parsing: unparseable entries are skipped.
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

  /// GET /library/files?include_root=false — ALL files from entire library (all folders)
  /// for global search. Defensive parsing.
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

  /// GET /library/folders — full folder tree (nested). We flatten navigation by
  /// [LibraryFolder.parentId], so return tree roots.
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

  /// GET /library/stats — library stats (best-effort; missing fields tolerated).
  Future<LibraryStats> stats() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(Endpoints.libraryStats);
      return LibraryStats.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  // --- Folders: CRUD ---

  /// POST /library/folders — create folder named [name] in [parentId] (null = root).
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

  /// PUT /library/folders/{id} — rename folder.
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

  /// DELETE /library/folders/{id} — delete folder and contents.
  Future<void> deleteFolder(int folderId) async {
    try {
      await _dio.delete<dynamic>(Endpoints.libraryFolder(folderId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  // --- Files: edit / move / delete ---

  /// PUT /library/files/{id} — rename file.
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

  /// POST /library/files/move — move files to folder [folderId] (null = root).
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

  /// DELETE /library/files/{id} — move file to trash.
  Future<void> deleteFile(int fileId) async {
    try {
      await _dio.delete<dynamic>(Endpoints.libraryFile(fileId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// POST /library/bulk-delete — bulk move files and folders to trash.
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

  // --- Print / queue ---

  /// POST /library/files/{id}/print?printer_id=… — send file to print. Empty body
  /// (default slicer settings server-side).
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

  /// POST /library/files/add-to-queue — add files to queue.
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

  /// POST /library/files — upload file to folder [folderId] (null = root).
  /// [onProgress] receives a fraction 0..1 (or null if size is unknown).
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
        // Upload can be large — disable send/receive timeout for this request.
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

  // --- Trash ---

  /// GET /library/trash — files in trash.
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

  /// POST /library/trash/{id}/restore — restore file from trash.
  Future<void> restoreFromTrash(int fileId) async {
    try {
      await _dio.post<dynamic>(Endpoints.libraryTrashRestore(fileId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// DELETE /library/trash/{id} — permanently delete file from trash.
  Future<void> hardDelete(int fileId) async {
    try {
      await _dio.delete<dynamic>(Endpoints.libraryTrashItem(fileId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// DELETE /library/trash — empty trash (permanent).
  Future<void> emptyTrash() async {
    try {
      await _dio.delete<dynamic>(Endpoints.libraryTrash);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
