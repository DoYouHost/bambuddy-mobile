import 'package:json_annotation/json_annotation.dart';

import 'json_utils.dart';

part 'library_tag.g.dart';

/// Library tag — a global, label-only chip on a library file (`TagResponse`
/// in the catalog listing, `TagSummary` when embedded in a file).
///
/// One class for both shapes on purpose: the embedded projection carries only
/// `id` + `name`, so [fileCount] falls back to 0 there and is only meaningful
/// for rows that came from the catalog endpoint.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class LibraryTag {
  const LibraryTag({required this.id, required this.name, this.fileCount = 0});

  factory LibraryTag.fromJson(Map<String, dynamic> json) =>
      _$LibraryTagFromJson(json);

  final int id;
  final String name;

  /// Files carrying this tag. Server-side this is already scoped to what the
  /// caller may see, so it matches what filtering by the tag returns.
  @JsonKey(defaultValue: 0)
  final int fileCount;
}

/// Bulk assignment mode of `POST /library/tags/bulk-assign`.
enum TagAssignAction {
  /// Append the tags to every file, leaving existing ones alone (idempotent).
  add('add'),

  /// Strip the tags from every file.
  remove('remove'),

  /// Make the given set the file's entire tag set — an empty set clears it.
  replace('replace');

  const TagAssignAction(this.wire);

  final String wire;
}

/// What `bulk-assign` actually did. [filesUpdated] counts the files the server
/// let through, which is **not** always the number asked for: a user without
/// library-update-all silently keeps their own files and loses the rest, and
/// that difference is the only signal the UI has to say "partially applied".
class TagAssignResult {
  const TagAssignResult({
    required this.filesUpdated,
    required this.added,
    required this.removed,
  });

  factory TagAssignResult.fromJson(Map<String, dynamic> json) =>
      TagAssignResult(
        filesUpdated: toInt(json['files_updated']),
        added: toInt(json['associations_added']),
        removed: toInt(json['associations_removed']),
      );

  final int filesUpdated;
  final int added;
  final int removed;
}
