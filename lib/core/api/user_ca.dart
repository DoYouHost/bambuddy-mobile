import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Written by `UserCaExport.kt` into the app's files directory.
const userCaFileName = 'user_ca.pem';

Future<void>? _trusted;

/// Makes `dart:io` trust the CAs the user installed in Android's Settings.
///
/// Dart's TLS trusts only the system store, so without this a server behind a
/// home CA fails every handshake. `SecurityContext.defaultContext` belongs to
/// one isolate: every entry point that opens a connection awaits this first.
/// Once per isolate: the notification handlers also run in the UI isolate,
/// and there is no need to read the file again.
Future<void> trustUserCas() => _trusted ??= _trust();

Future<void> _trust() async {
  if (!Platform.isAndroid) return;
  await trustCasFrom(await getApplicationSupportDirectory());
}

/// Adds the certificates in [dir]'s export to [context]. A missing file means
/// no user CAs; an unreadable or corrupt one is skipped, so the connection
/// fails its handshake rather than the app failing to start.
Future<void> trustCasFrom(Directory dir, [SecurityContext? context]) async {
  final file = File('${dir.path}/$userCaFileName');
  try {
    (context ?? SecurityContext.defaultContext).setTrustedCertificatesBytes(
      await file.readAsBytes(),
    );
  } on FileSystemException {
    return;
  } on TlsException {
    return;
  }
}
