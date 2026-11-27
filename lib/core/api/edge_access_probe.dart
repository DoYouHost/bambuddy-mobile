import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:dio/dio.dart';

import 'api_exceptions.dart';
import 'edge_access.dart';
import 'tls_overrides.dart';

/// Whether [uri] is on a Cloudflare Access team domain, where its sign-in page
/// lives.
bool isCloudflareSignIn(Uri uri) =>
    uri.host.toLowerCase().endsWith('.cloudflareaccess.com');

/// Told when Cloudflare stops accepting the credential the app presented: a
/// browser session that ended or was revoked, or a service token that expired or
/// was (#72). A static hook, like the credential itself in `useTls`: the probe
/// sits in a Dio that is built in every isolate, and each isolate that can tell
/// the user sets its own listener.
class EdgeSessionSignal {
  const EdgeSessionSignal._();

  /// Called with the host and whether it was a service token, from whichever
  /// request noticed. More than once for the same ending: the listener decides
  /// what to do about a repeat.
  static void Function(String host, bool token)? listener;

  static void ended(String host, {bool token = false}) =>
      listener?.call(host, token);

  /// Called with the host when a request that carried the credential in force got
  /// a real answer, so Cloudflare accepted it: whatever was recorded against it
  /// was a passing refusal (a policy being edited, a rule that missed for a
  /// moment). Called for every such request, so a listener must be cheap.
  static void Function(String host)? acceptedListener;

  static void accepted(String host) => acceptedListener?.call(host);
}

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
  static const _sentWith = 'edgeAccessSentWith';

  /// What the app presented when the request left, kept for when it comes back:
  /// the credential can be replaced in between (signing in again, another isolate
  /// adopting a new one), and a refusal of the old one must not be held against
  /// the new.
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_sentWith] = presentedEdgeAccess();
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final error = _signInError(response);
    if (error == null) {
      _noteAccepted(response);
      return handler.next(response);
    }
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
    if (error == null) {
      // An error status from the server is still an answer Cloudflare let through.
      if (response != null) _noteAccepted(response);
      return handler.next(err);
    }
    // A 401 from Cloudflare is not bambuddy's and must not start a re-login
    // against bambuddy: the new error has no response, so `AuthInterceptor`
    // finds no 401 to act on.
    handler.next(error);
  }

  /// The request carried the credential in force for its host and came back as
  /// something other than the sign-in page.
  void _noteAccepted(Response<dynamic> response) {
    final options = response.requestOptions;
    if (!options.extra.containsKey(_sentWith)) return;
    // A redirect says where to go, not that Cloudflare accepted the request: it
    // may be a sign-in of someone else's.
    final status = response.statusCode ?? 0;
    if (status >= 300 && status < 400) return;
    final sent = options.extra[_sentWith] as EdgeAccess?;
    if (sent == null || !sent.appliesTo(options.uri)) return;
    if (sent == presentedEdgeAccess()) EdgeSessionSignal.accepted(sent.host);
  }

  DioException? _signInError(Response<dynamic> response) {
    final sender = _sender(response);
    if (sender == null) return null;
    final options = response.requestOptions;
    final presented = options.extra.containsKey(_sentWith)
        ? options.extra[_sentWith] as EdgeAccess?
        : presentedEdgeAccess();
    final rejected = presented != null && presented.appliesTo(sender);
    // Told only while it is still the credential in force.
    if (rejected && presented == presentedEdgeAccess()) {
      EdgeSessionSignal.ended(
        sender.host.toLowerCase(),
        token: presented is ServiceToken,
      );
    }
    return DioException(
      requestOptions: options,
      error: EdgeAccessException(
        // Whether the credential was sent depends on the hop that went to
        // Cloudflare, scheme included: it is not sent over plain http.
        rejected
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
