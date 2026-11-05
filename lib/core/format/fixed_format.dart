/// [fixed] without the zeros after its decimal point, and without the point
/// when nothing follows it. A string with no point is returned as it is, so
/// the integer digits of `10` are never touched.
String trimFixedZeros(String fixed) {
  if (!fixed.contains('.')) return fixed;
  final trimmed = fixed.replaceFirst(RegExp(r'0+$'), '');
  return trimmed.endsWith('.')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}
