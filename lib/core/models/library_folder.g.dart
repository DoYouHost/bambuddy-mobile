// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_folder.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LibraryFolder _$LibraryFolderFromJson(Map<String, dynamic> json) =>
    LibraryFolder(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      parentId: (json['parent_id'] as num?)?.toInt(),
      projectName: json['project_name'] as String?,
      archiveName: json['archive_name'] as String?,
      isExternal: json['is_external'] as bool? ?? false,
      externalPath: json['external_path'] as String?,
      externalReadonly: json['external_readonly'] as bool? ?? false,
      fileCount: (json['file_count'] as num?)?.toInt() ?? 0,
      children: json['children'] == null
          ? const []
          : _childrenFromJson(json['children']),
    );
