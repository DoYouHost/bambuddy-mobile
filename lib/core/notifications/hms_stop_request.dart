import 'launch_relay.dart';

/// A "Stop printing" the user tapped on an HMS notification, waiting for the UI
/// to confirm it.
///
/// Every other remediation action runs where it was tapped. This one abandons a
/// print that may have hours in it, so the notification only brings the app up
/// (`NotificationAction.opensApp`) and the request parks here until the app
/// shell can ask, through [hmsStopRequests].
class HmsStopRequest {
  const HmsStopRequest({
    required this.printerId,
    required this.fullCode,
    this.jobId,
  });

  final int printerId;
  final String fullCode;
  final String? jobId;
}

/// Where the notification parks a stop for the shell to confirm.
final hmsStopRequests = LaunchRelay<HmsStopRequest>();
