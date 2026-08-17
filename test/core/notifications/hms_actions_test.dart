import 'package:bambuddy_mobile/core/notifications/background_api.dart';
import 'package:bambuddy_mobile/core/notifications/hms_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hmsRenderableActions', () {
    test('keeps the actions the server turns into a command', () {
      expect(
        hmsRenderableActions(['RESUME_PRINTING', 'STOP_PRINTING']),
        ['RESUME_PRINTING', 'STOP_PRINTING'],
      );
    });

    test('drops the ones the printer\'s own screen owns', () {
      // Every one of these reaches `case … pass` on the server: the publish
      // never happens, so a button for it would do nothing at all.
      expect(
        hmsRenderableActions([
          'CHECK_ASSISTANT',
          'JUMP_TO_LIVEVIEW',
          'OK_JUMP_RACK',
          'REMOVE_CLOSE_BTN',
          'LOAD_VIRTUAL_TRAY',
          'CANCLE',
          'DBL_CHECK_CANCEL',
        ]),
        isEmpty,
      );
    });

    test('drops a key no version of the server knows', () {
      // The firmware catalog grows without asking us; an unknown key would come
      // back as 400 rather than as an action.
      expect(hmsRenderableActions(['FEED_THE_CAT', '', 'RESUME_PRINTING']),
          ['RESUME_PRINTING']);
    });

    test('keeps the server\'s order and shows each button once', () {
      expect(
        hmsRenderableActions(
            ['STOP_PRINTING', 'RESUME_PRINTING', 'STOP_PRINTING']),
        ['STOP_PRINTING', 'RESUME_PRINTING'],
      );
    });
  });

  group('notification payload', () {
    test('round-trips the fault a button applies to', () {
      final parsed = parseHmsPayload(
          hmsPayload(printerId: 7, fullCode: '03008004', jobId: '746795586'));
      expect(parsed?.printerId, 7);
      expect(parsed?.fullCode, '03008004');
      expect(parsed?.jobId, '746795586');
    });

    test('an idle-state fault travels without a job id', () {
      final parsed =
          parseHmsPayload(hmsPayload(printerId: 7, fullCode: '03008004'));
      expect(parsed?.jobId, isNull);
    });

    test('anything else is not an HMS payload', () {
      // 'printer:1' is what every other alert carries, and a notification from
      // an older build of the app may still be sitting in the shade.
      for (final payload in [null, '', 'printer:1', 'hms:1:03008004', 'hms:x::']) {
        expect(parseHmsPayload(payload), isNull, reason: 'payload: $payload');
      }
    });
  });
}
