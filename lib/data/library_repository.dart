import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/json_utils.dart';
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
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.libraryFiles,
        queryParameters: query,
      );
      return res.data ?? const [];
    });
    return parseJsonList(body, LibraryFile.fromJson);
  }

  /// GET /library/files?include_root=false — ALL files from entire library (all folders)
  /// for global search. Defensive parsing.
  Future<List<LibraryFile>> listAllFiles() async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.libraryFiles,
        queryParameters: {'include_root': false},
      );
      return res.data ?? const [];
    });
    return parseJsonList(body, LibraryFile.fromJson);
  }

  /// GET /library/folders — full folder tree (nested). We flatten navigation by
  /// [LibraryFolder.parentId], so return tree roots.
  Future<List<LibraryFolder>> listFolders() async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(Endpoints.libraryFolders);
      return res.data ?? const [];
    });
    return parseJsonList(body, LibraryFolder.fromJson);
  }

  /// GET /library/stats — library stats (best-effort; missing fields tolerated).
  Future<LibraryStats> stats() => guard(() async {
        final res = await _dio.get<Map<String, dynamic>>(Endpoints.libraryStats);
        return LibraryStats.fromJson(res.data ?? const {});
      });

  // --- Folders: CRUD ---

  /// POST /library/folders — create folder named [name] in [parentId] (null = root).
  Future<void> createFolder(String name, {int? parentId}) => guard(() => _dio.post<dynamic>(
        Endpoints.libraryFolders,
        data: <String, dynamic>{
          'name': name,
          'parent_id': ?parentId,
        },
      ));

  /// PUT /library/folders/{id} — rename folder.
  Future<void> renameFolder(int folderId, String name) => guard(() => _dio.put<dynamic>(
        Endpoints.libraryFolder(folderId),
        data: <String, dynamic>{'name': name},
      ));

  /// DELETE /library/folders/{id} — delete folder and contents.
  Future<void> deleteFolder(int folderId) =>
      guard(() => _dio.delete<dynamic>(Endpoints.libraryFolder(folderId)));

  // --- Files: edit / move / delete ---

  /// PUT /library/files/{id} — rename file.
  Future<void> renameFile(int fileId, String filename) => guard(() => _dio.put<dynamic>(
        Endpoints.libraryFile(fileId),
        data: <String, dynamic>{'filename': filename},
      ));

  /// POST /library/files/move — move files to folder [folderId] (null = root).
  Future<void> moveFiles(List<int> fileIds, {int? folderId}) => guard(() => _dio.post<dynamic>(
        Endpoints.libraryFilesMove,
        data: <String, dynamic>{'file_ids': fileIds, 'folder_id': folderId},
      ));

  /// DELETE /library/files/{id} — move file to trash.
  Future<void> deleteFile(int fileId) =>
      guard(() => _dio.delete<dynamic>(Endpoints.libraryFile(fileId)));

  /// POST /library/bulk-delete — bulk move files and folders to trash.
  Future<void> bulkDelete({
    List<int> fileIds = const [],
    List<int> folderIds = const [],
  }) =>
      guard(() => _dio.post<dynamic>(
            Endpoints.libraryBulkDelete,
            data: <String, dynamic>{
              'file_ids': fileIds,
              'folder_ids': folderIds,
            },
          ));

  // --- Print / queue ---

  /// POST /library/files/{id}/print?printer_id=… — send file to print. Empty body
  /// (default slicer settings server-side).
  Future<void> printFile(int fileId, {required int printerId}) => guard(() => _dio.post<dynamic>(
        Endpoints.libraryFilePrint(fileId),
        queryParameters: {'printer_id': printerId},
      ));

  /// POST /library/files/add-to-queue — add files to queue.
  Future<void> addToQueue(List<int> fileIds) => guard(() => _dio.post<dynamic>(
        Endpoints.libraryFilesAddToQueue,
        data: <String, dynamic>{'file_ids': fileIds},
      ));

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
    await guard(() async {
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
    });
  }

  // --- Trash ---

  /// GET /library/trash — files in trash.
  Future<List<TrashFile>> listTrash() async {
    final body = await guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(Endpoints.libraryTrash);
      return res.data ?? const {};
    });
    return parseJsonList(body['items'], TrashFile.fromJson);
  }

  /// POST /library/trash/{id}/restore — restore file from trash.
  Future<void> restoreFromTrash(int fileId) =>
      guard(() => _dio.post<dynamic>(Endpoints.libraryTrashRestore(fileId)));

  /// DELETE /library/trash/{id} — permanently delete file from trash.
  Future<void> hardDelete(int fileId) =>
      guard(() => _dio.delete<dynamic>(Endpoints.libraryTrashItem(fileId)));

  /// DELETE /library/trash — empty trash (permanent).
  Future<void> emptyTrash() => guard(() => _dio.delete<dynamic>(Endpoints.libraryTrash));
}
