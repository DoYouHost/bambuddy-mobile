import 'package:app_diagnostics/app_diagnostics.dart';
import 'api_exceptions.dart';

/// Records a failure the user was meant to be told about.
///
/// `http` logs every error response, but nothing there separates a refusal that
/// stopped somebody from one a screen absorbed. Here rather than inside
/// `ActionOutcome.failed` because attached to that factory it marked "a notifier
/// used the outcome type", which three quarters of our error handling does not.
/// Both doors and the field list: `docs/diagnostics-log.md`.
///
/// [action] is the control the user touched, in the `logTag` vocabulary;
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
      // Reduced here, not only where it was captured: `path` is a plain field,
      // so an exception built by hand could otherwise put anything in an upload.
      'path': error.path == null ? null : loggablePath(error.path!),
      'code': error.code.name,
      'status': error.statusCode,
      // What makes a 403 actionable. In the `http` body too, but only as a blob
      // that clipping can take the end off.
      'reason': error.detail,
      // Written only in the negative, like `http`'s `empty`: the ordinary row
      // is the one that reached somebody, and it stays short.
      'shown': shown ? null : false,
    },
  );
}
