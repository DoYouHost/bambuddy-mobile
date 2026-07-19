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
  averyL7160('avery_l7160'),
  avery5160('avery_5160');

  const SpoolLabelTemplate(this.wire);

  /// Value sent as `template` in the request body.
  final String wire;
}

/// Server-side cap on one label request (`MAX_LABELS_PER_REQUEST`). Asking for
/// more is a 422, so the UI blocks the print instead of sending it.
const maxSpoolLabelsPerRequest = 500;

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
