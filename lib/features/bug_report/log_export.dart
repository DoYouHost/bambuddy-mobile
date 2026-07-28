/// Getting the log out of the app, which means a file and only a file.
///
/// **There is deliberately no "copy to clipboard".** A clip travels to the
/// system server in a Binder transaction whose buffer is one megabyte for the
/// whole process, and text is parcelled as UTF-16, so a character costs two
/// bytes on the way; past that `setPrimaryClip` throws
/// `TransactionTooLargeException`, on some devices taking the app with it. The
/// buffer turned out to be the lesser problem: every clipboard listener on the
/// phone — the keyboard's clip history first among them — reads what was
/// copied, so a log of a few hundred kilobytes janks the whole device long
/// before that ceiling (measured on a real phone), and then lives on in another
/// app's history. A session recorded for thirty minutes is far past both.
///
/// Someone who only wants a fragment can still select it in the raw log on the
/// review screen. That hands the system a paragraph instead of the session.
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LogSaveResult { saved, cancelled, failed }

typedef LogFileSaver = Future<LogSaveResult> Function({
  required String fileName,
  required String log,
  String? dialogTitle,
});

/// The system "save as" dialog, behind a provider so tests can answer for it —
/// the picker is a platform channel with no test double.
final logFileSaverProvider = Provider<LogFileSaver>((_) => saveLogFile);

@visibleForTesting
Future<LogSaveResult> saveLogFile({
  required String fileName,
  required String log,
  String? dialogTitle,
}) async {
  try {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(log)),
    );
    // Null is the user backing out of the picker, which is not a failure.
    return path == null ? LogSaveResult.cancelled : LogSaveResult.saved;
  } on Exception {
    return LogSaveResult.failed;
  }
}

/// `bambuddy-log-20260728-143005.txt`, in local time — the time the user saved
/// it is the one they can match against "it broke around two".
///
/// `.txt` although the content is JSONL: the file exists to be attached to an
/// issue, and trackers accept a plain text file while rejecting an extension
/// they do not know. Seconds are in the name so two saves of one session do not
/// land on the same file.
String logFileName(DateTime at) {
  String two(int value) => value.toString().padLeft(2, '0');
  return 'bambuddy-log-${at.year}${two(at.month)}${two(at.day)}'
      '-${two(at.hour)}${two(at.minute)}${two(at.second)}.txt';
}
