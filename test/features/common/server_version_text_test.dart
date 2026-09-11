import 'package:bambuddy_mobile/features/common/server_version_text.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  test('a version the server gave is printed as it came', () {
    expect(
      serverVersionText(l10n, const AsyncData('1.2.6b1')),
      'Server 1.2.6b1',
    );
  });

  test('while the read is in flight the label keeps its place', () {
    // Not "unknown": that would be a wrong answer for as long as the request
    // is out, and the line would then change twice.
    expect(serverVersionText(l10n, const AsyncLoading()), 'Server …');
  });

  test('every way of not knowing lands on the same sentence', () {
    // An older bambuddy with no /updates/version route answers null; a read
    // that threw arrives as an error. One fact to the reader, one sentence.
    for (final unknown in <AsyncValue<String?>>[
      const AsyncData(null),
      AsyncError(Exception('unreachable'), StackTrace.empty),
    ]) {
      expect(
        serverVersionText(l10n, unknown),
        'Server version unknown',
        reason: '$unknown',
      );
    }
  });
}
