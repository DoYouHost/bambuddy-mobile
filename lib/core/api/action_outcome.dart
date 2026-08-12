import '../diagnostics/diagnostic_recorder.dart';
import '../diagnostics/log_event.dart';
import 'api_exceptions.dart';

/// What a notifier hands back after running an action on the user's behalf.
///
/// Notifiers hold no `BuildContext`, so the sentence the user reads cannot be
/// built where the failure is caught. Four features each solved that with their
/// own `enum { ok, forbidden, error }` and their own translation back into
/// wording, and all four dropped what the server said on the way: a refusal
/// naming the missing permission reached the screen as "not allowed".
///
/// So the failure travels intact, and `ActionOutcomeL10n.messageFor` is the only
/// place that turns it into text. A feature decides *whether* to show it, never
/// *what it says*.
sealed class ActionOutcome {
  const ActionOutcome();

  /// Records the failure as one the user is about to be told about. `http` logs
  /// every error response, but nothing there separates a refusal that stopped
  /// somebody from one a screen absorbed. [action] is the control they touched,
  /// in the `logTag` vocabulary.
  factory ActionOutcome.failed(AppApiException error, {String? action}) {
    DiagnosticRecorder.active?.add(
      LogSource.app,
      'action_failed',
      lvl: LogLevel.warn,
      fields: {
        'action': action,
        'code': error.code.name,
        'status': error.statusCode,
        // What makes a 403 actionable. In the `http` record's body too, but
        // only as an unparsed blob that clipping can take the end off.
        'reason': error.detail,
      },
    );
    return ActionFailed(error);
  }

  static const ok = ActionOk._();

  bool get isOk => this is ActionOk;

  /// Screens that *hide* a control rather than complain about it — smart plugs,
  /// AMS drying — branch on this, so it stays a question about the failure and
  /// never a string comparison.
  bool get isForbidden =>
      this is ActionFailed &&
      (this as ActionFailed).error.code == AppErrorCode.forbidden;
}

final class ActionOk extends ActionOutcome {
  const ActionOk._();
}

final class ActionFailed extends ActionOutcome {
  const ActionFailed(this.error);

  final AppApiException error;
}
