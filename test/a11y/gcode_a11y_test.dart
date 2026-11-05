import 'dart:async';

import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/features/gcode/gcode_viewer_screen.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// A credentials store whose token read never answers, which parks the viewer
/// in its loading state before it builds a WebView.
class _StalledCredentials extends InMemoryCredentialsStore {
  @override
  Future<String?> readJwt() => Completer<String?>().future;
}

/// Rendered contrast and touch targets of the G-code viewer's own Flutter
/// surfaces, on a landscape phone (the shape it is designed for): the loading
/// state and the failure view the screen shows when it has no server. Not
/// covered, because they exist only inside the WebView, which a widget test
/// cannot host (there is no WebView platform behind it): the page's layer
/// slider, legend and colour modes, its own progress text, and the failure
/// views for an empty file or an HTTP refusal, which the page reports over its
/// JavaScript channel.
void main() {
  a11ySurface(
    'gcode viewer, loading',
    demo: false,
    window: landscapeRedmi,
    overrides: [
      fakeServerProfileOverride(authMode: AuthMode.jwt),
      credentialsStoreProvider.overrideWithValue(_StalledCredentials()),
    ],
    home: () => const GcodeViewerScreen(archiveId: 1, title: 'Benchy'),
    shows: find.byType(CircularProgressIndicator),
  );

  a11ySurface(
    'gcode viewer, failed to start',
    demo: false,
    window: landscapeRedmi,
    home: () => const GcodeViewerScreen(libraryFileId: 1),
    shows: find.text(pl.gcodeViewerError),
  );
}
