import 'dart:convert';
import 'dart:typed_data';

import 'package:bambuddy_mobile/core/models/timelapse.dart';
import 'package:bambuddy_mobile/features/archive/timelapse_export.dart';
import 'package:bambuddy_mobile/features/archive/timelapse_format.dart';
import 'package:bambuddy_mobile/features/archive/timelapse_providers.dart';
import 'package:bambuddy_mobile/features/archive/timelapse_trim.dart';
import 'package:bambuddy_mobile/features/archive/timelapse_trim_strip.dart';
import 'package:bambuddy_mobile/features/archive/timelapse_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

const _info = TimelapseInfo(
  duration: 54,
  width: 1920,
  height: 1080,
  fps: 30,
  codec: 'h264',
  fileSize: 12345,
  hasAudio: false,
);

/// 1×1 JPEG — enough for the strip to have something decodable in it.
const _jpeg =
    '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0a'
    'HBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAA'
    'AQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIh'
    'MUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpT'
    'VFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5'
    'usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD3+iii'
    'gD//2Q==';

void main() {
  group('formatClock', () {
    test('below an hour with no leading zero', () {
      expect(formatClock(0), '0:00');
      expect(formatClock(7), '0:07');
      expect(formatClock(54), '0:54');
      expect(formatClock(605), '10:05');
    });

    test('above an hour adds the hour component', () {
      expect(formatClock(3661), '1:01:01');
    });

    test(
      'truncates fractional seconds — clock does not outrun the footage',
      () {
        expect(formatClock(0.6), '0:00');
        expect(formatClock(1.9), '0:01');
      },
    );
  });

  group('formatSpeed', () {
    test('trims trailing zeros', () {
      expect(formatSpeed(1), '1x');
      expect(formatSpeed(0.25), '0.25x');
      expect(formatSpeed(1.5), '1.5x');
    });
  });

  group('preview loop', () {
    test('in the middle of the range does not wrap', () {
      expect(timelapseReachedEnd(5, 30), isFalse);
    });

    test('end of range catches with margin for frame spacing', () {
      expect(timelapseReachedEnd(29.95, 30), isTrue);
      expect(timelapseReachedEnd(31, 30), isTrue);
    });

    test('an undershoot seek near range start does NOT wrap in a loop', () {
      // Regression: the guard rule for the start also triggered on its own
      // undershoot — seek, undershoot, seek. The decoder only flushed
      // buffers, the image did not move.
      expect(
        timelapseReachedEnd(9.98, 30),
        isFalse,
        reason: 'a position just below the 10s start is not the range end',
      );
    });

    test('start of playback rewinds from outside range and from its end', () {
      expect(timelapseNeedsRewind(9.98, 10, 30), isTrue);
      expect(timelapseNeedsRewind(29.99, 10, 30), isTrue);
      expect(timelapseNeedsRewind(15, 10, 30), isFalse);
    });
  });

  group('file container', () {
    test('extension comes from content type, not assumption', () {
      expect(timelapseExtension('video/mp4'), 'mp4');
      expect(timelapseExtension('video/x-msvideo'), 'avi');
      expect(timelapseExtension('video/x-matroska'), 'mkv');
    });

    test('parameters and letter case do not confuse recognition', () {
      expect(timelapseExtension('Video/X-MSVideo; charset=binary'), 'avi');
    });

    test(
      'missing or unknown type is mp4, since that is the server default',
      () {
        expect(timelapseExtension(null), 'mp4');
        expect(timelapseExtension('application/octet-stream'), 'mp4');
      },
    );

    test('type to share comes back from the file extension', () {
      expect(timelapseMimeType('/tmp/a_timelapse.avi'), 'video/x-msvideo');
      expect(timelapseMimeType('/tmp/a_timelapse.mp4'), 'video/mp4');
    });
  });

  group('exportFilename', () {
    test('builds filename from print name', () {
      expect(exportFilename('Part Studio 1'), 'Part_Studio_1_timelapse.mp4');
    });

    test('takes the container the server named the file with', () {
      expect(exportFilename('Part', 'avi'), 'Part_timelapse.avi');
    });

    test('strips characters that break saving or sharing', () {
      expect(exportFilename('a/b\\c:d*?'), 'abcd_timelapse.mp4');
      expect(exportFilename('  ../etc  '), 'etc_timelapse.mp4');
    });

    test('empty name does not produce a file starting with underscore', () {
      expect(exportFilename('///'), 'timelapse_timelapse.mp4');
    });

    test('keeps letters of any script, so a folder of videos stays usable', () {
      // `\w` is ASCII in Dart: before the Unicode class this reduced "Łódź" to
      // "d" and a Japanese name to nothing at all, so every such print saved as
      // the same fallback name.
      expect(exportFilename('Łódź'), 'Łódź_timelapse.mp4');
      expect(exportFilename('日本語 x2'), '日本語_x2_timelapse.mp4');
      // Emoji are neither letter nor digit and a share target may refuse them.
      expect(exportFilename('Benchy 🎉'), 'Benchy_timelapse.mp4');
    });
  });

  group('TimelapseFilmstrip.fromJson', () {
    test('decodes frames and timestamps', () {
      final strip = TimelapseFilmstrip.fromJson({
        'thumbnails': [_jpeg, _jpeg],
        'timestamps': [0, 3.5],
      });

      expect(strip.frames, hasLength(2));
      expect(strip.timestamps, [0.0, 3.5]);
      expect(strip.isEmpty, isFalse);
    });

    test('an undecodable frame does not take down the whole strip', () {
      final strip = TimelapseFilmstrip.fromJson({
        'thumbnails': [_jpeg, 'nie-base64!!'],
        'timestamps': [0, 1],
      });

      expect(strip.frames, hasLength(1));
    });

    test('missing fields give an empty strip, not an exception', () {
      expect(TimelapseFilmstrip.fromJson(const {}).isEmpty, isTrue);
    });
  });

  group('framesFitting', () {
    final all = List.generate(14, (i) => i);

    test('on a narrow strip no frame drops below a readable width', () {
      const stripWidth = 517.0;
      final shown = framesFitting(all, stripWidth);

      expect(stripWidth / shown.length, greaterThanOrEqualTo(56.0));
      expect(
        shown,
        hasLength(lessThan(all.length)),
        reason: 'at this width the full set does not fit',
      );
    });

    test('samples across the whole footage, not from its start', () {
      final shown = framesFitting(all, 517);

      expect(shown, orderedEquals(shown.toList()..sort()));
      expect(shown.toSet(), hasLength(shown.length), reason: 'no repeats');
      expect(
        shown.last,
        greaterThan(all.length ~/ 2),
        reason: 'last sample from the second half, not the first',
      );
    });

    test('every frame lands under the moment it shows', () {
      // 14 frames over 6 tiles. Tile i occupies [i/6, (i+1)/6] of the footage,
      // frame j is from moment j/14 — so the one closest to its center fits
      // the tile. When sampling "from the tile's start" the last tile
      // (83-100%) got a frame from 78.6% and the tail could not be trimmed.
      final shown = framesFitting(all, 360);

      expect(shown, hasLength(6));
      for (var i = 0; i < shown.length; i++) {
        final tileStart = i / shown.length;
        final tileEnd = (i + 1) / shown.length;
        final frameAt = shown[i] / all.length;
        expect(
          frameAt,
          greaterThanOrEqualTo(tileStart - 0.001),
          reason: 'frame $i is ahead of its tile',
        );
        expect(
          frameAt,
          lessThanOrEqualTo(tileEnd + 0.001),
          reason: 'frame $i is behind its tile',
        );
      }
    });

    test('the last tile shows the last frame the server rendered', () {
      expect(framesFitting(all, 360).last, all.last);
      expect(framesFitting(all, 517).last, all.last);
    });

    test('when everything fits, none is dropped', () {
      expect(framesFitting(all, 2000), all);
    });

    test('empty list and zero width do not crash', () {
      expect(framesFitting(<int>[], 500), isEmpty);
      expect(framesFitting(all, 0), hasLength(1));
    });
  });

  group('trim strip', () {
    // 300px for 60s of footage. The timeline is inset by handle width on
    // each side, so the strip's center falls at 30s.
    const width = 300.0;
    const duration = 60.0;

    Future<({List<RangeValues> trims, List<double> ends, List<double> seeks})>
    pumpStrip(
      WidgetTester tester, {
      RangeValues trim = const RangeValues(0, duration),
      double? position,
      List<Uint8List> frames = const [],
    }) async {
      final trims = <RangeValues>[];
      final ends = <double>[];
      final seeks = <double>[];
      var current = trim;
      await tester.pumpWidget(
        plApp(
          Center(
            child: SizedBox(
              width: width,
              // The range feeds back to the strip the way the editor does — without
              // this loop the widget in the test would see a forever-stale range and
              // assertions would measure the harness, not the product.
              child: StatefulBuilder(
                builder: (context, setState) => TimelapseTrimStrip(
                  frames: frames,
                  duration: duration,
                  trim: current,
                  minClip: 1,
                  position: position,
                  onTrimChanged: (v) {
                    trims.add(v);
                    setState(() => current = v);
                  },
                  onTrimCommitted: ends.add,
                  onSeek: seeks.add,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (trims: trims, ends: ends, seeks: seeks);
    }

    Rect rectOf(WidgetTester tester, Key key) =>
        tester.getRect(find.byKey(key));

    Rect playheadRect(WidgetTester tester) =>
        rectOf(tester, TimelapseTrimStrip.playheadKey);

    testWidgets('dragging the left handle moves the range start', (
      tester,
    ) async {
      final r = await pumpStrip(tester);
      final strip = tester.getRect(find.byType(TimelapseTrimStrip));

      // Grab on the left handle (start = 0s sits at 12px), drag to
      // 58px, i.e. 46px along the track = 10s.
      await tester.dragFrom(
        Offset(strip.left + 2, strip.center.dy),
        const Offset(56, 0),
      );
      await tester.pumpAndSettle();

      expect(r.trims, isNotEmpty);
      expect(r.trims.last.start, closeTo(10, 0.5));
      expect(r.trims.last.end, duration, reason: 'end untouched');
      expect(
        r.ends,
        hasLength(1),
        reason: 'preview seek only once, on release',
      );
      expect(
        r.ends.single,
        closeTo(r.trims.last.start, 0.01),
        reason: 'preview parks at the dragged start, not the end',
      );
    });

    testWidgets('releasing the right handle parks the preview at its end', (
      tester,
    ) async {
      final r = await pumpStrip(tester);
      final strip = tester.getRect(find.byType(TimelapseTrimStrip));

      await tester.dragFrom(
        Offset(strip.right - 2, strip.center.dy),
        const Offset(-56, 0),
      );
      await tester.pumpAndSettle();

      expect(r.ends.single, closeTo(r.trims.last.end, 0.01));
    });

    testWidgets('grabbing a handle does not scrub the preview', (tester) async {
      // onTapDown fired before dragging won the gesture arena, so
      // just grabbing the handle jerked the playhead to the touch point.
      final r = await pumpStrip(tester, trim: const RangeValues(20, 40));
      final strip = tester.getRect(find.byType(TimelapseTrimStrip));
      final startHandle = rectOf(tester, TimelapseTrimStrip.startHandleKey);

      // The finger first rests on the handle for a moment — that's how it's
      // grabbed, and only then does tap recognition have time to clear its
      // time threshold. A drag started immediately would not reproduce this bug.
      final gesture = await tester.startGesture(
        Offset(startHandle.center.dx, strip.center.dy),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(r.trims, isNotEmpty, reason: 'the handle did move');
      expect(r.seeks, isEmpty, reason: 'no seek while grabbing the handle');
    });

    testWidgets(
      'footage shorter than the minimum clip does not crash the gesture',
      (tester) async {
        // clamp(0, end - minClip) throws when the bounds cross — and with 0.5s
        // of footage they always cross.
        await tester.pumpWidget(
          plApp(
            Center(
              child: SizedBox(
                width: width,
                child: TimelapseTrimStrip(
                  frames: const [],
                  duration: 0.5,
                  trim: const RangeValues(0, 0.5),
                  minClip: 1,
                  onTrimChanged: (_) {},
                  onTrimCommitted: (_) {},
                  onSeek: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final strip = tester.getRect(find.byType(TimelapseTrimStrip));

        await tester.dragFrom(
          Offset(strip.left + 2, strip.center.dy),
          const Offset(56, 0),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('dragging the middle of the strip scrubs, not trims', (
      tester,
    ) async {
      final r = await pumpStrip(tester);
      final strip = tester.getRect(find.byType(TimelapseTrimStrip));

      // The drag must exceed the touch threshold (18px), otherwise the system
      // reads it as a tap — hence 30px, not a dozen or so.
      await tester.dragFrom(strip.center, const Offset(30, 0));
      await tester.pumpAndSettle();

      expect(r.trims, isEmpty, reason: 'range unchanged');
      expect(
        r.seeks.last,
        closeTo(36.5, 0.5),
        reason: '180px is 168px along the track, i.e. 36.5s',
      );
    });

    testWidgets('the playhead does not go under the handles', (tester) async {
      // At both ends of the footage the playhead must not overlap the rendered
      // handle — checked on the rects, not a widget constant.
      for (final at in [0.0, duration]) {
        await pumpStrip(tester, position: at);
        final line = playheadRect(tester);

        expect(
          line.overlaps(rectOf(tester, TimelapseTrimStrip.startHandleKey)),
          isFalse,
          reason: 'playhead at ${at}s goes under the left handle',
        );
        expect(
          line.overlaps(rectOf(tester, TimelapseTrimStrip.endHandleKey)),
          isFalse,
          reason: 'playhead at ${at}s goes under the right handle',
        );
      }
    });

    testWidgets(
      'playhead moves from the first second, no standstill at start',
      (tester) async {
        // Regression: the playhead was clamped to edges computed from the trim
        // range, so for the first ~2.5s it stood still even though the footage
        // was already playing. The test does not recompute the formula — it
        // checks that successive seconds give successive, growing positions.
        final seen = <double>[];
        for (final second in [0.0, 1.0, 2.0, 3.0, 30.0, duration]) {
          await pumpStrip(tester, position: second);
          seen.add(playheadRect(tester).center.dx);
        }

        for (var i = 1; i < seen.length; i++) {
          expect(
            seen[i],
            greaterThan(seen[i - 1]),
            reason: 'second $i did not move the playhead',
          );
        }
      },
    );

    testWidgets('trimming does not shift or scale the frames', (tester) async {
      await pumpStrip(tester);
      final full = rectOf(tester, TimelapseTrimStrip.framesKey);

      await pumpStrip(tester, trim: const RangeValues(20, 40));
      final trimmed = rectOf(tester, TimelapseTrimStrip.framesKey);

      expect(
        trimmed,
        full,
        reason:
            'frames are the timeline — the range dims them, does not recompute',
      );
    });

    testWidgets('the handle does not cover the footage that remains', (
      tester,
    ) async {
      // A handle may sit over the dimmed part — that's cut away anyway.
      // It must not encroach on the frame between dimmed sections, i.e. what
      // remains after saving.
      for (final trim in [
        const RangeValues(0, duration),
        const RangeValues(20, 40),
      ]) {
        await pumpStrip(tester, trim: trim);
        final keptLeft = rectOf(tester, TimelapseTrimStrip.dimStartKey).right;
        final keptRight = rectOf(tester, TimelapseTrimStrip.dimEndKey).left;

        expect(
          rectOf(tester, TimelapseTrimStrip.startHandleKey).right,
          lessThanOrEqualTo(keptLeft + 0.01),
          reason: 'left handle encroaches on kept frame at $trim',
        );
        expect(
          rectOf(tester, TimelapseTrimStrip.endHandleKey).left,
          greaterThanOrEqualTo(keptRight - 0.01),
          reason: 'right handle encroaches on kept frame at $trim',
        );
      }
    });

    testWidgets('scrubbing does not leave the trimmed range', (tester) async {
      final r = await pumpStrip(tester, trim: const RangeValues(20, 40));
      final strip = tester.getRect(find.byType(TimelapseTrimStrip));

      // Tap right at the right edge of the strip, i.e. outside the range (40s).
      await tester.tapAt(Offset(strip.right - 4, strip.center.dy));
      await tester.pumpAndSettle();

      expect(r.seeks.single, 40, reason: 'clamped to range end');
    });
  });

  group('editor screen', () {
    testWidgets('shows source length and computed result for speed', (
      tester,
    ) async {
      await pumpPhone(
        tester,
        const TimelapseEditorScreen(archiveId: 7),
        overrides: [
          timelapseInfoProvider(7).overrideWith((ref) async => _info),
          timelapseFilmstripProvider(7).overrideWith(
            (ref) async => TimelapseFilmstrip(
              frames: [base64Decode(_jpeg)],
              timestamps: const [0],
            ),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('Oryginał: 0:54 w 1920×1080'), findsOneWidget);
      expect(find.text('Wynik: 0:54'), findsOneWidget);

      await tester.tap(find.text('2x'));
      await tester.pumpAndSettle();

      expect(
        find.text('Wynik: 0:27'),
        findsOneWidget,
        reason: '2x skraca 54 s do 27 s',
      );
    });

    testWidgets('without video preview the editor still allows trim and save', (
      tester,
    ) async {
      // There is no preview: the native video_player side does not exist in
      // the test, which is exactly the degradation the screen has to survive.
      await pumpPhone(
        tester,
        const TimelapseEditorScreen(archiveId: 7),
        overrides: [
          timelapseInfoProvider(7).overrideWith((ref) async => _info),
          timelapseFilmstripProvider(7).overrideWith(
            (ref) async => const TimelapseFilmstrip(frames: [], timestamps: []),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.byType(TimelapseTrimStrip), findsOneWidget);
      expect(find.text('Zapisz'), findsOneWidget);
    });

    testWidgets('failed info leaves the screen with a retry, not a spinner', (
      tester,
    ) async {
      await pumpPhone(
        tester,
        const TimelapseEditorScreen(archiveId: 7),
        overrides: [
          timelapseInfoProvider(
            7,
          ).overrideWith((ref) async => throw Exception('boom')),
          timelapseFilmstripProvider(7).overrideWith(
            (ref) async => const TimelapseFilmstrip(frames: [], timestamps: []),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.text('Spróbuj ponownie'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
