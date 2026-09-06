import 'package:bambuddy_mobile/core/api/action_outcome.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:bambuddy_mobile/features/queue/queue_removal.dart';
import 'package:bambuddy_mobile/l10n/app_localizations_en.dart';
import 'package:bambuddy_mobile/l10n/app_localizations_pl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = AppLocalizationsEn();

  group('queueRemovalFor', () {
    test('a waiting item is cancelled', () {
      for (final status in [
        QueueItemStatusKind.pending,
        QueueItemStatusKind.scheduled,
      ]) {
        expect(
          queueRemovalFor(status, printerBusy: false),
          QueueRemoval.cancel,
          reason: '$status has not started; /cancel is its route',
        );
        expect(
          queueRemovalFor(status, printerBusy: true),
          QueueRemoval.cancel,
          reason: 'a busy printer says nothing about a row still waiting',
        );
      }
    });

    test('a printing item on a busy printer stops the print', () {
      expect(
        queueRemovalFor(QueueItemStatusKind.printing, printerBusy: true),
        QueueRemoval.stopPrint,
      );
    });

    test('a printing item on an idle printer is a removal, not a stop', () {
      // Issue #35: the print had failed on the machine while its row stayed
      // `printing`. There is nothing left to abort, so offering "stop the
      // print" is what made the reporter think the app had no way out.
      expect(
        queueRemovalFor(QueueItemStatusKind.printing, printerBusy: false),
        QueueRemoval.stopAbandoned,
      );
    });

    test('a paused item follows the printing item', () {
      // The server has no `paused` status of its own — it keeps such a job
      // `printing` — so the model's tolerance for one must not fall through to
      // the branch that deletes.
      expect(
        queueRemovalFor(QueueItemStatusKind.paused, printerBusy: true),
        QueueRemoval.stopPrint,
      );
      expect(
        queueRemovalFor(QueueItemStatusKind.paused, printerBusy: false),
        QueueRemoval.stopAbandoned,
      );
    });

    test('every terminal and unrecognized status is deleted', () {
      // `DELETE` is refused for `printing` alone, so it is the correct route
      // for all of these — including `skipped`, which the server sets and the
      // app's model has no case for.
      for (final status in [
        QueueItemStatusKind.completed,
        QueueItemStatusKind.cancelled,
        QueueItemStatusKind.failed,
        QueueItemStatusKind.unknown,
      ]) {
        expect(
          queueRemovalFor(status, printerBusy: false),
          QueueRemoval.delete,
          reason: '$status leaves the queue by DELETE',
        );
      }
    });

    test('no status is left without a route out of the queue', () {
      // The whole of #35 in one assertion: before this, one status had no
      // working action at all.
      for (final status in QueueItemStatusKind.values) {
        for (final busy in [true, false]) {
          expect(
            () => queueRemovalFor(status, printerBusy: busy),
            returnsNormally,
          );
        }
      }
    });
  });

  group('queueWriteMessage', () {
    test('a success says nothing', () {
      expect(queueWriteMessage(en, ActionOutcome.ok), isNull);
    });

    test('each route\'s refusal reads as the row having moved on', () {
      // Three routes, three wordings, one thing the user has to do.
      const details = [
        "Cannot cancel item with status 'printing'",
        "Can only stop items that are printing, current status: 'pending'",
        'Cannot delete item that is currently printing',
      ];
      for (final detail in details) {
        expect(
          queueWriteMessage(en, _refused(detail, 400)),
          en.queueRemovalStatusChanged,
          reason: detail,
        );
      }
    });

    test('the refusal is translated, not quoted in English', () {
      expect(
        queueWriteMessage(
          AppLocalizationsPl(),
          _refused("Cannot cancel item with status 'printing'", 400),
        ),
        AppLocalizationsPl().queueRemovalStatusChanged,
      );
    });

    test('a refusal worded differently is quoted rather than dropped', () {
      // A phrasing we do not know yet still beats "server returned error 400",
      // which is all the reporter's screen could say.
      expect(
        queueWriteMessage(en, _refused('Budget reservation is locked', 400)),
        'Budget reservation is locked',
      );
    });

    test('a refusal with no detail falls back to the code', () {
      expect(
        queueWriteMessage(en, _refused(null, 400)),
        en.errBadResponse(400),
      );
    });

    test('a permission refusal keeps its own wording', () {
      // 403 is not a removal rule; it must not be flattened into "refresh the
      // queue", which would send the user to retry something that cannot work.
      final message = queueWriteMessage(
        en,
        ActionOutcome.failed(
          const ApiException(
            AppErrorCode.forbidden,
            statusCode: 403,
            detail: 'You can only cancel your own queue items',
          ),
        ),
      );
      expect(message, contains('your own queue items'));
      expect(message, isNot(en.queueRemovalStatusChanged));
    });
  });
}

ActionOutcome _refused(String? detail, int status) => ActionOutcome.failed(
  ApiException(AppErrorCode.badResponse, statusCode: status, detail: detail),
);
