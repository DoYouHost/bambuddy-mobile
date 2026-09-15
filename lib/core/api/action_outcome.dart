import 'action_failure.dart';
import 'api_exceptions.dart';

/// What a notifier hands back after running an action on the user's behalf.
///
/// A notifier holds no `BuildContext`, so the sentence cannot be built where the
/// failure is caught — the failure travels intact instead, and
/// `ActionOutcomeL10n.messageFor` is the only place that turns it into text. A
/// feature decides *whether* to show it, never *what it says*.
sealed class ActionOutcome {
  const ActionOutcome();

  /// Records the failure, then carries it out to the widget that can word it.
  /// [action] is the control the user touched, in the `logTag` vocabulary.
  factory ActionOutcome.failed(AppApiException error, {String? action}) {
    recordActionFailure(error, action: action);
    return ActionFailed(error);
  }

  static const ok = ActionOk._();

  bool get isOk => this is ActionOk;

  /// Screens that *hide* a control rather than complain about it branch on
  /// this, so it stays a question about the failure, never a string comparison.
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

/// Runs [action] on the user's behalf and hands back how it went, so a screen
/// never catches the exception itself.
///
/// [logId] is the control the user touched — one tag for a whole notifier would
/// record which screen failed but not what they were trying to do. [onSuccess]
/// is what must happen only when the write landed, and a failure there is the
/// write's failure too: the alternative reports success over a list it could
/// not reload.
Future<ActionOutcome> runAction(
  Future<void> Function() action, {
  required String logId,
  Future<void> Function()? onSuccess,
}) async {
  try {
    await action();
    await onSuccess?.call();
    return ActionOutcome.ok;
  } on AppApiException catch (e) {
    return ActionOutcome.failed(e, action: logId);
  }
}
