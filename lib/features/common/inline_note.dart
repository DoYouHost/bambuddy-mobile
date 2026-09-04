import 'package:flutter/material.dart';

import '../../core/theme/dash_theme.dart';
import '../../core/theme/dash_text.dart';

/// A caveat under a control, or beside a result: what is about to happen is not
/// what the control looks like it does, or part of an answer is missing and the
/// user is owed the reason.
///
/// **Quiet by default** — tertiary ink, not the amber a fault card uses. Most
/// of these sit next to a setting the user chose and is still free to change,
/// and the job goes ahead either way. [urgent] is for the one that is not like
/// that: a note about something that will fail the work later, after the point
/// where the user could have done anything about it. Grey is an honest colour
/// for every other note and the wrong one for that, and amber that appears next
/// to things that turn out not to matter stops being read at all.
///
/// **[urgent] colours the icon, not the sentence.** The light theme's amber is
/// `#E07C36`, which reads 2.7:1 against the palest card — fine for a 16 px
/// mark, and well under the 4.5:1 a 12 px line has to clear, so the one note
/// the user most needs to read was the hardest one to. The tertiary ink it
/// keeps instead clears it at 4.6:1, and the amber still marks the row.
///
/// [announce] reads the note out when it appears. Only for a note that is the
/// answer to the tap just made, and only where one of them appears at a time: a
/// change that raises several would read them all out in a row, which is worse
/// than the silence.
///
/// [icon] is the warning triangle by default. Pass a quieter one where the note
/// is not a caveat at all but a statement of what was not looked at.
class InlineNote extends StatelessWidget {
  const InlineNote(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.only(top: 6),
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
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: t.labelSoft),
          ),
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
  EdgeInsets padding = const EdgeInsets.only(top: 6),
  IconData icon = Icons.warning_amber_rounded,
  bool urgent = false,
  bool announce = false,
}) =>
    text == null
        ? null
        : InlineNote(
            text,
            padding: padding,
            icon: icon,
            urgent: urgent,
            announce: announce,
          );
