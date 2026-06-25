/// Modele integracji MakerWorld (`/api/v1/makerworld/*`).
///
/// `design` i `instances` przychodzą z MakerWorld przepuszczone „as-is" —
/// serwer ich nie przekształca. Czytamy je więc defensywnie po kilku
/// kandydujących kluczach i tolerujemy braki; UI degraduje do nazwy/placeholdera.
library;

/// Stan integracji z `GET /makerworld/status`.
class MakerWorldStatus {
  const MakerWorldStatus({
    required this.hasCloudToken,
    required this.canDownload,
  });

  factory MakerWorldStatus.fromJson(Map<String, dynamic> json) =>
      MakerWorldStatus(
        hasCloudToken: json['has_cloud_token'] == true,
        canDownload: json['can_download'] == true,
      );

  /// Czy konto ma zapisany token chmury Bambu.
  final bool hasCloudToken;

  /// Skrót: token istnieje i wygląda na ważny. Pobieranie tego wymaga.
  final bool canDownload;
}

/// Pojedyncza okładka/obiekt z opaque mapy — wyciąga tytuł i URL okładki.
String? _pickString(Map<String, dynamic> json, List<String> keys) {
  for (final k in keys) {
    final v = json[k];
    if (v is String && v.trim().isNotEmpty) return v;
  }
  return null;
}

int? _pickInt(Map<String, dynamic> json, List<String> keys) {
  for (final k in keys) {
    final v = json[k];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final n = int.tryParse(v);
      if (n != null) return n;
    }
  }
  return null;
}

/// Nagłówek modelu (tytuł + okładka). Pola MakerWorld bywają pod różnymi
/// nazwami — bierzemy pierwszą pasującą.
class MakerWorldDesign {
  const MakerWorldDesign({this.title, this.coverUrl});

  factory MakerWorldDesign.fromJson(Map<String, dynamic> json) =>
      MakerWorldDesign(
        title: _pickString(json, ['title', 'name', 'designTitle']),
        coverUrl: _pickString(
          json,
          ['cover', 'coverUrl', 'cover_url', 'coverImage', 'cover_image'],
        ),
      );

  final String? title;
  final String? coverUrl;
}

/// Instancja (płyta/profil) modelu. `profileId` jest tym, co dosyłamy jako
/// `profile_id` przy imporcie.
class MakerWorldInstance {
  const MakerWorldInstance({
    this.profileId,
    required this.name,
    this.coverUrl,
  });

  factory MakerWorldInstance.fromJson(Map<String, dynamic> json) {
    final profileId =
        _pickInt(json, ['profileId', 'profile_id', 'id']);
    final name = _pickString(json, ['name', 'title', 'profileName']) ??
        (profileId != null ? 'Plate $profileId' : 'Plate');
    return MakerWorldInstance(
      profileId: profileId,
      name: name,
      coverUrl: _pickString(
        json,
        ['cover', 'coverUrl', 'cover_url', 'coverImage', 'cover_image'],
      ),
    );
  }

  final int? profileId;
  final String name;
  final String? coverUrl;
}

/// Wynik `POST /makerworld/resolve`.
class MakerWorldResolvedModel {
  const MakerWorldResolvedModel({
    required this.modelId,
    this.profileId,
    required this.design,
    required this.instances,
    this.alreadyImportedLibraryIds = const {},
  });

  factory MakerWorldResolvedModel.fromJson(Map<String, dynamic> json) {
    final rawDesign = json['design'];
    final design = rawDesign is Map<String, dynamic>
        ? MakerWorldDesign.fromJson(rawDesign)
        : const MakerWorldDesign();

    final instances = <MakerWorldInstance>[];
    final rawInstances = json['instances'];
    if (rawInstances is List) {
      for (final item in rawInstances) {
        if (item is! Map<String, dynamic>) continue;
        try {
          instances.add(MakerWorldInstance.fromJson(item));
        } on Object {
          continue;
        }
      }
    }

    final imported = <int>{};
    final rawImported = json['already_imported_library_ids'];
    if (rawImported is List) {
      for (final v in rawImported) {
        if (v is int) imported.add(v);
        if (v is num) imported.add(v.toInt());
      }
    }

    return MakerWorldResolvedModel(
      modelId: _pickInt(json, ['model_id', 'modelId']) ?? 0,
      profileId: _pickInt(json, ['profile_id', 'profileId']),
      design: design,
      instances: instances,
      alreadyImportedLibraryIds: imported,
    );
  }

  final int modelId;

  /// Profil z fragmentu URL-a (`#profileId-`), jeśli był.
  final int? profileId;
  final MakerWorldDesign design;
  final List<MakerWorldInstance> instances;

  /// `LibraryFile` ID-ki wcześniej zaimportowane z tego URL-a.
  final Set<int> alreadyImportedLibraryIds;
}

/// Wynik `POST /makerworld/import`.
class MakerWorldImportResponse {
  const MakerWorldImportResponse({
    required this.libraryFileId,
    required this.filename,
    this.folderId,
    this.profileId,
    this.wasExisting = false,
  });

  factory MakerWorldImportResponse.fromJson(Map<String, dynamic> json) =>
      MakerWorldImportResponse(
        libraryFileId: _pickInt(json, ['library_file_id', 'libraryFileId']) ?? 0,
        filename: _pickString(json, ['filename', 'name']) ?? '',
        folderId: _pickInt(json, ['folder_id', 'folderId']),
        profileId: _pickInt(json, ['profile_id', 'profileId']),
        wasExisting: json['was_existing'] == true,
      );

  final int libraryFileId;
  final String filename;
  final int? folderId;
  final int? profileId;

  /// Plik z tego samego URL-a był już — nie pobrano ponownie.
  final bool wasExisting;
}

/// Wiersz listy „ostatnie importy z MakerWorld".
class MakerWorldRecentImport {
  const MakerWorldRecentImport({
    required this.libraryFileId,
    required this.filename,
    this.folderId,
    this.thumbnailPath,
    this.sourceUrl,
    this.createdAt,
  });

  factory MakerWorldRecentImport.fromJson(Map<String, dynamic> json) =>
      MakerWorldRecentImport(
        libraryFileId: _pickInt(json, ['library_file_id', 'libraryFileId']) ?? 0,
        filename: _pickString(json, ['filename', 'name']) ?? '',
        folderId: _pickInt(json, ['folder_id', 'folderId']),
        thumbnailPath: _pickString(json, ['thumbnail_path', 'thumbnailPath']),
        sourceUrl: _pickString(json, ['source_url', 'sourceUrl']),
        createdAt: _pickString(json, ['created_at', 'createdAt']),
      );

  final int libraryFileId;
  final String filename;
  final int? folderId;
  final String? thumbnailPath;
  final String? sourceUrl;
  final String? createdAt;

  /// Czy serwer ma dla pliku miniaturę (do `LibraryThumbnail`).
  bool get hasThumbnail => thumbnailPath != null && thumbnailPath!.isNotEmpty;
}
