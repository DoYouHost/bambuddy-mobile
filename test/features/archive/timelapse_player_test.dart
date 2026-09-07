import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The timelapse route is authenticated per request, and half of that
/// credential can only reach the player as a header: an `X-API-Key` session
/// gets no `?token=` at all, so a player built from the URL alone loads nothing
/// for those users and fails the way a missing video does — silently.
///
/// A scan rather than a widget test because the failure is an *omission*: the
/// editor's preview shipped without the headers and every test still passed.
/// The rule this keeps is "there is one constructor", which is checkable.
void main() {
  test('every network timelapse player is built by timelapsePlayer', () {
    final builder = RegExp(r'VideoPlayerController\.networkUrl');
    const helper = 'lib/features/archive/timelapse_url.dart';

    final offenders = [
      for (final file
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart')))
        if (file.path != helper && builder.hasMatch(file.readAsStringSync()))
          file.path,
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'Build it with timelapsePlayer(source), which passes both halves of '
          'the credential: the token rides in source.url, but an API-key '
          'session carries an X-API-Key header instead and has no token to put '
          'there.',
    );
  });

  test('the helper still holds the only constructor', () {
    // Guards the scan above from going vacuous if the helper is renamed away.
    final helper = File(
      'lib/features/archive/timelapse_url.dart',
    ).readAsStringSync();

    expect(helper, contains('VideoPlayerController.networkUrl'));
    expect(helper, contains('httpHeaders: source.auth.headers'));
  });
}
