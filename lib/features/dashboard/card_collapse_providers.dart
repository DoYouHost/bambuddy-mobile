import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';

/// The app setting: whether printer cards open collapsed.
final printerCardsCollapsedByDefaultProvider =
    NotifierProvider<PrinterCardsCollapsedByDefaultNotifier, bool>(
      PrinterCardsCollapsedByDefaultNotifier.new,
    );

class PrinterCardsCollapsedByDefaultNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(settingsRepositoryProvider).loadPrinterCardsCollapsed();

  Future<void> set(bool collapsed) async {
    await ref
        .read(settingsRepositoryProvider)
        .savePrinterCardsCollapsed(collapsed);
    if (!ref.mounted) return;
    state = collapsed;
  }
}

/// Which cards are collapsed right now: the setting, plus what the user
/// toggled by hand since the app started.
///
/// Held here rather than in the card's `State` because the dashboard list
/// builds lazily — a card scrolled out of view is disposed, and would come back
/// in the default look. Deliberately not persisted, and deliberately rebuilt
/// from scratch when the setting changes: flipping it is a request to see every
/// card that way.
final printerCardCollapseProvider =
    NotifierProvider<PrinterCardCollapseNotifier, PrinterCardCollapse>(
      PrinterCardCollapseNotifier.new,
    );

class PrinterCardCollapse {
  const PrinterCardCollapse({required this.byDefault, this.toggled = const {}});

  final bool byDefault;

  /// Printer id → collapsed, for the cards toggled by hand.
  final Map<int, bool> toggled;

  bool isCollapsed(int printerId) => toggled[printerId] ?? byDefault;
}

class PrinterCardCollapseNotifier extends Notifier<PrinterCardCollapse> {
  @override
  PrinterCardCollapse build() => PrinterCardCollapse(
    byDefault: ref.watch(printerCardsCollapsedByDefaultProvider),
  );

  void set(int printerId, bool collapsed) => state = PrinterCardCollapse(
    byDefault: state.byDefault,
    toggled: {...state.toggled, printerId: collapsed},
  );
}

/// The app setting: whether printer cards draw their filament as compact tiles.
final compactAmsLayoutProvider =
    NotifierProvider<CompactAmsLayoutNotifier, bool>(
      CompactAmsLayoutNotifier.new,
    );

class CompactAmsLayoutNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(settingsRepositoryProvider).loadCompactAmsLayout();

  Future<void> set(bool compact) async {
    await ref.read(settingsRepositoryProvider).saveCompactAmsLayout(compact);
    if (!ref.mounted) return;
    state = compact;
  }
}

/// Which cards draw compact tiles right now: the setting, plus what the user
/// switched by hand on a card since the app started. Held here for the same
/// reason as [printerCardCollapseProvider] (a scrolled-out card is disposed),
/// and rebuilt from the setting when it changes, so flipping it restyles every
/// card.
final printerCompactAmsProvider =
    NotifierProvider<PrinterCompactAmsNotifier, PrinterCompactAms>(
      PrinterCompactAmsNotifier.new,
    );

class PrinterCompactAms {
  const PrinterCompactAms({required this.byDefault, this.toggled = const {}});

  final bool byDefault;

  /// Printer id → compact, for the cards switched by hand.
  final Map<int, bool> toggled;

  bool isCompact(int printerId) => toggled[printerId] ?? byDefault;
}

class PrinterCompactAmsNotifier extends Notifier<PrinterCompactAms> {
  @override
  PrinterCompactAms build() =>
      PrinterCompactAms(byDefault: ref.watch(compactAmsLayoutProvider));

  void set(int printerId, bool compact) => state = PrinterCompactAms(
    byDefault: state.byDefault,
    toggled: {...state.toggled, printerId: compact},
  );
}
