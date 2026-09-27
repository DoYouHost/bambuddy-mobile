/// 32-bit FNV-1a of [s] — the same number in every isolate and on every run.
///
/// Spelled out rather than taken from `Object.hash` / `String.hashCode`, whose
/// seed is drawn afresh on every VM start: the foreground service restarts
/// each time the app is backgrounded, and a notification id or payload built
/// from a seeded hash stops matching the one already on screen.
int stableDigest(String s) {
  var h = 0x811c9dc5;
  for (var i = 0; i < s.length; i++) {
    h = ((h ^ s.codeUnitAt(i)) * 0x01000193) & 0xffffffff;
  }
  return h;
}
