import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:dio/dio.dart';

import 'api_exceptions.dart';
import 'tls_overrides.dart';

/// Whether [uri] is on a Cloudflare Access team domain, where its sign-in page
/// lives.
bool isCloudflareSignIn(Uri uri) =>
    uri.host.toLowerCase().endsWith('.cloudflareaccess.com');

/// Turns an answer that was sent to a Cloudflare Access sign-in page into the
/// error it is. Access answers a request it does not accept with a redirect to
/// `<team>.cloudflareaccess.com`. What the app sees depends on who followed it:
/// `dart:io` follows it to a page of HTML (and on to the identity provider when
/// there is only one), while a request that carries a credential is an
/// `EdgeRequest`, which never follows a redirect to another origin and hands
/// back the 302 itself. Without this the page reads as a response that is not
/// bambuddy's (`notBambuddy`), which sends the user to the address when the
/// remedy is a credential.
///
/// A request is sent to sign-in when it did not start on the team domain, went
/// through it (or was told to go there), and did not come back to its own host.
/// The last condition keeps a round trip that ended on the server, which is the
/// server's own answer.
///
/// The error carries no response, on purpose. Callers that ask "did the server
/// answer, and with what status" before they map the error (the probe's
/// confirmation of bambuddy, the two-factor logging) would otherwise read the
/// login page's 200 as bambuddy's own answer.
///
/// Whether the app presented a credential for the host decides between the two
/// codes: none means it needs one, one means Cloudflare did not accept it.
class EdgeAccessProbe extends Interceptor {
  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final error = _signInError(response);
    if (error == null) return handler.next(response);
    // Not through the error interceptors: the probes before this one have
    // already seen this exchange as the answer it was, and would see it again
    // as a failure with no response.
    handler.reject(error);
  }

  /// The sign-in page can come back with any status: Access answers a policy
  /// that denies the visitor with a 403 page of its own.
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    final error = response == null ? null : _signInError(response);
    if (error == null) return handler.next(err);
    // A 401 from Cloudflare is not bambuddy's and must not start a re-login
    // against bambuddy: the new error has no response, so `AuthInterceptor`
    // finds no 401 to act on.
    handler.next(error);
  }

  DioException? _signInError(Response<dynamic> response) {
    final sender = _sender(response);
    if (sender == null) return null;
    final options = response.requestOptions;
    final presented = presentedEdgeAccess();
    return DioException(
      requestOptions: options,
      error: EdgeAccessException(
        // Whether the credential was sent depends on the hop that went to
        // Cloudflare, scheme included: it is not sent over plain http.
        presented != null && presented.appliesTo(sender)
            ? AppErrorCode.edgeAccessRejected
            : AppErrorCode.edgeAccessRequired,
        host: sender.host.toLowerCase(),
        method: options.method,
        path: loggablePath(options.uri.path),
      ),
    );
  }

  /// The place that sent the request to Cloudflare Access, or null when the
  /// request did not end there.
  ///
  /// The journey is walked hop by hop, each location resolved against the one
  /// before it (a redirect may be relative), then, for a 3xx handed over
  /// unfollowed, the place it points to. It counts when it reaches the team
  /// domain, the request did not start there, and it did not end back on the
  /// host that sent it to the team domain: that host answering is its own answer,
  /// whether it is the one the request started on or the canonical one an alias
  /// redirected to first.
  static Uri? _sender(Response<dynamic> response) {
    final start = response.requestOptions.uri;
    if (isCloudflareSignIn(start)) return null;
    final journey = _journey(response);
    final team = journey.indexWhere(isCloudflareSignIn);
    if (team < 1) return null;
    final sender = journey[team - 1];
    if (sender.host.isEmpty) return null;
    return journey.last.host.toLowerCase() == sender.host.toLowerCase()
        ? null
        : sender;
  }

  /// [Response.requestOptions] URI, every redirect it followed, and where an
  /// unfollowed 3xx points, each resolved against the one before. A location
  /// that is not a URI ends the journey there.
  static List<Uri> _journey(Response<dynamic> response) {
    final journey = [response.requestOptions.uri];
    Uri next(String location) => journey.last.resolve(location);
    try {
      for (final hop in response.redirects) {
        journey.add(journey.last.resolveUri(hop.location));
      }
      final status = response.statusCode ?? 0;
      // `Headers.value` throws on a header sent twice; a 3xx that says where
      // to go twice does not say where.
      final locations = response.headers['location'];
      if (status >= 300 && status < 400 && locations?.length == 1) {
        journey.add(next(locations!.first));
      }
    } on FormatException {
      // What was resolved so far is the journey.
    }
    return journey;
  }
}
