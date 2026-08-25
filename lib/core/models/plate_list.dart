import 'embedded_settings.dart';
import 'json_utils.dart';

/// One plate of a 3MF, from `GET /archives/{id}/plates` or
/// `GET /library/files/{id}/plates` — the two answer the same shape, so one
/// model reads both (the library route omits [bedType]).
class PlateInfo {
  const PlateInfo({
    required this.index,
    this.name,
    this.objects = const [],
    this.objectCount = 0,
    this.thumbnailPath,
    this.printTimeSeconds,
    this.filamentUsedGrams,
    this.bedType,
  });

  /// Null when the row carries no usable plate number: `index` is what the
  /// print, the G-code preview and the filament requirements are all keyed on,
  /// so a row without it cannot be offered as a choice.
  static PlateInfo? tryParse(dynamic value) {
    if (value is! Map) return null;
    final index = toIntOrNull(value['index']);
    if (index == null || index < 1) return null;
    return PlateInfo(
      index: index,
      name: toStringOrNull(value['name']),
      objects: toStringList(value['objects']),
      objectCount: toInt(value['object_count']),
      // Server-built and route-specific (`/archives/…` vs `/library/files/…`),
      // so it is taken as given rather than rebuilt from the index — and only
      // when the server said there is an image, since it sets the key to null
      // otherwise and asking anyway costs a 404 per row.
      thumbnailPath: value['has_thumbnail'] == true
          ? _samePathOnly(value['thumbnail_url'])
          : null,
      printTimeSeconds: toIntOrNull(value['print_time_seconds']),
      filamentUsedGrams: toDoubleOrNull(value['filament_used_grams']),
      bedType: toStringOrNull(value['bed_type']),
    );
  }

  /// A path on **this** server, or null.
  ///
  /// The value is fetched with the camera token in the query, so where it points
  /// decides who gets to see that token. The server has no business naming
  /// another host here — it builds these as `/api/v1/…` — and an absolute URL
  /// or a protocol-relative `//host/…` would send the token off to whoever it
  /// named. Rejected rather than sanitized: a plate with no render is a row with
  /// a placeholder icon, which costs nothing.
  static String? _samePathOnly(dynamic value) {
    final path = toStringOrNull(value);
    if (path == null || !path.startsWith('/') || path.startsWith('//')) {
      return null;
    }
    return path;
  }

  /// 1-indexed plate number, as it appears in `Metadata/plate_N.gcode` and as
  /// `plate_id` takes it.
  final int index;

  /// Plate name from the 3MF, or the first object's name when the designer left
  /// the plate unnamed. Null when neither is in the file.
  final String? name;

  final List<String> objects;

  /// Objects on the plate as the server counted them — kept separate from
  /// `objects.length`, which is empty for a file whose object names could not
  /// be read.
  final int objectCount;

  /// Path of this plate's render, ready to hang a `?token=` on. Null when the
  /// 3MF has none.
  final String? thumbnailPath;

  final int? printTimeSeconds;
  final double? filamentUsedGrams;

  /// Build plate the designer sliced for (e.g. "Textured PEI Plate"). Archive
  /// route only.
  final String? bedType;
}

/// Everything `GET …/plates` answers: the plates of one 3MF, the two flags the
/// picker gates on, and what the file was prepared with.
///
/// One model for the whole payload on purpose. It used to be read twice — the
/// plate rows here, [EmbeddedSettings] through a second request from the slicer
/// repository — which is two round trips for one zip parse and two places to
/// keep in step with the same route.
///
/// [PlateList.none] is what every failure degrades to — a missing route (a
/// server older than the endpoint), a file that is not a 3MF, an unreadable
/// zip, an account without read permission. All of them mean the same thing to
/// the caller: there is no plate to choose and no design to slice as, so offer
/// neither.
class PlateList {
  const PlateList({
    this.plates = const [],
    this.hasGcode = false,
    this.embedded = EmbeddedSettings.none,
  });

  factory PlateList.fromJson(Map<String, dynamic> json) => PlateList(
        plates: parsePlates(json['plates']),
        // Absent on the library route and on a source-only 3MF. Read as "there
        // is G-code to preview", never as "this file exists".
        hasGcode: json['has_gcode'] == true,
        embedded: EmbeddedSettings.fromJson(json),
      );

  static const none = PlateList();

  /// Plate rows, lowest index first — the order the server builds them in, kept
  /// explicit so a reordered response cannot shuffle the picker.
  final List<PlateInfo> plates;

  final bool hasGcode;

  /// The presets the 3MF names in its own `project_settings.config`, and whether
  /// this server can slice from them — the "slice as designed" gate.
  final EmbeddedSettings embedded;

  /// Whether there is a plate to pick. `is_multi_plate` from the server says
  /// the same thing, but it is derived from the very list below it, so the list
  /// is the single source here.
  bool get isMultiPlate => plates.length > 1;

  /// The row for [index], or null when the file has no such plate.
  PlateInfo? byIndex(int? index) {
    if (index == null) return null;
    for (final plate in plates) {
      if (plate.index == index) return plate;
    }
    return null;
  }

  /// Tolerant list parse: a row without a usable `index` is dropped rather than
  /// emptying the picker, and the result is sorted so the plate numbers read in
  /// order whatever the server sent.
  static List<PlateInfo> parsePlates(dynamic value) {
    if (value is! List) return const [];
    final out = <PlateInfo>[];
    for (final row in value) {
      final plate = PlateInfo.tryParse(row);
      if (plate != null) out.add(plate);
    }
    out.sort((a, b) => a.index.compareTo(b.index));
    return out;
  }
}
