import 'package:bambuddy_mobile/features/common/device_files.dart';
import 'package:bambuddy_mobile/features/projects/project_common.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers.dart';
import '../../helpers/fake_file_picker.dart';

void main() {
  late FakeFilePicker picker;

  setUp(() {
    picker = FakeFilePicker();
    FilePicker.platform = picker;
  });

  /// Runs [pickProjectFile] from a screen and hands back what it returned.
  Future<PickedFile?> pick(WidgetTester tester) async {
    PickedFile? out;
    await tester.pumpWidget(
      plApp(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => out = await pickProjectFile(
                ScaffoldMessenger.of(context),
                pl,
              ),
              child: const Text('pick'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    return out;
  }

  testWidgets('a refused picker says so and gives nothing', (tester) async {
    picker.fails = true;
    expect(await pick(tester), isNull);
    expect(find.text(pl.filePickerFailed), findsOneWidget);
  });

  testWidgets('backing out is silent', (tester) async {
    expect(await pick(tester), isNull);
    expect(find.text(pl.filePickerFailed), findsNothing);
  });

  testWidgets('a chosen file comes back', (tester) async {
    picker.answer = PlatformFile(
      name: 'part.3mf',
      size: 3,
      path: '/x/part.3mf',
    );
    final file = await pick(tester);
    expect((file?.name, file?.path), ('part.3mf', '/x/part.3mf'));
    expect(find.text(pl.filePickerFailed), findsNothing);
  });
}
