/// Spool label printing (`POST /inventory/labels`, `POST /spoolman/labels`).
///
/// The server renders a PDF; the app hands those bytes to the platform print
/// dialog. Each label carries a QR code deep-linking back to the spool, so a
/// scan from the Filaments tab reopens that spool.
library;

import 'dart:math' as math;
import 'dart:ui' show Color;

/// Label stock the server can render onto. Wire values must match the
/// backend's `LabelRequest.template` literals exactly — anything else is a 400.
///
/// `mm` sizes are single labels (one per page, for roll/thermal printers);
/// the two Avery entries are full sheets of many labels.
enum SpoolLabelTemplate {
  amsHolderSmall('ams_holder_74x33'),
  amsHolderLarge('ams_holder_75x55'),
  box40x30('box_40x30'),
  box62x29('box_62x29'),
  averyL7160(
    'avery_l7160',
    sheet: (columns: 3, rows: 7, widthMm: 63.5, heightMm: 38.1),
  ),
  avery5160(
    'avery_5160',
    sheet: (columns: 3, rows: 10, widthMm: 66.675, heightMm: 25.4),
  );

  const SpoolLabelTemplate(this.wire, {this.sheet});

  /// Value sent as `template` in the request body.
  final String wire;

  /// How the labels are laid out on a sheet, or null for a roll template that
  /// prints one label per page.
  ///
  /// Mirrors `_SHEET_TEMPLATES` in the server's `label_renderer.py`, which is
  /// also what validates `starting_position` — a value past [sheetCapacity] is
  /// a 422, so the picker must not offer one. The millimetres are there so a
  /// picker can draw slots shaped like the stock in the printer's tray: the two
  /// sheets differ far more in label proportion than in slot count.
  final ({int columns, int rows, double widthMm, double heightMm})? sheet;

  /// Labels one sheet holds, or null for a roll template. Positions are
  /// numbered 1..capacity left to right, top row first.
  int? get sheetCapacity {
    final layout = sheet;
    return layout == null ? null : layout.columns * layout.rows;
  }
}

/// Server-side cap on one label request (`MAX_LABELS_PER_REQUEST`). Asking for
/// more is a 422, so the UI blocks the print instead of sending it.
const maxSpoolLabelsPerRequest = 500;

/// The body of `POST /inventory/labels` / `POST /spoolman/labels`.
///
/// A value type rather than a parameter list, because the two backends take the
/// same body and the shape has already grown twice: every field the server adds
/// otherwise means editing the source interface, both implementations and the
/// repository facade, with nothing but four copies of the same signature
/// keeping them in step. Here it is one field and one line of [toJson].
class SpoolLabelRequest {
  const SpoolLabelRequest({
    required this.spoolIds,
    required this.template,
    this.monochrome = false,
    this.startingPosition = 1,
  }) : assert(startingPosition >= 1, 'sheet positions are numbered from 1');

  /// Also the print order: the server renders in the order it receives ids, so
  /// a caller-chosen sort is what reaches the sheet.
  final List<int> spoolIds;

  final SpoolLabelTemplate template;

  /// Drops the colour swatch (it prints as a muddy grey block) and widens the
  /// text column instead, for black-and-white thermal printers.
  final bool monochrome;

  /// Slot of the first sheet to start printing at, leaving the ones before it
  /// blank so a part-used sheet gets finished. 1 prints a whole sheet, and is
  /// the only value a roll template accepts.
  final int startingPosition;

  Map<String, dynamic> toJson() => {
    'spool_ids': spoolIds,
    'template': template.wire,
    'monochrome': monochrome,
    // Only when it deviates: 1 is the server's own default, and a server
    // too old to know the field would drop it silently either way — sending
    // it unasked would put a key on the wire that proves nothing about who
    // honoured it.
    if (startingPosition > 1) 'starting_position': startingPosition,
  };
}

/// Sort position for the label picker's "by colour" mode.
///
/// Chromatic colours land in bucket 0 ordered by HSL hue (0..360), so a printed
/// sheet reads as a continuous rainbow; neutrals — grey/white/black, plus any
/// spool with a missing or malformed colour — land in bucket 1 ordered by
/// lightness (0..1), trailing the rainbow dark → light.
///
/// Ported from bambuddy's web label modal so both clients lay out a sheet the
/// same way. Callers sort on `bucket` then `pos`, tie-breaking on spool id.
({int bucket, double pos}) spoolColorSortKey(Color? color) {
  if (color == null) return (bucket: 1, pos: 0);

  // Color channels are normalized 0..1, which is what the HSL math expects.
  final r = color.r;
  final g = color.g;
  final b = color.b;
  final max = math.max(r, math.max(g, b));
  final min = math.min(r, math.min(g, b));
  final lightness = (max + min) / 2;
  final delta = max - min;
  // delta == 0 is a pure grey; it also guards the saturation divisor below,
  // which only vanishes at lightness 0 or 1 — both of which imply delta == 0.
  if (delta == 0) return (bucket: 1, pos: lightness);

  final saturation = delta / (1 - (2 * lightness - 1).abs());
  // Generous achromatic cutoff — matches what reads as "grey enough" to someone
  // picking colours, without sending dark muted tones like navy into neutrals.
  if (saturation < 0.1) return (bucket: 1, pos: lightness);

  double hue;
  if (max == r) {
    hue = ((g - b) / delta) % 6;
  } else if (max == g) {
    hue = (b - r) / delta + 2;
  } else {
    hue = (r - g) / delta + 4;
  }
  hue *= 60;
  if (hue < 0) hue += 360;
  return (bucket: 0, pos: hue);
}
