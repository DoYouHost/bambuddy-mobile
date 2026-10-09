import 'package:app_util/app_util.dart';

/// One printer location (`PrinterLocationResponse`, server #2962).
///
/// A printer's location is still the free-text `Printer.location`; this adds
/// what that string cannot hold — an icon, a colour, and a location with no
/// printers in it yet.
class PrinterLocation {
  const PrinterLocation({
    required this.name,
    this.id,
    this.icon,
    this.color,
    this.printerCount = 0,
  });

  factory PrinterLocation.fromJson(Map<String, dynamic> json) =>
      PrinterLocation(
        id: toIntOrNull(json['id']),
        name: toStringOrNull(json['name']) ?? '',
        icon: toStringOrNull(json['icon']),
        color: toStringOrNull(json['color']),
        printerCount: toInt(json['printer_count']),
      );

  /// `null` for a location only printers carry: the server lists those too, so
  /// a name typed into the printer form shows up here, but it has no row — and
  /// so no icon or colour — until it is first styled.
  final int? id;

  /// What a printer's `location` is matched against, exactly. Never use [id]
  /// to address one: every write takes the name.
  final String name;

  /// One of [printerLocationIcons]; anything else (an icon a newer web adds)
  /// shows the default.
  final String? icon;

  /// `#rrggbb`, or `null` for none.
  final String? color;

  /// Counted over the printers the caller may see, not over all of them.
  final int printerCount;
}

/// What a create or an edit sends. [name] on an edit is the one the location
/// has now; [newName] is set only when it changes.
class PrinterLocationDraft {
  const PrinterLocationDraft({
    required this.name,
    this.newName,
    this.icon,
    this.color,
  });

  final String name;
  final String? newName;
  final String? icon;
  final String? color;

  /// `PATCH`: `icon` and `color` are changed only when sent, and `null` clears
  /// them — so both always go, and a field the user emptied is cleared.
  Map<String, dynamic> toUpdateJson() => {
    'name': name,
    if (newName != null && newName != name) 'new_name': newName,
    'icon': icon,
    'color': color,
  };

  Map<String, dynamic> toCreateJson() => {
    'name': name,
    'icon': icon,
    'color': color,
  };
}

/// The most a location name may hold (`schemas/printer_location.py`): the
/// column is `VARCHAR(100)`, and a longer value is refused with a 422.
const printerLocationNameMax = 100;

/// The colours the web page offers (`PrinterLocationsPage.tsx`,
/// `LOCATION_COLORS`); the server takes any `#rrggbb`.
const printerLocationColors = <String>[
  '#ef4444',
  '#f97316',
  '#eab308',
  '#22c55e',
  '#14b8a6',
  '#3b82f6',
  '#8b5cf6',
  '#ec4899',
  '#6b7280',
];
