// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trash_file.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TrashFile _$TrashFileFromJson(Map<String, dynamic> json) => TrashFile(
  id: (json['id'] as num).toInt(),
  filename: json['filename'] as String,
  fileSize: (json['file_size'] as num).toInt(),
  thumbnailPath: json['thumbnail_path'] as String?,
  folderName: json['folder_name'] as String?,
  createdByUsername: json['created_by_username'] as String?,
  deletedAt: dateTimeFromJson(json['deleted_at']),
  autoPurgeAt: dateTimeFromJson(json['auto_purge_at']),
);
