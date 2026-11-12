import 'package:app_util/app_util.dart';

import 'spool_preset_override.dart';

/// The product a profile default is for (server #1326). An empty
/// [colorName] means every colour.
class ProfileProduct {
  const ProfileProduct({
    required this.material,
    this.brand = '',
    this.subtype = '',
    this.colorName = '',
  });

  factory ProfileProduct.fromJson(Map<String, dynamic> json) => ProfileProduct(
    brand: toStringOrNull(json['brand']) ?? '',
    material: toStringOrNull(json['material']) ?? '',
    subtype: toStringOrNull(json['subtype']) ?? '',
    colorName: toStringOrNull(json['color_name']) ?? '',
  );

  final String brand;
  final String material;
  final String subtype;
  final String colorName;

  /// The same product with every colour — the key the server resolves first.
  ProfileProduct get allColours =>
      ProfileProduct(brand: brand, material: material, subtype: subtype);

  /// `profile_defaults.match_key`: trimmed and case-folded, so `PLA` and
  /// `pla ` are one product. Comparing anything looser or stricter would pick
  /// another row than the one the server's save replaces.
  String get matchKey => [
    brand,
    material,
    subtype,
    colorName,
  ].map((part) => part.trim().toLowerCase()).join('\x1f');

  /// "Bambu Lab PLA Basic": the web's `productOf`, without the colour.
  String get label => [
    brand,
    material,
    subtype,
  ].map((part) => part.trim()).where((part) => part.isNotEmpty).join(' ');

  Map<String, dynamic> toJson() => {
    'brand': brand.trim(),
    'material': material.trim(),
    'subtype': subtype.trim(),
    'color_name': colorName.trim(),
  };
}

/// One stored default (`FilamentProfileDefaultResponse`).
///
/// [kProfiles] stay raw maps: the app has no editor for them, and the save is a
/// full replacement, so the only safe thing to send back is what the server
/// sent — including any field a newer server adds.
class ProfileDefault {
  const ProfileDefault({
    required this.id,
    required this.product,
    this.slicerFilament,
    this.slicerFilamentName,
    this.presets = const [],
    this.kProfiles = const [],
  });

  factory ProfileDefault.fromJson(Map<String, dynamic> json) => ProfileDefault(
    id: toInt(json['id']),
    product: ProfileProduct.fromJson(json),
    slicerFilament: toStringOrNull(json['slicer_filament']),
    slicerFilamentName: toStringOrNull(json['slicer_filament_name']),
    presets: parseJsonList(json['presets'], SpoolPresetOverride.fromJson),
    kProfiles: [
      if (json['k_profiles'] case final List rows)
        for (final k in rows)
          if (k is Map) asJsonRecord(k),
    ],
  );

  final int id;
  final ProfileProduct product;
  final String? slicerFilament;
  final String? slicerFilamentName;
  final List<SpoolPresetOverride> presets;
  final List<Map<String, dynamic>> kProfiles;
}

/// What a new spool of a product starts with (`ResolvedProfileDefault`): the
/// all-colours default with the colour's own laid over it. K profiles are not
/// read — the server applies them itself, and the form has no place to show
/// them.
class ResolvedProfileDefault {
  const ResolvedProfileDefault({
    this.slicerFilament,
    this.slicerFilamentName,
    this.presets = const [],
  });

  factory ResolvedProfileDefault.fromJson(Map<String, dynamic> json) =>
      ResolvedProfileDefault(
        slicerFilament: toStringOrNull(json['slicer_filament']),
        slicerFilamentName: toStringOrNull(json['slicer_filament_name']),
        presets: parseJsonList(json['presets'], SpoolPresetOverride.fromJson),
      );

  final String? slicerFilament;
  final String? slicerFilamentName;
  final List<SpoolPresetOverride> presets;
}

/// The body of `PUT /inventory/profile-defaults` (`FilamentProfileDefaultWrite`).
class ProfileDefaultDraft {
  const ProfileDefaultDraft({
    required this.product,
    this.slicerFilament,
    this.slicerFilamentName,
    this.presets = const [],
    this.kProfiles = const [],
  });

  final ProfileProduct product;
  final String? slicerFilament;
  final String? slicerFilamentName;
  final List<SpoolPresetOverride> presets;
  final List<Map<String, dynamic>> kProfiles;

  Map<String, dynamic> toJson() => {
    ...product.toJson(),
    'slicer_filament': slicerFilament,
    'slicer_filament_name': slicerFilament == null ? null : slicerFilamentName,
    'presets': [for (final p in presets) p.toJson()],
    'k_profiles': kProfiles,
  };
}
