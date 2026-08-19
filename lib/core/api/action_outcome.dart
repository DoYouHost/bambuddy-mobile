import 'action_failure.dart';
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

  /// Records the failure as one the user is about to be told about, then
  /// carries it out to the widget that can word it. [action] is the control
  /// they touched, in the `logTag` vocabulary.
  ///
  /// The recording itself is [recordActionFailure], shared with the screens
  /// that snack on the spot and never build an outcome.
  factory ActionOutcome.failed(AppApiException error, {String? action}) {
    recordActionFailure(error, action: action);
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
