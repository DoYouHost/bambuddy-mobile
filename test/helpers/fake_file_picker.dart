import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A system file picker that answers what the test set.
class FakeFilePicker extends FilePicker {
  /// Null is a cancelled dialog.
  PlatformFile? answer;
  bool fails = false;
  Completer<void>? gate;
  int opened = 0;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    opened++;
    await gate?.future;
    if (fails) throw PlatformException(code: 'boom');
    final file = answer;
    return file == null ? null : FilePickerResult([file]);
  }
}

/// The row reads the file with real I/O, which fake time never completes.
Future<void> settleDisk(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}
