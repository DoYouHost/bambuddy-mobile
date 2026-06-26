import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// A picked file with a usable local path and display name.
typedef PickedFile = ({String path, String name});

/// Open the system file picker and return the chosen file, or null if the user
/// cancelled (or the platform returned no local path). Mirrors the picker usage
/// in the file manager.
Future<PickedFile?> pickSingleFile({
  List<String>? allowedExtensions,
}) async {
  final FilePickerResult? picked;
  try {
    picked = await FilePicker.platform.pickFiles(
      withReadStream: false,
      type: allowedExtensions == null ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions,
    );
  } on Exception {
    return null;
  }
  final file = picked?.files.single;
  final path = file?.path;
  final name = file?.name;
  if (path == null || name == null) return null;
  return (path: path, name: name);
}

/// Save [bytes] to a user-chosen location. Returns the saved path, or null on
/// cancel/failure. Same idiom as the swatch export.
Future<String?> saveBytesToFile({
  required String fileName,
  required Uint8List bytes,
  String? dialogTitle,
}) async {
  try {
    return await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      bytes: bytes,
    );
  } on Exception {
    return null;
  }
}
