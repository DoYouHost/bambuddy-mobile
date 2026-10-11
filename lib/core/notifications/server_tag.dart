import '../format/stable_digest.dart';

/// The server a notification's payload belongs to, as a digest rather than in
/// the clear. A payload names rows by id — a printer, an archive — and an id
/// means something only on the server that sent it, while the notification
/// outlives a switch to another server, where the same id is somebody else's.
String serverTag(String baseUrl) => stableDigest(baseUrl).toRadixString(16);
