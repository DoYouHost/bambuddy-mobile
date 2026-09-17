import 'dart:async';

import 'package:bambuddy_mobile/core/settings/server_profile.dart';
import 'package:bambuddy_mobile/features/camera/camera_view.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:bambuddy_mobile/features/camera/mjpeg_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  group('CameraView', () {
    testWidgets('renders demo unavailable banner when in demo mode', (
      tester,
    ) async {
      await pumpPhone(
        tester,
        const CameraView(printerId: 1, printerName: 'Demo X1C'),
        overrides: [
          serverProfileOverride(
            const ServerProfile(
              baseUrl: 'http://demo',
              authMode: AuthMode.none,
            ),
          ),
        ],
      );
      await settle(tester);

      expect(find.byIcon(Icons.videocam_off), findsOneWidget);
      expect(find.text('Demo X1C'), findsOneWidget);
    });

    testWidgets('renders loading view while camera token is loading', (
      tester,
    ) async {
      final completer = Completer<String>();

      await pumpPhone(
        tester,
        const CameraView(printerId: 1, printerName: 'Lab P1S'),
        overrides: [
          fakeServerProfileOverride(),
          cameraTokenProvider.overrideWith((ref) => completer.future),
        ],
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Lab P1S'), findsOneWidget);
    });

    testWidgets('renders error view with retry button on token failure', (
      tester,
    ) async {
      await pumpPhone(
        tester,
        const CameraView(printerId: 1, printerName: 'Lab P1S'),
        overrides: [
          fakeServerProfileOverride(),
          cameraTokenProvider.overrideWith(
            (ref) => throw Exception('auth failure'),
          ),
        ],
      );
      await settle(tester);

      expect(find.byIcon(Icons.videocam_off), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Lab P1S'), findsOneWidget);
    });

    testWidgets(
      'points the stream at the printer route with the minted token',
      (tester) async {
        await pumpPhone(
          tester,
          const CameraView(printerId: 7, printerName: 'Farm A1'),
          overrides: [
            fakeServerProfileOverride(),
            cameraTokenProvider.overrideWith(
              (ref) async => 'secret-stream-token',
            ),
          ],
        );
        await settle(tester);

        // What the stream does with the URL is covered on a device, in
        // `integration_test/camera_stream_test.dart`.
        final view = tester.widget<MjpegView>(find.byType(MjpegView));
        expect(view.url, contains('/api/v1/printers/7/camera/stream'));
        expect(view.url, contains('token=secret-stream-token'));
      },
    );
  });
}
