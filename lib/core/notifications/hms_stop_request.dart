import 'dart:async';

/// A "Stop printing" the user tapped on an HMS notification, waiting for the UI
/// to confirm it.
///
/// Every other remediation action runs where it was tapped. This one abandons a
/// print that may have hours in it, so the notification only brings the app up
/// (`NotificationAction.opensApp`) and the request parks here until the app
/// shell can ask. Two ways in, because Android has two: a tap while the app
/// runs arrives on [hmsStopRequests], a tap that launched it is waiting in the
/// plugin's launch details and lands in [pendingHmsStop].
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

final StreamController<HmsStopRequest> _controller =
    StreamController<HmsStopRequest>.broadcast();

Stream<HmsStopRequest> get hmsStopRequests => _controller.stream;

/// Held for a shell that is not listening yet — a cold start reaches the
/// notification callback before the first frame. Read it with [takeHmsStop],
/// which clears it, so the dialog cannot appear twice for one tap.
HmsStopRequest? _pending;

void postHmsStopRequest(HmsStopRequest request) {
  _pending = request;
  _controller.add(request);
}

HmsStopRequest? takeHmsStop() {
  final request = _pending;
  _pending = null;
  return request;
}
