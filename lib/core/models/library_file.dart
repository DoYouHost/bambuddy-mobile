import 'package:json_annotation/json_annotation.dart';

part 'library_file.g.dart';

/// Plik w bibliotece menedżera plików (`FileListResponse`).
///
/// Parsowanie defensywne: poza id/filename/file_type/file_size/created_at
/// wszystko nullable, nieznane klucze ignorowane — kontrakt API bywa ruchliwy.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class LibraryFile {
  const LibraryFile({
    required this.id,
    required this.filename,
    required this.fileType,
    required this.fileSize,
    required this.printCount,
    this.folderId,
    this.isExternal = false,
    this.thumbnailPath,
    this.duplicateCount = 0,
    this.createdByUsername,
    this.createdAt,
    this.printName,
    this.printTimeSeconds,
    this.filamentUsedGrams,
    this.slicedForModel,
  });

  factory LibraryFile.fromJson(Map<String, dynamic> json) =>
      _$LibraryFileFromJson(json);

  final int id;
  final int? folderId;

  /// Plik z folderu zewnętrznego (read-only po stronie hosta) — pewne akcje
  /// (np. usunięcie/zmiana nazwy) mogą być niedostępne.
  @JsonKey(defaultValue: false)
  final bool isExternal;

  /// Nazwa pliku na dysku (np. „Mug Holder.3mf").
  final String filename;

  /// Rozszerzenie/typ pliku (np. „3mf", „gcode", „stl").
  final String fileType;

  /// Rozmiar pliku w bajtach.
  final int fileSize;

  /// Ścieżka miniatury (jeśli wygenerowana). Sam render idzie przez endpoint
  /// `thumbnail` z tokenem — to pole służy tylko do sprawdzenia „czy jest".
  final String? thumbnailPath;

  /// Ile razy plik był drukowany.
  final int printCount;

  /// Liczba duplikatów (ten sam hash w innych miejscach biblioteki).
  @JsonKey(defaultValue: 0)
  final int duplicateCount;

  /// Nazwa użytkownika, który wgrał plik.
  final String? createdByUsername;

  final DateTime? createdAt;

  /// Czytelna nazwa wydruku z metadanych slicera (jeśli inna niż [filename]).
  final String? printName;

  /// Szacowany czas wydruku w sekundach (z metadanych slicera).
  final int? printTimeSeconds;

  /// Szacowane zużycie filamentu w gramach (z metadanych slicera).
  final double? filamentUsedGrams;

  /// Model drukarki, dla którego plik był skrojony (np. „P1S", „X1C").
  final String? slicedForModel;

  /// Wyświetlana nazwa: czytelna nazwa wydruku, jeśli jest, inaczej nazwa pliku.
  String get displayName => printName ?? filename;

  /// Czy plik nadaje się do druku (skrojony g-code). Tylko takie przyjmuje
  /// endpoint druku — patrz `FilePrint` w API.
  bool get isPrintable {
    final t = fileType.toLowerCase();
    final name = filename.toLowerCase();
    return t == 'gcode' ||
        name.endsWith('.gcode') ||
        name.endsWith('.gcode.3mf');
  }
}
