import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Replaces test/flutter_test_config.dart for this directory, without its
/// `TestWidgetsFlutterBinding`: that binding answers every HTTP request with a
/// 400, and these tests talk to a real server.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  WidgetController.hitTestWarningShouldBeFatal = true;
  await testMain();
}
