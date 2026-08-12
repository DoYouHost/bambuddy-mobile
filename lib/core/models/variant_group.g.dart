// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'variant_group.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PrintVariant _$PrintVariantFromJson(Map<String, dynamic> json) => PrintVariant(
  libraryFileId: (json['library_file_id'] as num).toInt(),
  filename: json['filename'] as String,
  targetModel: json['target_model'] as String,
  position: (json['position'] as num).toInt(),
);

VariantGroup _$VariantGroupFromJson(Map<String, dynamic> json) => VariantGroup(
  id: (json['id'] as num).toInt(),
  name: json['name'] as String,
  members: json['members'] == null
      ? const []
      : _membersFromJson(json['members']),
);
