import 'package:flutter/material.dart';

/// The words that name a section, marked as a heading for a screen reader.
///
/// A heading is how someone using TalkBack or VoiceOver moves through a long
/// screen: the reader offers "jump to next heading", and a section title that
/// is only a bold `Text` is not one — it arrives in the middle of the run of
/// content it was supposed to introduce.
///
/// This carries the semantics and nothing else. The app's section headers are
/// four genuinely different layouts — a title with a subtitle under it, a title
/// with a count chip beside it, a title with a button opposite — and folding
/// them into one widget would take a parameter per variation to render four
/// different things. What they share is this one line, and having it here is
/// what makes the next section header remember it.
///
/// Only the words go inside. A control that sits beside the title — a
/// "Select all", a count — must stay outside it: merged into a heading it stops
/// reading as the button it is.
///
/// Screen titles need no help: `AppBar` marks its own. A sheet has no app bar,
/// so its title does.
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.text, {super.key, required this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) =>
      Semantics(header: true, child: Text(text, style: style));
}
