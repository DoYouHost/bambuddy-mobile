import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart' show appFlavor;
import 'package:package_info_plus/package_info_plus.dart';

import '../auth/credentials_store.dart';
import '../settings/server_profile.dart';
import 'log_event.dart';

/// Everything the recorder needs to describe a session, plus the exact secrets
/// it must never let through. Gathered once when recording starts — package
/// info and secure storage are both async, and neither changes mid-session.
class SessionFacts {
  const SessionFacts({
    required this.app,
    required this.flavor,
    this.os,
    this.device,
    this.locale,
    this.server,
    this.serverUrl,
    this.auth,
    this.secrets = const {},
  });

  final String app;
  final String flavor;
  final String? os;

  /// Device model. Left empty for now: it needs a `device_info_plus`
  /// dependency, which is a call worth making deliberately rather than as a
  /// side effect of building the logger.
  final String? device;

  final String? locale;

  /// bambuddy version, as the server reports it at `/updates/version`. Empty
  /// when the server could not be reached or answered something unparseable —
  /// which is itself worth seeing in a report.
  final String? server;

  final ServerFingerprint? serverUrl;
  final String? auth;

  /// Exact value → redaction label, handed to the session's redactor.
  final Map<String, String> secrets;

  LogHeader toHeader({
    required DateTime ts,
    required String session,
    LogStream stream = LogStream.ui,
  }) =>
      LogHeader(
        ts: ts,
        session: session,
        app: app,
        flavor: flavor,
        stream: stream,
        os: os,
        device: device,
        locale: locale,
        server: server,
        serverUrl: serverUrl,
        auth: auth,
      );
}

/// The exact values a session's redactor must never let through.
///
/// Split out of [loadSessionFacts] for the background isolates: they inherit the
/// UI stream's header off disk, so they need none of the facts — but they do need
/// these, and with an empty redactor the first records they write are the ones
/// that carry secrets. A `SocketException` reads "Failed host lookup:
/// 'nas.example'", which is not a URL, so only an exact value catches it.
///
/// Deliberately without `PackageInfo`: this runs before the foreground service
/// dials its socket, and one platform channel is one more thing that can hang or
/// throw on the path to monitoring being live.
Future<Map<String, String>> sessionSecrets({
  required ServerProfile? profile,
  required CredentialsStore credentials,
}) async {
  final secrets = <String, String>{};

  // Registered as exact values so they are cut even when they surface inside
  // a message we did not format, e.g. a server error echoing the key back.
  final apiKey = await _quietly(credentials.readApiKey);
  final jwt = await _quietly(credentials.readJwt);
  if (apiKey != null) secrets[apiKey] = '[APIKEY]';
  if (jwt != null) secrets[jwt] = '[JWT]';

  final host = profile == null ? null : Uri.tryParse(profile.baseUrl)?.host;
  if (host != null && host.isNotEmpty) secrets[host] = '[HOST]';

  return secrets;
}

/// Reads the real facts off the device and the stored profile.
///
/// [readServerVersion] is awaited for the header's `server` field. It is a
/// callback rather than a value because the version comes off the network, and
/// the header is written once at the top of the log where it is most useful:
/// which server build produced the behaviour below is the first question every
/// report raises, and the queue-enum diagnosis
/// (`docs/plans/07-queue-cali-enum.md`) cost a day for want of exactly this line.
/// A failure to read it is swallowed — a recording must start regardless.
Future<SessionFacts> loadSessionFacts({
  required ServerProfile? profile,
  required CredentialsStore credentials,
  Future<String?> Function()? readServerVersion,
}) async {
  final info = await PackageInfo.fromPlatform();
  final secrets =
      await sessionSecrets(profile: profile, credentials: credentials);

  return SessionFacts(
    app: '${info.version}+${info.buildNumber}',
    flavor: appFlavor ?? 'mobile',
    os: Platform.operatingSystemVersion,
    locale: PlatformDispatcher.instance.locale.toLanguageTag(),
    server:
        readServerVersion == null ? null : await _quietly(readServerVersion),
    serverUrl: ServerFingerprint.tryParse(profile?.baseUrl),
    auth: profile?.authMode.name,
    secrets: secrets,
  );
}

/// Secure storage can throw on a wiped keystore; a missing secret must not
/// stop a recording from starting.
Future<String?> _quietly(Future<String?> Function() read) async {
  try {
    return await read();
  } on Object {
    return null;
  }
}
