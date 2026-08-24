import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// The system file dialogs — choosing a file to send up, saving a small one
/// down — in one place.
///
/// Every caller needs the same three answers apart: it happened, the user backed
/// out, or the platform refused. Backing out is silent and a refusal is worth
/// a message, so a helper that returns only `null` forces each screen to keep
/// its own `try`/`catch` around the picker to tell them apart — which is how
/// four screens ended up with four copies of the same eight lines.
/// [DeviceFileOutcome] is that distinction, made once.
///
/// **Saving is for small files only.** On Android the save dialog cannot take a
/// path or a stream, only bytes (`file_picker`'s `saveFile` refuses without
/// them), so everything handed to it sits in memory first. Anything that can
/// run to hundreds of megabytes — a printer's file, a timelapse — goes through
/// `file_export.dart` instead, which streams it to disk and hands the file to
/// the share sheet.
enum DeviceFileOutcome {
  /// The user chose a file, or the file was written.
  done,

  /// The user backed out of the dialog. Not a failure; say nothing.
  cancelled,

  /// The platform refused or threw. Worth telling the user about.
  failed,
}

/// A file the user picked: always a name, a local path when the platform gave
/// one, and the contents when they were asked for.
typedef PickedFile = ({String path, String name, Uint8List? bytes});

/// Result of a pick: the outcome, and the file when there is one.
typedef PickedFileResult = ({DeviceFileOutcome outcome, PickedFile? file});

/// Result of a save: the outcome, and where it landed when it did.
typedef SavedFileResult = ({DeviceFileOutcome outcome, String? path});

/// Opens the system file picker for a single file.
///
/// [allowedExtensions] narrows what the dialog offers. [withData] also reads the
/// contents, for a caller that parses the file rather than uploading it — an
/// upload wants the path, so it does not pay for the copy.
Future<PickedFileResult> pickFileFromDevice({
  List<String>? allowedExtensions,
  bool withData = false,
}) async {
  final FilePickerResult? picked;
  try {
    picked = await FilePicker.platform.pickFiles(
      type: allowedExtensions == null ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions,
      withReadStream: false,
      withData: withData,
    );
  } on Exception {
    return (outcome: DeviceFileOutcome.failed, file: null);
  }
  final file = picked?.files.single;
  if (file == null) return (outcome: DeviceFileOutcome.cancelled, file: null);
  final name = file.name;
  // A picker that hands over neither a path nor the bytes has given the caller
  // nothing to work with, whatever it reported.
  final path = file.path;
  if (path == null && file.bytes == null) {
    return (outcome: DeviceFileOutcome.cancelled, file: null);
  }
  return (
    outcome: DeviceFileOutcome.done,
    file: (path: path ?? '', name: name, bytes: file.bytes),
  );
}

/// Saves [bytes] wherever the user points the system dialog.
///
/// Small files only — see the note on [DeviceFileOutcome].
Future<SavedFileResult> saveBytesToDevice({
  required String fileName,
  required Uint8List bytes,
  String? dialogTitle,
}) async {
  try {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      bytes: bytes,
    );
    return path == null
        ? (outcome: DeviceFileOutcome.cancelled, path: null)
        : (outcome: DeviceFileOutcome.done, path: path);
  } on Exception {
    return (outcome: DeviceFileOutcome.failed, path: null);
  }
}
