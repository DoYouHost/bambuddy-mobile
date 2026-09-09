import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:app_diagnostics/app_diagnostics.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:package_info_plus/package_info_plus.dart';

import '../auth/credentials_store.dart';
import '../settings/server_profile.dart';

/// The exact values a session's redactor must never let through.
///
/// Split out of [loadSessionFacts] for the background isolates, which inherit
/// the UI header off disk and so need none of the facts — but with an empty
/// redactor the first records they write are the ones carrying secrets. A
/// `SocketException` reads "Failed host lookup: 'nas.example'", which is not a
/// URL, so only an exact value catches it.
///
/// Deliberately without `PackageInfo`: this runs before the foreground service
/// dials its socket, and one platform channel is one more thing that can hang
/// on the path to monitoring being live.
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
/// [readServerVersion] is a callback rather than a value because the version
/// comes off the network. Which server build produced the behaviour below is
/// the first question every report raises — the queue-enum diagnosis
/// (`docs/plans/07-queue-cali-enum.md`) cost a day for want of this line. A
/// failure to read it is swallowed; a recording must start regardless.
Future<SessionFacts> loadSessionFacts({
  required ServerProfile? profile,
  required CredentialsStore credentials,
  Future<String?> Function()? readServerVersion,
}) async {
  final info = await PackageInfo.fromPlatform();
  final secrets = await sessionSecrets(
    profile: profile,
    credentials: credentials,
  );

  return SessionFacts(
    app: '${info.version}+${info.buildNumber}',
    os: Platform.operatingSystemVersion,
    locale: PlatformDispatcher.instance.locale.toLanguageTag(),
    server: readServerVersion == null
        ? null
        : await _quietly(readServerVersion),
    serverUrl: ServerFingerprint.tryParse(profile?.baseUrl),
    secrets: secrets,
    // bambuddy's own header fields. They stay flat top-level keys on the line,
    // exactly where they have always been; `SessionFacts` simply no longer
    // declares a slot for each app's private half of the header.
    //
    // `auth` is `AuthMode.name` verbatim, camel case included — whatever reads
    // it back has to match that spelling exactly.
    extra: {
      'flavor': appFlavor ?? 'mobile',
      if (profile != null) 'auth': profile.authMode.name,
    },
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
