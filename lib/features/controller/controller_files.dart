import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'controller_controls.dart';

/// The Files tab: the server's file library, scoped to the controller's printer
/// ([docs/single-printer-controller.md]). The library is the only source a print
/// can start from — the server cannot start one from the printer's own storage.
class ControllerFiles extends ConsumerWidget {
  const ControllerFiles({super.key, required this.printerId});

  final int printerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ControllerCard.single(
      title: l10n.controllerTabFiles,
      child: const SizedBox.expand(),
    );
  }
}
