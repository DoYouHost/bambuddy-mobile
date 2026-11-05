/// Trims [value]; a blank one becomes null, which a form reads as "unset" and
/// sends no key for.
String? trimmedOrNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
