import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no button of the controller is a bare outline', () {
    // An outlined button is a border and nothing else, which all but vanishes
    // on the controller's dark ground — and disabled, where the jogs sit while
    // a print runs, it is gone. Buttons go through `controllerButtonStyle`.
    final offenders = [
      for (final file in Directory('lib/features/controller').listSync())
        if (file is File && file.path.endsWith('.dart'))
          if (RegExp(
            r'OutlinedButton|IconButton\.outlined',
          ).hasMatch(file.readAsStringSync()))
            file.path,
    ];

    expect(offenders, isEmpty);
  });
}
