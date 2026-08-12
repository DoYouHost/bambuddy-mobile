import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/api/server_version.dart';
import '../core/api/server_version_service.dart';
import '../core/models/json_utils.dart';
import '../core/models/library_file.dart';
import '../core/models/library_folder.dart';
import '../core/models/library_stats.dart';
import '../core/models/library_tag.dart';
import '../core/models/trash_file.dart';
import '../core/models/variant_group.dart';

/// REST data source for file manager / library.
///
/// Auth adds [AuthInterceptor] to the shared Dio (thumbnails go separately via
/// `?token=` — see `LibraryThumbnail`). Each method maps [DioException] to
/// [AppApiException].
class LibraryRepository {
  LibraryRepository(this._dio, [this._serverVersion]);

  final Dio _dio;

  /// Fallback for whether variant groups exist here, used until a file listing
  /// has shown it. Optional because the read-only callers never ask, and a
  /// missing service reads the same as an unknown version: no variants, which
  /// every server generation is happy with.
  final ServerVersionService? _serverVersion;

  /// What the server's own file listing showed, once one has arrived.
  ///
  /// Outranks the version number for the same reason
  /// `QueueRepository._observedTriState` does: `variant_count` is a
  /// non-optional field on 1.2.6's `FileListResponse` and absent before it, so
  /// its presence answers outright what a version string can only suggest.
  /// Null until a listing with at least one row has been parsed — an empty
  /// library reveals nothing either way.
  bool? _observedVariants;

  /// Whether this server groups library files into cross-model variant sets.
  ///
  /// Observation first, version second, `false` when neither knows — so the
  /// grouping actions stay hidden rather than 404ing on an older server.
  Future<bool> supportsCrossModelVariants() async {
    final observed = _observedVariants;
    if (observed != null) return observed;
    return await _serverVersion?.supports(ServerFeature.crossModelVariants) ??
        false;
  }

  /// Records whether a parsed listing carried the 1.2.6 variant fields. Reads
  /// the raw rows rather than the model, because the model cannot distinguish
  /// "absent" from the `0` it defaults to.
  void _observeVariantSupport(List<dynamic> rows) {
    final firstMap = rows.whereType<Map<String, dynamic>>().firstOrNull;
    if (firstMap == null) return;
    _observedVariants = firstMap.containsKey('variant_count');
  }

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
    _observeVariantSupport(body);
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
    _observeVariantSupport(body);
    return parseJsonList(body, LibraryFile.fromJson);
  }

  /// GET /library/files?tag_ids=… — every file carrying ALL of [tagIds].
  ///
  /// A separate method rather than a parameter on [listFiles] because the
  /// server drops the folder scope entirely once `tag_ids` is present: tags are
  /// cross-cutting, so the answer is library-wide by design. Sending
  /// `folder_id` alongside would suggest otherwise. Dio serializes the list as
  /// repeated `tag_ids=` keys, which is what FastAPI's `Query` list expects.
  Future<List<LibraryFile>> listFilesByTags(List<int> tagIds) async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.libraryFiles,
        queryParameters: {'tag_ids': tagIds},
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

  // --- Tags ---

  /// GET /library/tags — the whole catalog, alphabetical, with file counts.
  ///
  /// Returns `null` when the server has no tag catalog at all (404 — the routes
  /// arrived in bambuddy 1.2.5). That is the app's feature gate: the tag
  /// controls stay hidden instead of offering buttons that can only fail. Any
  /// other failure is a real error and propagates, so a network blip shows as an
  /// error rather than silently removing the feature.
  Future<List<LibraryTag>?> listTags() async {
    try {
      final body = await guard(() async {
        final res = await _dio.get<List<dynamic>>(Endpoints.libraryTags);
        return res.data ?? const [];
      });
      return parseJsonList(body, LibraryTag.fromJson);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// POST /library/tags — create a tag. Names are unique case-insensitively;
  /// a duplicate answers 409, which reaches the caller as [ApiException] with
  /// `statusCode == 409`.
  Future<LibraryTag> createTag(String name) => guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.libraryTags,
          data: <String, dynamic>{'name': name},
        );
        return LibraryTag.fromJson(res.data ?? const {});
      });

  /// PATCH /library/tags/{id} — rename a tag (409 on duplicate name).
  Future<void> renameTag(int tagId, String name) => guard(() => _dio.patch<dynamic>(
        Endpoints.libraryTag(tagId),
        data: <String, dynamic>{'name': name},
      ));

  /// DELETE /library/tags/{id} — drop the tag; tagged files keep everything
  /// else, they just lose this label.
  Future<void> deleteTag(int tagId) =>
      guard(() => _dio.delete<dynamic>(Endpoints.libraryTag(tagId)));

  /// POST /library/tags/bulk-assign — add / remove / replace [tagIds] across
  /// [fileIds]. See [TagAssignResult.filesUpdated] for partial application.
  Future<TagAssignResult> assignTags({
    required List<int> fileIds,
    required List<int> tagIds,
    required TagAssignAction action,
  }) =>
      guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.libraryTagsBulkAssign,
          data: <String, dynamic>{
            'file_ids': fileIds,
            'tag_ids': tagIds,
            'action': action.wire,
          },
        );
        return TagAssignResult.fromJson(res.data ?? const {});
      });

  // --- Variant groups (server #671, 1.2.6+) ---
  //
  // Gate every entry point on [supportsCrossModelVariants]: an older server
  // 404s these paths, which would surface as a generic failure.

  /// GET /library/variant-groups/by-file/{id} — the group [fileId] belongs to.
  ///
  /// Null rather than an exception when it belongs to none: the server says so
  /// with a 404, and "this file is not grouped" is the ordinary answer, not a
  /// failure. A 404 from an older server that has no such route reads the same
  /// and is equally harmless.
  Future<VariantGroup?> variantGroupForFile(int fileId) async {
    try {
      final body = await guard(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          Endpoints.libraryVariantGroupByFile(fileId),
        );
        return res.data ?? const <String, dynamic>{};
      });
      return VariantGroup.fromJson(body);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// POST /library/variant-groups — group [fileIds] as alternatives, in the
  /// order given (that order is the dispatch priority).
  ///
  /// Two files minimum. The server answers 409 when one already belongs to
  /// another group and 400 when the same file is listed twice, both of which
  /// travel as an [AppApiException] for the caller to show.
  Future<VariantGroup> createVariantGroup(
    List<int> fileIds, {
    String? name,
  }) =>
      guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.libraryVariantGroups,
          data: <String, dynamic>{
            'members': [
              for (final id in fileIds) <String, dynamic>{'library_file_id': id},
            ],
            'name': ?name,
          },
        );
        return VariantGroup.fromJson(res.data ?? const {});
      });

  /// PATCH /library/variant-groups/{id} — rename and/or re-prioritise.
  ///
  /// [memberFileIds] must list *exactly* the group's current members; the
  /// server rejects a partial list rather than guessing where the omitted ones
  /// belong. Pass null to leave the order alone.
  Future<VariantGroup> updateVariantGroup(
    int groupId, {
    String? name,
    List<int>? memberFileIds,
  }) =>
      guard(() async {
        final res = await _dio.patch<Map<String, dynamic>>(
          Endpoints.libraryVariantGroup(groupId),
          data: <String, dynamic>{
            'name': ?name,
            'member_file_ids': ?memberFileIds,
          },
        );
        return VariantGroup.fromJson(res.data ?? const {});
      });

  /// POST /library/variant-groups/{id}/members — add [fileId] at the end.
  Future<VariantGroup> addVariantGroupMember(int groupId, int fileId) =>
      guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.libraryVariantGroupMembers(groupId),
          data: <String, dynamic>{'library_file_id': fileId},
        );
        return VariantGroup.fromJson(res.data ?? const {});
      });

  /// DELETE /library/variant-groups/{id}/members/{fileId}.
  ///
  /// Removing the second-to-last member dissolves the group entirely, so the
  /// caller must reload the listing rather than patching one row.
  Future<void> removeVariantGroupMember(int groupId, int fileId) =>
      guard(() => _dio.delete<dynamic>(
            Endpoints.libraryVariantGroupMember(groupId, fileId),
          ));

  /// DELETE /library/variant-groups/{id} — ungroup; the files stay put.
  Future<void> deleteVariantGroup(int groupId) => guard(
      () => _dio.delete<dynamic>(Endpoints.libraryVariantGroup(groupId)));

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
