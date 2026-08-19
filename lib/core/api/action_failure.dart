import '../diagnostics/diagnostic_recorder.dart';
import '../diagnostics/log_event.dart';
import '../diagnostics/log_path.dart';
import 'api_exceptions.dart';

/// Records a failure the user was meant to be told about.
///
/// `http` logs every error response, but nothing there separates a refusal that
/// stopped somebody from one a screen absorbed. The record belongs to that
/// event, not to either shape of caller, which is why it lives here rather than
/// inside `ActionOutcome.failed`: attached to the factory it marked "a notifier
/// used the outcome type", and three quarters of our error handling never does.
/// Both doors and the field list: `docs/diagnostics-log.md`.
///
/// [action] is the control the user touched, in the `logTag` vocabulary.
/// [shown] is false where the message was built and then not delivered.
void recordActionFailure(
  AppApiException error, {
  String? action,
  bool shown = true,
}) {
  DiagnosticRecorder.active?.add(
    LogSource.app,
    'action_failed',
    lvl: LogLevel.warn,
    fields: {
      'action': action,
      // Which call it was. Reconstructing that from the `http` records around
      // it is guesswork whenever more than one is in flight.
      'method': error.method,
      // Reduced here and not only where it was captured: `path` is a plain
      // field, so a caller building the exception by hand would otherwise put
      // whatever it likes into an upload.
      'path': error.path == null ? null : loggablePath(error.path!),
      'code': error.code.name,
      'status': error.statusCode,
      // What makes a 403 actionable. In the `http` record's body too, but
      // only as an unparsed blob that clipping can take the end off.
      'reason': error.detail,
      // Written only in the negative, like `http`'s `empty`: the ordinary row
      // is the one that reached somebody, and it stays short.
      'shown': shown ? null : false,
    },
  );
}
