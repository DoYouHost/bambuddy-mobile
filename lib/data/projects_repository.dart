import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/library_file.dart';
import '../core/models/library_folder.dart';
import '../core/models/project.dart';
import '../core/models/queue_item.dart';

/// REST data source for projects (full web parity): list/CRUD, templates,
/// import/export, archives, queue, BOM, attachments, cover image, timeline.
///
/// Auth adds [AuthInterceptor] to the shared Dio (cover image goes separately
/// via `?token=`). Each call maps [DioException] to [AppApiException]; list
/// parsing is defensive (unparseable entries skipped).
class ProjectsRepository {
  ProjectsRepository(this._dio);

  final Dio _dio;

  // --- Projects: list / CRUD ---

  /// GET /projects/ — optionally filtered by `status`.
  Future<List<ProjectListResponse>> list({String? status}) async {
    final query = <String, dynamic>{'status': ?status};
    final List<dynamic> body;
    try {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.projects,
        queryParameters: query.isEmpty ? null : query,
      );
      body = res.data ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
    return _parseList(body, ProjectListResponse.fromJson);
  }

  /// GET /projects/templates — projects flagged as templates.
  Future<List<ProjectListResponse>> listTemplates() async {
    final List<dynamic> body;
    try {
      final res = await _dio.get<List<dynamic>>(Endpoints.projectsTemplates);
      body = res.data ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
    return _parseList(body, ProjectListResponse.fromJson);
  }

  /// GET /projects/{id} — full detail.
  Future<ProjectResponse> get(int id) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(Endpoints.project(id));
      return ProjectResponse.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// POST /projects/ — create.
  Future<ProjectResponse> create(ProjectCreate body) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.projects,
        data: body.toMap(),
      );
      return ProjectResponse.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// PATCH /projects/{id} — partial update.
  Future<ProjectResponse> update(int id, ProjectUpdate body) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        Endpoints.project(id),
        data: body.toMap(),
      );
      return ProjectResponse.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// DELETE /projects/{id}.
  Future<void> delete(int id) async {
    try {
      await _dio.delete<dynamic>(Endpoints.project(id));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  // --- Templates / import / export ---

  /// POST /projects/from-template/{id}?name= — instantiate a template.
  Future<ProjectResponse> createFromTemplate(int templateId, String name) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.projectFromTemplate(templateId),
        queryParameters: {'name': name},
      );
      return ProjectResponse.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// POST /projects/{id}/create-template — turn project into a template.
  Future<void> createTemplate(int id) async {
    try {
      await _dio.post<dynamic>(Endpoints.projectCreateTemplate(id));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// POST /projects/import/file — import from an exported project file.
  Future<ProjectResponse> importFile({
    required String filePath,
    required String filename,
    void Function(double? progress)? onProgress,
  }) async {
    try {
      final form = FormData.fromMap(<String, dynamic>{
        'file': await MultipartFile.fromFile(filePath, filename: filename),
      });
      final res = await _dio.post<Map<String, dynamic>>(
        Endpoints.projectsImportFile,
        data: form,
        options:
            Options(sendTimeout: Duration.zero, receiveTimeout: Duration.zero),
        onSendProgress: onProgress == null
            ? null
            : (sent, total) => onProgress(total > 0 ? sent / total : null),
      );
      return ProjectResponse.fromJson(res.data ?? const {});
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// GET /projects/{id}/export?format=zip — export bytes for saving to disk.
  Future<Uint8List> export(int id, {String format = 'zip'}) async {
    try {
      final res = await _dio.get<List<int>>(
        Endpoints.projectExport(id),
        queryParameters: {'format': format},
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(res.data ?? const []);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  // --- Archives ---

  /// GET /projects/{id}/archives — preview list (reuses [ArchivePreview]).
  Future<List<ArchivePreview>> archives(int id, {int limit = 50, int offset = 0}) async {
    final List<dynamic> body;
    try {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.projectArchives(id),
        queryParameters: {'limit': limit, 'offset': offset},
      );
      body = res.data ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
    return _parseList(body, ArchivePreview.fromJson);
  }

  /// POST /projects/{id}/add-archives — link archives.
  Future<void> addArchives(int id, List<int> archiveIds) async {
    try {
      await _dio.post<dynamic>(
        Endpoints.projectAddArchives(id),
        data: <String, dynamic>{'archive_ids': archiveIds},
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// POST /projects/{id}/remove-archives — unlink archives.
  Future<void> removeArchives(int id, List<int> archiveIds) async {
    try {
      await _dio.post<dynamic>(
        Endpoints.projectRemoveArchives(id),
        data: <String, dynamic>{'archive_ids': archiveIds},
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  // --- Queue ---

  /// GET /projects/{id}/queue — queue items linked to the project.
  Future<List<QueueItem>> queue(int id) async {
    final List<dynamic> body;
    try {
      final res = await _dio.get<List<dynamic>>(Endpoints.projectQueue(id));
      body = res.data ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
    return _parseList(body, QueueItem.fromJson);
  }

  /// POST /projects/{id}/add-queue — link queue items.
  Future<void> addQueue(int id, List<int> queueItemIds) async {
    try {
      await _dio.post<dynamic>(
        Endpoints.projectAddQueue(id),
        data: <String, dynamic>{'queue_item_ids': queueItemIds},
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  // --- BOM ---

  /// GET /projects/{id}/bom — bill-of-materials items.
  Future<List<BomItem>> bom(int id) async {
    final List<dynamic> body;
    try {
      final res = await _dio.get<List<dynamic>>(Endpoints.projectBom(id));
      body = res.data ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
    return _parseList(body, BomItem.fromJson);
  }

  /// POST /projects/{id}/bom — add a BOM item.
  Future<void> addBomItem(int id, BomItemInput body) async {
    try {
      await _dio.post<dynamic>(Endpoints.projectBom(id), data: body.toMap());
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// PATCH /projects/{id}/bom/{itemId} — edit a BOM item.
  Future<void> updateBomItem(int id, int itemId, BomItemInput body) async {
    try {
      await _dio.patch<dynamic>(
        Endpoints.projectBomItem(id, itemId),
        data: body.toMap(),
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// DELETE /projects/{id}/bom/{itemId}.
  Future<void> deleteBomItem(int id, int itemId) async {
    try {
      await _dio.delete<dynamic>(Endpoints.projectBomItem(id, itemId));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  // --- Attachments ---

  /// POST /projects/{id}/attachments — upload a file attachment.
  Future<void> uploadAttachment(
    int id, {
    required String filePath,
    required String filename,
    void Function(double? progress)? onProgress,
  }) async {
    try {
      final form = FormData.fromMap(<String, dynamic>{
        'file': await MultipartFile.fromFile(filePath, filename: filename),
      });
      await _dio.post<dynamic>(
        Endpoints.projectAttachments(id),
        data: form,
        options:
            Options(sendTimeout: Duration.zero, receiveTimeout: Duration.zero),
        onSendProgress: onProgress == null
            ? null
            : (sent, total) => onProgress(total > 0 ? sent / total : null),
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// GET /projects/{id}/attachments/{filename} — download bytes.
  Future<Uint8List> downloadAttachment(int id, String filename) async {
    try {
      final res = await _dio.get<List<int>>(
        Endpoints.projectAttachment(id, filename),
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(res.data ?? const []);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// DELETE /projects/{id}/attachments/{filename}.
  Future<void> deleteAttachment(int id, String filename) async {
    try {
      await _dio.delete<dynamic>(Endpoints.projectAttachment(id, filename));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  // --- Cover image ---

  /// POST /projects/{id}/cover-image — upload cover image.
  Future<void> uploadCoverImage(
    int id, {
    required String filePath,
    required String filename,
  }) async {
    try {
      final form = FormData.fromMap(<String, dynamic>{
        'file': await MultipartFile.fromFile(filePath, filename: filename),
      });
      await _dio.post<dynamic>(
        Endpoints.projectCoverImage(id),
        data: form,
        options:
            Options(sendTimeout: Duration.zero, receiveTimeout: Duration.zero),
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// DELETE /projects/{id}/cover-image.
  Future<void> deleteCoverImage(int id) async {
    try {
      await _dio.delete<dynamic>(Endpoints.projectCoverImage(id));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  // --- Linked folders + printable files ---

  /// GET /library/folders/by-project/{id} — folders linked to the project.
  Future<List<LibraryFolder>> linkedFolders(int id) async {
    final List<dynamic> body;
    try {
      final res =
          await _dio.get<List<dynamic>>(Endpoints.libraryFoldersByProject(id));
      body = res.data ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
    return _parseList(body, LibraryFolder.fromJson);
  }

  /// PUT /library/folders/{folderId} — link a folder to a project
  /// ([projectId]) or unlink it (`null`). Sends only `project_id` so other
  /// folder fields are untouched.
  ///
  /// Server quirk: a JSON `null` is treated as "no change" (live-verified), so
  /// unlinking sends `0`, which the backend interprets as "clear the link".
  Future<void> setFolderProject(int folderId, int? projectId) async {
    try {
      await _dio.put<dynamic>(
        Endpoints.libraryFolder(folderId),
        data: <String, dynamic>{'project_id': projectId ?? 0},
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// GET /library/files?project_id={id} — library files in folders linked to
  /// the project. Used for the in-project print workflow.
  Future<List<LibraryFile>> files(int id) async {
    final List<dynamic> body;
    try {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.libraryFiles,
        queryParameters: {'project_id': id, 'include_root': false},
      );
      body = res.data ?? const [];
    } on DioException catch (e) {
      throw mapDioException(e);
    }
    return _parseList(body, LibraryFile.fromJson);
  }

  // --- Timeline ---

  /// GET /projects/{id}/timeline — chronological events. Auth errors bubble up
  /// (UI → /setup); other failures (the server currently 500s for some
  /// projects) degrade to an empty list so the section shows "no activity".
  Future<List<TimelineEvent>> timeline(int id, {int? limit}) async {
    final List<dynamic> body;
    try {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.projectTimeline(id),
        queryParameters: limit == null ? null : {'limit': limit},
      );
      body = res.data ?? const [];
    } on DioException catch (e) {
      final mapped = mapDioException(e);
      if (mapped is AuthException) throw mapped;
      return const [];
    }
    return _parseList(body, TimelineEvent.fromJson);
  }

  /// Defensive list parse: skips entries that fail to parse.
  List<T> _parseList<T>(
    List<dynamic> body,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final out = <T>[];
    for (final item in body) {
      if (item is! Map<String, dynamic>) continue;
      try {
        out.add(fromJson(item));
      } on Object {
        continue;
      }
    }
    return out;
  }
}
