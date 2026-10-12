import 'package:flutter/material.dart';

import '../../core/theme/dash_theme.dart';

/// A caveat under a control, or beside a result: what is about to happen is not what
/// the control looks like it does, or part of an answer is missing and the user is
/// owed the reason.
///
/// **Quiet by default** — tertiary ink, not the amber a fault card uses. [urgent] is
/// for a note about something that will fail the work later, after the point where
/// the user could have done anything about it; amber on notes that turn out not to
/// matter stops being read at all.
///
/// **[urgent] colours the icon, not the sentence.** The light theme's amber is
/// `#E07C36`, 2.7:1 against the palest card: fine for a 16 px mark, under the 4.5:1 a
/// 12 px line has to clear. The tertiary ink the sentence keeps clears it at 4.6:1.
///
/// [announce] reads the note out when it appears: only for the answer to the tap just
/// made, and only where one appears at a time. [icon] is the warning triangle by
/// default; pass a quieter one where the note is a statement of what was not looked at.
class InlineNote extends StatelessWidget {
  const InlineNote(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.only(top: DashSpace.sm),
    this.icon = Icons.warning_amber_rounded,
    this.urgent = false,
    this.announce = false,
  });

  final String text;
  final EdgeInsets padding;
  final IconData icon;
  final bool urgent;
  final bool announce;

  @override
  Widget build(BuildContext context) {
    final t = DashTokens.of(context);
    final ink = urgent ? t.accentOrangeInk : t.textTertiary;
    final row = Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: ink),
          const SizedBox(width: DashSpace.sm),
          Expanded(child: Text(text, style: t.labelSoft)),
        ],
      ),
    );
    return announce
        ? Semantics(container: true, liveRegion: true, child: row)
        : row;
  }
}

/// [InlineNote] for a caller that has a nullable reason rather than a condition
/// — null [text] is "nothing to say", and the caller drops the null.
InlineNote? inlineNote(
  String? text, {
  EdgeInsets padding = const EdgeInsets.only(top: DashSpace.sm),
  IconData icon = Icons.warning_amber_rounded,
  bool urgent = false,
  bool announce = false,
}) => text == null
    ? null
    : InlineNote(
        text,
        padding: padding,
        icon: icon,
        urgent: urgent,
        announce: announce,
      );
