// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_file.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LibraryFile _$LibraryFileFromJson(Map<String, dynamic> json) => LibraryFile(
  id: (json['id'] as num).toInt(),
  filename: json['filename'] as String,
  fileType: json['file_type'] as String,
  fileSize: (json['file_size'] as num).toInt(),
  printCount: (json['print_count'] as num).toInt(),
  folderId: (json['folder_id'] as num?)?.toInt(),
  isExternal: json['is_external'] as bool? ?? false,
  thumbnailPath: json['thumbnail_path'] as String?,
  duplicateCount: (json['duplicate_count'] as num?)?.toInt() ?? 0,
  createdByUsername: json['created_by_username'] as String?,
  createdAt: dateTimeFromJson(json['created_at']),
  printName: json['print_name'] as String?,
  printTimeSeconds: (json['print_time_seconds'] as num?)?.toInt(),
  filamentUsedGrams: (json['filament_used_grams'] as num?)?.toDouble(),
  slicedForModel: json['sliced_for_model'] as String?,
  tags: json['tags'] == null ? const [] : _tagsFromJson(json['tags']),
);
