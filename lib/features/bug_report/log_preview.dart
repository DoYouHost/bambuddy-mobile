/// How much of a session the review screen renders.
///
/// The raw block exists for one question — "what am I about to send?" — and a
/// sample answers it as well as the whole thing does. Rendering the whole thing
/// does not scale with it: the session goes out from its file now, so it is
/// bounded by `recordingSizeLimit` (20 MB) rather than by the ring, and a
/// `SelectableText` lays out every character it is given, in UTF-16, on the
/// frame the user taps "show raw log".
const logPreviewChars = 24 * 1024;

/// A window onto a session: what to render, and how much of the start it leaves
/// out.
typedef LogPreview = ({String text, int hiddenChars});

/// The session's header line plus the tail of its records, clipped to
/// [maxChars] on a line boundary.
///
/// The tail rather than the head because that is where the bug is: the user
/// stops recording right after reproducing it. The header line survives the clip
/// regardless — it carries the app version, the flavour and the server's shape,
/// which is the context every record underneath is read against.
LogPreview logPreview(String log, {int maxChars = logPreviewChars}) {
  if (log.length <= maxChars) return (text: log, hiddenChars: 0);

  final firstBreak = log.indexOf('\n');
  // A log with no line break at all is not a session; clip it as plain text
  // rather than pretend the first line is a header.
  final header = firstBreak < 0 ? '' : log.substring(0, firstBreak + 1);
  final body = log.substring(header.length);
  final budget = maxChars - header.length;
  if (budget <= 0) return (text: header, hiddenChars: body.length);

  // Start the window at the record boundary after the cut, so the first record
  // shown is a whole one — half a JSON line reads as corruption.
  final cut = body.length - budget;
  final boundary = body.indexOf('\n', cut);
  final start = boundary < 0 ? cut : boundary + 1;
  return (text: '$header${body.substring(start)}', hiddenChars: start);
}
