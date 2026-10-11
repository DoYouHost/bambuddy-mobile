/// Names in the order a person reads them: case does not decide it.
///
/// ponytail: lower-cased `compareTo` standing in for the web's `localeCompare`.
/// It compares UTF-16 code units, so an accented letter sorts after "z" rather
/// than beside its base letter; Dart ships no collator. Swap one in here if
/// that ever matters — every name sort in the app goes through this.
int compareIgnoringCase(String a, String b) =>
    a.toLowerCase().compareTo(b.toLowerCase());
