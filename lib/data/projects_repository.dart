import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/api/api_exceptions.dart';
import '../core/api/endpoints.dart';
import '../core/models/json_utils.dart';
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
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.projects,
        queryParameters: query.isEmpty ? null : query,
      );
      return res.data ?? const [];
    });
    return parseJsonList(body, ProjectListResponse.fromJson);
  }

  /// GET /projects/templates — projects flagged as templates.
  Future<List<ProjectListResponse>> listTemplates() async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(Endpoints.projectsTemplates);
      return res.data ?? const [];
    });
    return parseJsonList(body, ProjectListResponse.fromJson);
  }

  /// GET /projects/{id} — full detail.
  Future<ProjectResponse> get(int id) => guard(() async {
        final res = await _dio.get<Map<String, dynamic>>(Endpoints.project(id));
        return ProjectResponse.fromJson(res.data ?? const {});
      });

  /// GET /projects/{id}/file-progress — finished runs per library file.
  ///
  /// Returns `null` when the route doesn't exist (404 — it arrived in bambuddy
  /// 1.2.5.2), the same feature gate [LibraryRepository.listTags] uses: the
  /// sets progress bar stays hidden rather than reading zero on a server that
  /// simply cannot answer. Other failures propagate as real errors.
  Future<List<ProjectFileProgress>?> fileProgress(int id) async {
    try {
      final body = await guard(() async {
        final res =
            await _dio.get<List<dynamic>>(Endpoints.projectFileProgress(id));
        return res.data ?? const [];
      });
      return parseJsonList(body, ProjectFileProgress.fromJson);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// POST /projects/ — create.
  Future<ProjectResponse> create(ProjectCreate body) => guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.projects,
          data: body.toMap(),
        );
        return ProjectResponse.fromJson(res.data ?? const {});
      });

  /// PATCH /projects/{id} — partial update.
  Future<ProjectResponse> update(int id, ProjectUpdate body) => guard(() async {
        final res = await _dio.patch<Map<String, dynamic>>(
          Endpoints.project(id),
          data: body.toMap(),
        );
        return ProjectResponse.fromJson(res.data ?? const {});
      });

  /// DELETE /projects/{id}.
  Future<void> delete(int id) => guard(() => _dio.delete<dynamic>(Endpoints.project(id)));

  // --- Templates / import / export ---

  /// POST /projects/from-template/{id}?name= — instantiate a template.
  Future<ProjectResponse> createFromTemplate(int templateId, String name) => guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.projectFromTemplate(templateId),
          queryParameters: {'name': name},
        );
        return ProjectResponse.fromJson(res.data ?? const {});
      });

  /// POST /projects/{id}/create-template — turn project into a template.
  Future<void> createTemplate(int id) =>
      guard(() => _dio.post<dynamic>(Endpoints.projectCreateTemplate(id)));

  /// POST /projects/import/file — import from an exported project file.
  Future<ProjectResponse> importFile({
    required String filePath,
    required String filename,
    void Function(double? progress)? onProgress,
  }) =>
      guard(() async {
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
      });

  /// GET /projects/{id}/export?format=zip — export bytes for saving to disk.
  Future<Uint8List> export(int id, {String format = 'zip'}) => guard(() async {
        final res = await _dio.get<List<int>>(
          Endpoints.projectExport(id),
          queryParameters: {'format': format},
          options: Options(responseType: ResponseType.bytes),
        );
        return Uint8List.fromList(res.data ?? const []);
      });

  // --- Archives ---

  /// GET /projects/{id}/archives — preview list (reuses [ArchivePreview]).
  Future<List<ArchivePreview>> archives(int id, {int limit = 50, int offset = 0}) async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.projectArchives(id),
        queryParameters: {'limit': limit, 'offset': offset},
      );
      return res.data ?? const [];
    });
    return parseJsonList(body, ArchivePreview.fromJson);
  }

  /// POST /projects/{id}/add-archives — link archives.
  Future<void> addArchives(int id, List<int> archiveIds) => guard(() => _dio.post<dynamic>(
        Endpoints.projectAddArchives(id),
        data: <String, dynamic>{'archive_ids': archiveIds},
      ));

  /// POST /projects/{id}/remove-archives — unlink archives.
  Future<void> removeArchives(int id, List<int> archiveIds) => guard(() => _dio.post<dynamic>(
        Endpoints.projectRemoveArchives(id),
        data: <String, dynamic>{'archive_ids': archiveIds},
      ));

  // --- Queue ---

  /// GET /projects/{id}/queue — queue items linked to the project.
  Future<List<QueueItem>> queue(int id) async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(Endpoints.projectQueue(id));
      return res.data ?? const [];
    });
    return parseJsonList(body, QueueItem.fromJson);
  }

  /// POST /projects/{id}/add-queue — link queue items.
  Future<void> addQueue(int id, List<int> queueItemIds) => guard(() => _dio.post<dynamic>(
        Endpoints.projectAddQueue(id),
        data: <String, dynamic>{'queue_item_ids': queueItemIds},
      ));

  // --- BOM ---

  /// GET /projects/{id}/bom — bill-of-materials items.
  Future<List<BomItem>> bom(int id) async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(Endpoints.projectBom(id));
      return res.data ?? const [];
    });
    return parseJsonList(body, BomItem.fromJson);
  }

  /// POST /projects/{id}/bom — add a BOM item.
  Future<void> addBomItem(int id, BomItemInput body) =>
      guard(() => _dio.post<dynamic>(Endpoints.projectBom(id), data: body.toMap()));

  /// PATCH /projects/{id}/bom/{itemId} — edit a BOM item.
  Future<void> updateBomItem(int id, int itemId, BomItemInput body) => guard(() => _dio.patch<dynamic>(
        Endpoints.projectBomItem(id, itemId),
        data: body.toMap(),
      ));

  /// DELETE /projects/{id}/bom/{itemId}.
  Future<void> deleteBomItem(int id, int itemId) =>
      guard(() => _dio.delete<dynamic>(Endpoints.projectBomItem(id, itemId)));

  // --- Attachments ---

  /// POST /projects/{id}/attachments — upload a file attachment.
  Future<void> uploadAttachment(
    int id, {
    required String filePath,
    required String filename,
    void Function(double? progress)? onProgress,
  }) =>
      guard(() async {
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
      });

  /// GET /projects/{id}/attachments/{filename} — download bytes.
  Future<Uint8List> downloadAttachment(int id, String filename) => guard(() async {
        final res = await _dio.get<List<int>>(
          Endpoints.projectAttachment(id, filename),
          options: Options(responseType: ResponseType.bytes),
        );
        return Uint8List.fromList(res.data ?? const []);
      });

  /// DELETE /projects/{id}/attachments/{filename}.
  Future<void> deleteAttachment(int id, String filename) =>
      guard(() => _dio.delete<dynamic>(Endpoints.projectAttachment(id, filename)));

  // --- Cover image ---

  /// POST /projects/{id}/cover-image — upload cover image.
  Future<void> uploadCoverImage(
    int id, {
    required String filePath,
    required String filename,
  }) =>
      guard(() async {
        final form = FormData.fromMap(<String, dynamic>{
          'file': await MultipartFile.fromFile(filePath, filename: filename),
        });
        await _dio.post<dynamic>(
          Endpoints.projectCoverImage(id),
          data: form,
          options:
              Options(sendTimeout: Duration.zero, receiveTimeout: Duration.zero),
        );
      });

  /// DELETE /projects/{id}/cover-image.
  Future<void> deleteCoverImage(int id) =>
      guard(() => _dio.delete<dynamic>(Endpoints.projectCoverImage(id)));

  // --- Linked folders + printable files ---

  /// GET /library/folders/by-project/{id} — folders linked to the project.
  Future<List<LibraryFolder>> linkedFolders(int id) async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(Endpoints.libraryFoldersByProject(id));
      return res.data ?? const [];
    });
    return parseJsonList(body, LibraryFolder.fromJson);
  }

  /// PUT /library/folders/{folderId} — link a folder to a project
  /// ([projectId]) or unlink it (`null`). Sends only `project_id` so other
  /// folder fields are untouched.
  ///
  /// Server quirk: a JSON `null` is treated as "no change" (live-verified), so
  /// unlinking sends `0`, which the backend interprets as "clear the link".
  Future<void> setFolderProject(int folderId, int? projectId) => guard(() => _dio.put<dynamic>(
        Endpoints.libraryFolder(folderId),
        data: <String, dynamic>{'project_id': projectId ?? 0},
      ));

  /// GET /library/files?project_id={id} — library files in folders linked to
  /// the project. Used for the in-project print workflow.
  Future<List<LibraryFile>> files(int id) async {
    final body = await guard(() async {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.libraryFiles,
        queryParameters: {'project_id': id, 'include_root': false},
      );
      return res.data ?? const [];
    });
    return parseJsonList(body, LibraryFile.fromJson);
  }

  // --- Timeline ---

  /// GET /projects/{id}/timeline — chronological events. Auth errors bubble up
  /// (UI → /setup); other failures (the server currently 500s for some
  /// projects) degrade to an empty list so the section shows "no activity".
  Future<List<TimelineEvent>> timeline(int id, {int? limit}) async {
    final body = await guardOrNull(() async {
      final res = await _dio.get<List<dynamic>>(
        Endpoints.projectTimeline(id),
        queryParameters: limit == null ? null : {'limit': limit},
      );
      return res.data ?? const [];
    });
    if (body == null) return const [];
    return parseJsonList(body, TimelineEvent.fromJson);
  }
}
