import 'package:material_ui/material_ui.dart';

import '../../../core/models/ai_detection.dart';
import '../../../core/theme/dash_theme.dart';
import '../../../l10n/app_localizations.dart';
import 'print_meta_row.dart';

/// The word for a detection class, as the web's badge words it
/// (`printers.aiDetection.*`).
String aiDetectionLabel(AppLocalizations l10n, AiDetectionClass cls) =>
    switch (cls) {
      AiDetectionClass.safe => l10n.aiDetectionSafe,
      AiDetectionClass.warning => l10n.aiDetectionWarning,
      AiDetectionClass.failure => l10n.aiDetectionFailure,
      AiDetectionClass.error => l10n.aiDetectionNotChecking,
      AiDetectionClass.unknown => l10n.aiDetectionStarting,
    };

/// The sentence behind the item: the web badge's `title` in `PrintersPage.tsx`,
/// branch by branch, without its "click for details".
///
/// A class that is no verdict quotes no measurement: "Safe (0.000)" for a print
/// nothing is looking at is the whole of server #2952.
String aiDetectionSentence(AppLocalizations l10n, AiDetection detection) {
  final status = aiDetectionLabel(l10n, detection.cls);
  switch (detection.cls) {
    case AiDetectionClass.error:
      final reason = detection.usageLimitReached
          ? l10n.aiDetectionLimitReached
          : detection.error;
      return reason == null || reason.isEmpty
          ? l10n.aiDetectionTipErrorNoReason
          : l10n.aiDetectionTipError(reason);
    case AiDetectionClass.unknown:
      return l10n.aiDetectionTipStarting;
    case AiDetectionClass.safe ||
        AiDetectionClass.warning ||
        AiDetectionClass.failure:
      final quality = detection.printQuality;
      if (quality != null) return l10n.aiDetectionTipQuality(status, quality);
      final score = detection.score;
      if (score != null && !detection.ratesQuality) {
        return l10n.aiDetectionTipScore(status, score.toStringAsFixed(3));
      }
      return l10n.aiDetectionTipStatus(status);
  }
}

/// The AI failure detection item of the print panel's meta row: an eye and the
/// class, in the class's colour. The sentence is what a screen reader says and
/// what a tap shows. Null without an entry — unlike the web, which keeps a grey
/// "Idle" badge on every monitored card, a card here says nothing between
/// prints.
PrintMetaItem? aiDetectionMetaItem(
  BuildContext context,
  AppLocalizations l10n,
  AiDetection? detection,
) {
  if (detection == null) return null;
  final t = DashTokens.of(context);
  final sentence = aiDetectionSentence(l10n, detection);
  return PrintMetaItem(
    icon: detection.cls == AiDetectionClass.error
        ? Icons.visibility_off_outlined
        : Icons.visibility_outlined,
    text: aiDetectionLabel(l10n, detection.cls),
    color: switch (detection.cls) {
      AiDetectionClass.failure => t.dangerInk,
      AiDetectionClass.warning => t.warningInk,
      AiDetectionClass.safe => t.accentGreenInk,
      AiDetectionClass.error => t.accentOrangeInk,
      AiDetectionClass.unknown => null,
    },
    semanticLabel: sentence,
    tooltip: sentence,
  );
}
