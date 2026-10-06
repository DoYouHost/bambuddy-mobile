import 'package:bambuddy_mobile/core/models/current_user.dart';
import 'package:bambuddy_mobile/core/models/library_folder.dart';
import 'package:bambuddy_mobile/features/projects/project_detail_sections.dart';
import 'package:bambuddy_mobile/features/projects/projects_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Linking a folder to a project, and unlinking it, is a folder update the
/// server takes from `library:update_all` alone (`library.py::update_folder`).
void main() {
  Future<void> pump(WidgetTester tester, Set<String> permissions) async {
    await pumpPhone(
      tester,
      const Scaffold(
        body: SingleChildScrollView(child: ProjectFilesSection(projectId: 1)),
      ),
      overrides: [
        noServerProfileOverride,
        currentUserOverride(
          CurrentUser(
            id: 3,
            username: 'u',
            isAdmin: false,
            permissions: permissions,
          ),
        ),
        projectFoldersProvider.overrideWith(
          (ref, id) async => const [LibraryFolder(id: 5, name: 'Parts')],
        ),
        projectFilesProvider.overrideWith((ref, id) async => const []),
      ],
    );
    await tester.pumpAndSettle();
  }

  testWidgets('update-all may link and unlink', (tester) async {
    await pump(tester, {Permissions.libraryUpdateAll});
    expect(byLogId('project.section_action'), findsOneWidget);
    expect(byLogId('project.unlink_folder'), findsOneWidget);
  });

  testWidgets('anyone else is offered neither', (tester) async {
    await pump(tester, {'library:update_own'});
    expect(find.text('Parts'), findsOneWidget);
    expect(byLogId('project.section_action'), findsNothing);
    expect(byLogId('project.unlink_folder'), findsNothing);
  });
}
