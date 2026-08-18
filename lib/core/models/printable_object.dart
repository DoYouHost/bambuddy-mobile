import 'json_utils.dart';

/// One printable object on the current build plate. [id] is the printer's
/// `identify_id` (shown on the machine display), used as the value to skip.
/// [x]/[y] are plate coordinates in mm (null when the 3MF lacks positions).
/// [width]/[height] are the footprint in mm; the real server doesn't send
/// them today (`printers.py` builds the object entry from id/name/x/y only),
/// so they're demo-only for now and the plate preview falls back to a fixed
/// marker size whenever they're absent.
class PrintableObject {
  const PrintableObject({
    required this.id,
    required this.name,
    this.x,
    this.y,
    this.width,
    this.height,
    this.skipped = false,
  });

  final int id;
  final String name;
  final double? x;
  final double? y;
  final double? width;
  final double? height;
  final bool skipped;

  factory PrintableObject.fromJson(Map<String, dynamic> json) {
    final id = toInt(json['id']);
    return PrintableObject(
      id: id,
      name: toStringOrNull(json['name']) ?? 'Object $id',
      x: toDoubleOrNull(json['x']),
      y: toDoubleOrNull(json['y']),
      width: toDoubleOrNull(json['width']),
      height: toDoubleOrNull(json['height']),
      skipped: json['skipped'] == true,
    );
  }
}

/// Printable-objects snapshot for the current print. [bboxAll] is the
/// `[xMin, yMin, xMax, yMax]` (mm) bounding box of all objects — it defines the
/// area shown in the top-down cover render, so object [x]/[y] map onto that image.
class PrintableObjects {
  const PrintableObjects({
    this.objects = const [],
    this.total = 0,
    this.skippedCount = 0,
    this.isPrinting = false,
    this.bboxAll,
  });

  final List<PrintableObject> objects;
  final int total;
  final int skippedCount;
  final bool isPrinting;
  final List<double>? bboxAll;

  /// Objects still being printed (not yet skipped).
  int get activeCount => objects.where((o) => !o.skipped).length;

  factory PrintableObjects.fromJson(Map<String, dynamic> json) {
    final bbox = json['bbox_all'];
    return PrintableObjects(
      objects: parseJsonList(json['objects'], PrintableObject.fromJson),
      total: toInt(json['total']),
      skippedCount: toInt(json['skipped_count']),
      isPrinting: json['is_printing'] == true,
      bboxAll: bbox is List && bbox.length == 4
          ? bbox.map(toDouble).toList(growable: false)
          : null,
    );
  }
}
