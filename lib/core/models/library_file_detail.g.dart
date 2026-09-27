// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'library_file_detail.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LibraryFileDetail _$LibraryFileDetailFromJson(Map<String, dynamic> json) =>
    LibraryFileDetail(
      notes: json['notes'] as String?,
      externalUrl: json['external_url'] as String?,
      sourceUrl: json['source_url'] as String?,
      photos:
          (json['photos'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
