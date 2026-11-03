import 'package:bambuddy_mobile/core/api/action_outcome.dart';
import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/features/admin/user_messages.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  ActionOutcome refused(String? detail) => ActionOutcome.failed(
    ApiException(AppErrorCode.badResponse, statusCode: 400, detail: detail),
  );

  test('a success says the ok text', () {
    expect(userWriteText(en, ActionOutcome.ok, en.usersSaved), en.usersSaved);
  });

  test('an empty ok text is passed through on success', () {
    expect(userWriteText(en, ActionOutcome.ok, ''), '');
  });

  test('a recognised refusal says its own sentence, not the ok text', () {
    expect(
      userWriteText(en, refused('Username already exists'), en.usersSaved),
      en.usersErrUsernameTaken,
    );
  });

  test('a refusal without detail reads as userWriteMessage does', () {
    final outcome = refused(null);
    expect(
      userWriteText(en, outcome, en.usersSaved),
      userWriteMessage(en, outcome),
    );
    expect(userWriteText(en, outcome, en.usersSaved), isNot(en.usersSaved));
  });
}
