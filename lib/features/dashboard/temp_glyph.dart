import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/dash_theme.dart';
import '../../l10n/app_localizations.dart';
import 'temp_readings.dart';

/// The pictogram of a temperature sensor: a hotend, a heated bed or a chamber.
///
/// The chamber's drawing carries the air-duct mode (waves = heating, snowflake =
/// cooling, an empty box = a printer with no duct mode), so the mode never rests
/// on [color] alone. [color] is the heat state, which is the one thing the tile
/// colours.
class TempGlyph extends StatelessWidget {
  const TempGlyph({
    super.key,
    required this.kind,
    required this.color,
    this.airductIsHeating,
    this.semanticLabel,
  }) : asset = null;

  /// The BIQU Panda Breath, a chamber heater of its own: an air-flow drawing.
  const TempGlyph.panda({super.key, required this.color, this.semanticLabel})
    : kind = TempKind.unknown,
      airductIsHeating = null,
      asset = pandaAsset;

  static const pandaAsset = 'assets/icons/temp_panda.svg';

  /// An asset that replaces the one [kind] picks: the Panda Breath's.
  final String? asset;

  final TempKind kind;
  final Color color;

  /// Chamber only: the duct runs heating (true), cooling (false) or the printer
  /// reports no mode (null).
  final bool? airductIsHeating;
  final String? semanticLabel;

  /// The asset for [kind], or null for a sensor that has no pictogram (an
  /// unknown key keeps its own name as text).
  static String? assetFor(TempKind kind, {bool? airductIsHeating}) =>
      switch (kind) {
        TempKind.nozzle => 'assets/icons/temp_nozzle.svg',
        TempKind.bed => 'assets/icons/temp_bed.svg',
        TempKind.chamber => switch (airductIsHeating) {
          true => 'assets/icons/temp_chamber_heating.svg',
          false => 'assets/icons/temp_chamber_cooling.svg',
          null => 'assets/icons/temp_chamber.svg',
        },
        TempKind.unknown => null,
      };

  /// Side of the drawing at a text scale. It follows the text, like the digits
  /// beside it; `tempGridColumns` measures the same number.
  static double extent(TextScaler scaler) => scaler.scale(DashIcon.sm);

  @override
  Widget build(BuildContext context) {
    final asset =
        this.asset ?? assetFor(kind, airductIsHeating: airductIsHeating);
    if (asset == null) return const SizedBox.shrink();
    final side = extent(MediaQuery.textScalerOf(context));
    return SvgPicture.asset(
      asset,
      width: side,
      height: side,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      semanticsLabel: semanticLabel,
      // Without a name the drawing is decoration: the text beside it speaks.
      excludeFromSemantics: semanticLabel == null,
    );
  }
}

/// A reading's name as the card, the sheet and a screen reader say it. On two
/// heads the plain key is the first nozzle, not "the" nozzle, as on the
/// controller: "Nozzle 1" and "Nozzle 2".
String tempDisplayName(
  TempReading reading, {
  required bool dualNozzle,
  required AppLocalizations l10n,
}) => dualNozzle && reading.kind == TempKind.nozzle && reading.index == null
    ? l10n.tempNozzleNumbered('1')
    : reading.label(l10n);

/// The short mark beside a nozzle's pictogram, or null where none is needed.
/// On two heads it is the left or right head's letter, as the web writes them
/// (the plain key is the left head, `nozzle_2` the right); a rack printer shows
/// the mounted nozzle's rack position; a single hotend needs nothing.
String? tempGlyphTag(
  TempReading reading, {
  required bool dualNozzle,
  required AppLocalizations l10n,
}) {
  if (reading.kind != TempKind.nozzle) return null;
  if (dualNozzle) {
    return reading.index == null
        ? l10n.extruderLeftShort
        : l10n.extruderRightShort;
  }
  return reading.rackPosition?.toString();
}
