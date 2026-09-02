import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/features/common/plate_clear.dart';
import 'package:flutter_test/flutter_test.dart';

/// The route answers 400 for two unrelated reasons, so the text is the whole
/// signal — see [isOfflinePlateClearRefusal].
ApiException _refusal(String detail) => ApiException(
      AppErrorCode.badResponse,
      statusCode: 400,
      detail: detail,
    );

void main() {
  group('isOfflinePlateClearRefusal', () {
    test('the pre-#2864 server insisting on reaching the printer', () {
      expect(isOfflinePlateClearRefusal(_refusal('Printer not connected')),
          isTrue);
    });

    test('the current server saying no gate is up is a different answer', () {
      // Same status, opposite meaning: nothing to acknowledge on this printer.
      expect(
        isOfflinePlateClearRefusal(_refusal(
            'Printer is not awaiting plate-clear acknowledgment (state=IDLE)')),
        isFalse,
      );
    });

    test('a 400 with no wording at all is not read as the refusal', () {
      // What the plain mapper produces when the body carries no `detail`.
      expect(
        isOfflinePlateClearRefusal(
            const ApiException(AppErrorCode.badResponse, statusCode: 400)),
        isFalse,
      );
    });

    test('a missing permission is not the refusal', () {
      expect(
        isOfflinePlateClearRefusal(const AuthException(
          AppErrorCode.forbidden,
          detail: "API key does not have 'printers:clear_plate' permission",
        )),
        isFalse,
      );
    });
  });
}
