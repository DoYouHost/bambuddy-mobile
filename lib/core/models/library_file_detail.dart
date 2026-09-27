import 'package:json_annotation/json_annotation.dart';

part 'library_file_detail.g.dart';

/// What `GET /library/files/{id}` (`FileResponse`) adds over the listing row
/// for the details screen (#3077). Every field is optional: a server before it
/// sends `notes` only, and the screen is not offered there anyway.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class LibraryFileDetail {
  const LibraryFileDetail({
    this.notes,
    this.externalUrl,
    this.sourceUrl,
    this.photos = const [],
  });

  factory LibraryFileDetail.fromJson(Map<String, dynamic> json) =>
      _$LibraryFileDetailFromJson(json);

  final String? notes;

  /// The user's own link; `""` never arrives — the server stores it as null.
  final String? externalUrl;

  /// Where the file was imported from (MakerWorld). Read-only: `FileUpdate`
  /// has no field for it.
  final String? sourceUrl;

  /// Photo filenames, uuid-named by the server, in upload order.
  @JsonKey(defaultValue: <String>[])
  final List<String> photos;
}
