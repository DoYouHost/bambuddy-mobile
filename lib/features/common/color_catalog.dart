import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ams/color_names.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';

/// The server's colour catalogue; empty when it cannot be read, and names
/// then come from the hue alone.
final colorNameCatalogProvider = FutureProvider.autoDispose<ColorCatalog>(
  (ref) => ref
      .watch(amsSlotConfigRepositoryProvider)
      .colorCatalog()
      .catchError((Object _) => ColorCatalog.empty),
);

extension ColorNameCatalogRef on WidgetRef {
  /// The catalogue as far as it has loaded: [ColorCatalog.empty] until then,
  /// so a name never waits for the network.
  ColorCatalog watchColorNames() =>
      watch(colorNameCatalogProvider).value ?? ColorCatalog.empty;

  ColorCatalog readColorNames() =>
      read(colorNameCatalogProvider).value ?? ColorCatalog.empty;
}

/// `getColorName`: the catalogue's name, else the hue family's.
String colorDisplayName(
  AppLocalizations l10n,
  ColorCatalog catalog,
  String? hex, {
  String? material,
}) =>
    catalog.nameOf(hex, material: material) ??
    switch (colorFamily(hex)) {
      ColorFamily.red => l10n.colorFamilyRed,
      ColorFamily.orange => l10n.colorFamilyOrange,
      ColorFamily.yellow => l10n.colorFamilyYellow,
      ColorFamily.green => l10n.colorFamilyGreen,
      ColorFamily.cyan => l10n.colorFamilyCyan,
      ColorFamily.blue => l10n.colorFamilyBlue,
      ColorFamily.purple => l10n.colorFamilyPurple,
      ColorFamily.pink => l10n.colorFamilyPink,
      ColorFamily.brown => l10n.colorFamilyBrown,
      ColorFamily.white => l10n.colorFamilyWhite,
      ColorFamily.lightGray => l10n.colorFamilyLightGray,
      ColorFamily.gray => l10n.colorFamilyGray,
      ColorFamily.darkGray => l10n.colorFamilyDarkGray,
      ColorFamily.black => l10n.colorFamilyBlack,
      ColorFamily.clear => l10n.colorFamilyClear,
      null => l10n.colorFamilyUnknown,
    };
