import 'package:app_util/app_util.dart';

/// Shapes of the Manyfold routes (`backend/app/schemas/manyfold.py`, #1471).
/// Manyfold ids are short public strings ("x7q3k2pa"), never numbers.

/// `GET /manyfold/status`.
class ManyfoldStatus {
  const ManyfoldStatus({required this.configured, this.url = ''});

  factory ManyfoldStatus.fromJson(Map<String, dynamic> json) => ManyfoldStatus(
    configured: json['configured'] == true,
    url: toStringOrNull(json['url']) ?? '',
  );

  final bool configured;

  /// The install's base URL, for "Open in Manyfold"; empty until configured.
  final String url;
}

class ManyfoldModelSummary {
  const ManyfoldModelSummary({required this.id, required this.name});

  factory ManyfoldModelSummary.fromJson(Map<String, dynamic> json) =>
      ManyfoldModelSummary(
        id: toStringOrNull(json['id']) ?? '',
        name: toStringOrNull(json['name']) ?? '',
      );

  final String id;
  final String name;
}

/// One page of `GET /manyfold/models`. The page size is the Manyfold
/// application owner's own setting, so only the neighbours are known.
class ManyfoldModelPage {
  const ManyfoldModelPage({
    required this.total,
    required this.page,
    required this.hasNext,
    required this.hasPrevious,
    required this.models,
  });

  factory ManyfoldModelPage.fromJson(Map<String, dynamic> json) =>
      ManyfoldModelPage(
        total: toInt(json['total']),
        page: toIntOrNull(json['page']) ?? 1,
        hasNext: json['has_next'] == true,
        hasPrevious: json['has_previous'] == true,
        models: parseJsonList(json['models'], ManyfoldModelSummary.fromJson),
      );

  final int total;
  final int page;
  final bool hasNext;
  final bool hasPrevious;
  final List<ManyfoldModelSummary> models;
}

/// The library file an earlier import of a Manyfold file created.
class ManyfoldLibraryRef {
  const ManyfoldLibraryRef({
    required this.id,
    required this.filename,
    this.folderId,
  });

  factory ManyfoldLibraryRef.fromJson(Map<String, dynamic> json) =>
      ManyfoldLibraryRef(
        id: toInt(json['id']),
        filename: toStringOrNull(json['filename']) ?? '',
        folderId: toIntOrNull(json['folder_id']),
      );

  final int id;
  final String filename;
  final int? folderId;
}

class ManyfoldFile {
  const ManyfoldFile({
    required this.id,
    required this.name,
    this.mime = '',
    this.importable = false,
    this.libraryFile,
  });

  factory ManyfoldFile.fromJson(Map<String, dynamic> json) => ManyfoldFile(
    id: toStringOrNull(json['id']) ?? '',
    name: toStringOrNull(json['name']) ?? '',
    mime: toStringOrNull(json['mime']) ?? '',
    importable: json['importable'] == true,
    libraryFile: json['library_file'] is Map<String, dynamic>
        ? ManyfoldLibraryRef.fromJson(json['library_file'])
        : null,
  );

  final String id;
  final String name;
  final String mime;

  /// 3MF, STL or STEP — what the server can slice or print.
  final bool importable;

  /// Set while the file imported earlier is still in the library.
  final ManyfoldLibraryRef? libraryFile;

  /// The web's `fileTypeLabel`: "model/x-step+zip" → "STEP".
  String get typeLabel {
    final slash = mime.indexOf('/');
    final subtype = slash < 0 ? '' : mime.substring(slash + 1);
    final base = subtype.replaceFirst(RegExp('^x-'), '').split(RegExp('[+.;]'));
    return base.first.isEmpty ? '?' : base.first.toUpperCase();
  }
}

/// `GET /manyfold/models/{id}`.
class ManyfoldModel {
  const ManyfoldModel({
    required this.id,
    required this.name,
    this.caption,
    this.description,
    this.license,
    this.tags = const [],
    this.url = '',
    this.hasPreview = false,
    this.files = const [],
  });

  factory ManyfoldModel.fromJson(Map<String, dynamic> json) => ManyfoldModel(
    id: toStringOrNull(json['id']) ?? '',
    name: toStringOrNull(json['name']) ?? '',
    caption: toStringOrNull(json['caption']),
    description: toStringOrNull(json['description']),
    license: toStringOrNull(json['license']),
    tags: toStringList(json['tags']),
    url: toStringOrNull(json['url']) ?? '',
    hasPreview: json['has_preview'] == true,
    files: parseJsonList(json['files'], ManyfoldFile.fromJson),
  );

  final String id;
  final String name;
  final String? caption;
  final String? description;
  final String? license;
  final List<String> tags;

  /// The model's page in Manyfold.
  final String url;
  final bool hasPreview;
  final List<ManyfoldFile> files;

  /// Files that can still be imported: printable and not in the library yet.
  List<ManyfoldFile> get importCandidates => [
    for (final f in files)
      if (f.importable && f.libraryFile == null) f,
  ];
}

/// `POST /manyfold/import`.
class ManyfoldImportResult {
  const ManyfoldImportResult({
    required this.libraryFileId,
    required this.filename,
    this.folderId,
    this.wasExisting = false,
  });

  factory ManyfoldImportResult.fromJson(Map<String, dynamic> json) =>
      ManyfoldImportResult(
        libraryFileId: toInt(json['library_file_id']),
        filename: toStringOrNull(json['filename']) ?? '',
        folderId: toIntOrNull(json['folder_id']),
        wasExisting: json['was_existing'] == true,
      );

  final int libraryFileId;
  final String filename;
  final int? folderId;

  /// The file was in the library already and was not downloaded again.
  final bool wasExisting;
}

/// `GET /manyfold/config`. The secret itself is never sent back.
class ManyfoldConfig {
  const ManyfoldConfig({
    this.url = '',
    this.clientId = '',
    this.hasClientSecret = false,
    this.configured = false,
  });

  factory ManyfoldConfig.fromJson(Map<String, dynamic> json) => ManyfoldConfig(
    url: toStringOrNull(json['url']) ?? '',
    clientId: toStringOrNull(json['client_id']) ?? '',
    hasClientSecret: json['has_client_secret'] == true,
    configured: json['configured'] == true,
  );

  final String url;
  final String clientId;
  final bool hasClientSecret;
  final bool configured;
}

/// A Manyfold failure the server named with a code (`{"detail": {"code",
/// "message"}}`); the app shows its own text for it, as the web does. Codes
/// are the keys of the web's `manyfold.errors`.
class ManyfoldFailure implements Exception {
  const ManyfoldFailure(this.code, {this.statusCode});

  final String code;
  final int? statusCode;

  @override
  String toString() => 'ManyfoldFailure($code, status=$statusCode)';
}
