import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/library_file.dart';
import 'package:bambuddy_mobile/core/models/library_folder.dart';
import 'package:bambuddy_mobile/core/models/project.dart';
import 'package:bambuddy_mobile/features/projects/project_detail_screen.dart';
import 'package:bambuddy_mobile/features/projects/project_form_screen.dart';
import 'package:bambuddy_mobile/features/projects/projects_providers.dart';
import 'package:bambuddy_mobile/features/projects/projects_screen.dart';
import 'package:bambuddy_mobile/data/library_repository.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers.dart';
import 'a11y_harness.dart';

/// Rendered contrast and touch targets for `lib/features/projects/`: the list
/// (filled, filtered to nothing, failed, both app-bar menus), the create and
/// edit forms (status and parent selects, the date picker, the validation
/// message) and the detail page with each of its sections, sheet, dialogs and
/// menus. Everything runs on the demo backend except the states it never
/// serves (an empty list, a failure, a project with a parent, children,
/// attachments, linked folders and a timeline), which override one provider.
/// Not covered: the system file picker behind "Import", "Upload cover" and
/// "Upload attachment", and the save-file dialog behind "Export" and
/// "Download" — platform UI a widget test cannot render.
void main() {
  a11ySurface(
    'projects list',
    home: () => const ProjectsScreen(),
    shows: find.text('Workshop organizers'),
  );

  // Every status chip: the ones that are not green or blue are drawn in the
  // quiet ink on their own wash.
  a11ySurface(
    'projects list, every status',
    demo: false,
    home: () => const ProjectsScreen(),
    overrides: [
      fakeServerProfileOverride(),
      projectsListProvider.overrideWith(_EveryStatusList.new),
    ],
    shows: find.text('Archived rails'),
  );

  a11ySurface(
    'projects list, filtered to nothing',
    home: () => const ProjectsScreen(),
    overrides: [projectStatusFilterProvider.overrideWith((_) => 'archived')],
    shows: find.text(pl.projectsEmpty),
  );

  a11ySurface(
    'projects list, load failed',
    demo: false,
    home: () => const ProjectsScreen(),
    overrides: [
      fakeServerProfileOverride(),
      projectsListProvider.overrideWith(_FailingList.new),
    ],
    shows: find.text(pl.retry),
  );

  a11ySurface(
    'projects list, status filter menu',
    home: () => const ProjectsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('projects.filter_menu'));
    },
    shows: byLogId('projects.filter_all'),
  );

  a11ySurface(
    'projects list, overflow menu',
    home: () => const ProjectsScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('projects.overflow_menu'));
    },
    shows: byLogId('projects.import'),
  );

  a11ySurface(
    'project form, create',
    home: () => const ProjectFormScreen(),
    shows: find.text(pl.projectCreate),
  );

  a11ySurface(
    'project form, name missing',
    home: () => const ProjectFormScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('project_form.save'));
    },
    shows: find.text(pl.projectNameRequired),
  );

  a11ySurface(
    'project form, edit',
    home: () => ProjectFormScreen(existing: _richProject),
    shows: find.text(pl.projectEdit),
  );

  a11ySurface(
    'project form, status select open',
    home: () => ProjectFormScreen(existing: _richProject),
    arrange: (tester) async {
      await tester.tap(byLogId('project_form.status'));
    },
    shows: byLogId('project_form.status.on_hold'),
  );

  a11ySurface(
    'project form, parent select open',
    home: () => const ProjectFormScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('project_form.parent'));
    },
    shows: byLogId('project_form.parent_none'),
  );

  a11ySurface(
    'project form, due date picker',
    home: () => const ProjectFormScreen(),
    arrange: (tester) async {
      await tester.tap(byLogId('project_form.due_date'));
    },
    shows: find.byType(Dialog),
  );

  a11ySurface(
    'project detail, active',
    home: () => const ProjectDetailScreen(projectId: 1),
    shows: find.text(pl.projectNotes),
  );

  a11ySurface(
    'project detail, completed',
    home: () => const ProjectDetailScreen(projectId: 2),
    shows: find.text(pl.projectStatusCompleted),
  );

  a11ySurface(
    'project detail, load failed',
    demo: false,
    home: () => const ProjectDetailScreen(projectId: 1),
    overrides: [
      fakeServerProfileOverride(),
      projectDetailProvider.overrideWith2(_FailingDetail.new),
    ],
    shows: find.text(pl.retry),
  );

  // A project with everything the header and the sections can carry: parent,
  // children, link, tags, attachments, a linked folder with a printable file,
  // a timeline and a sets target.
  final richOverrides = [
    projectDetailProvider.overrideWith2((arg) => _DetailOf(_richProject, arg)),
    projectFoldersProvider.overrideWith((ref, id) async => _folders),
    projectFilesProvider.overrideWith((ref, id) async => _files),
    projectFileProgressProvider.overrideWith(
      (ref, id) async => const [
        ProjectFileProgress(fileId: 31, completedCount: 3),
      ],
    ),
    projectTimelineProvider.overrideWith((ref, id) async => _timeline),
  ];

  a11ySurface(
    'project detail, every section filled',
    home: () => const ProjectDetailScreen(projectId: 1),
    overrides: richOverrides,
    shows: find.text('Gridfinity'),
  );

  a11ySurface(
    'project detail, linked folder expanded',
    home: () => const ProjectDetailScreen(projectId: 1),
    overrides: richOverrides,
    arrange: (tester) async {
      await a11yTap(tester, byLogId('project.folder'));
    },
    shows: byLogId('project.print_file'),
  );

  a11ySurface(
    'project detail, overflow menu',
    home: () => const ProjectDetailScreen(projectId: 1),
    overrides: richOverrides,
    arrange: (tester) async {
      await tester.tap(byLogId('project.overflow_menu'));
    },
    shows: byLogId('project.export'),
  );

  a11ySurface(
    'project detail, delete confirmation',
    home: () => const ProjectDetailScreen(projectId: 1),
    arrange: (tester) async {
      await tester.tap(byLogId('project.overflow_menu'));
      await tester.pumpAndSettle();
      await tester.tap(byLogId('project.delete'));
    },
    shows: find.text(pl.projectDeleteTitle),
  );

  a11ySurface(
    'project detail, notes dialog',
    home: () => const ProjectDetailScreen(projectId: 1),
    arrange: (tester) async {
      await tester.tap(byLogId('project.edit_notes'));
    },
    shows: byLogId('project_notes.save'),
  );

  a11ySurface(
    'project detail, link folder sheet',
    home: () => const ProjectDetailScreen(projectId: 1),
    arrange: (tester) async {
      await tester.tap(byLogId('project.section_action').first);
    },
    shows: find.text(pl.projectLinkFolder),
  );

  a11ySurface(
    'project detail, link folder sheet, nothing to link',
    home: () => const ProjectDetailScreen(projectId: 1),
    overrides: [libraryRepositoryProvider.overrideWithValue(_NoFolders())],
    arrange: (tester) async {
      await tester.tap(byLogId('project.section_action').first);
    },
    shows: find.text(pl.projectNoFoldersToLink),
  );

  a11ySurface(
    'project detail, bill of materials row menu',
    home: () => const ProjectDetailScreen(projectId: 1),
    arrange: (tester) async {
      await a11yTap(
        tester,
        find.descendant(
          of: byLogId('project.bom_item').first,
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
    },
    shows: byLogId('bom_menu.edit'),
  );

  a11ySurface(
    'project detail, add bill of materials item',
    home: () => const ProjectDetailScreen(projectId: 1),
    arrange: (tester) async {
      // Sections each have a `project.section_action`; the BOM one is the
      // last with the add label.
      await tester.tap(find.text(pl.bomAdd));
    },
    shows: find.text(pl.bomAddTitle),
  );

  a11ySurface(
    'project detail, edit bill of materials item',
    home: () => const ProjectDetailScreen(projectId: 1),
    arrange: (tester) async {
      await a11yTap(
        tester,
        find.descendant(
          of: byLogId('project.bom_item').first,
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(byLogId('bom_menu.edit'));
    },
    shows: find.text(pl.bomEditTitle),
  );
}

final _richProject = ProjectResponse.fromJson({
  'id': 1,
  'name': 'Workshop organizers',
  'description': 'Drawer and wall organizers for the workshop.',
  'color': '#2196F3',
  'status': 'on_hold',
  'priority': 'urgent',
  'target_count': 12,
  'target_parts_count': 40,
  'target_sets': 4,
  'budget': 60.0,
  'tags': 'organization,workshop,gridfinity',
  'notes': 'Match the 25 mm grid on the tool wall.',
  'due_date': '2030-03-14',
  'url': 'https://example.com/workshop',
  'parent_id': 7,
  'parent_name': 'Garage',
  'children': [
    {'id': 8, 'name': 'Drawer bins', 'color': '#4caf50', 'status': 'active'},
    {'id': 9, 'name': 'Wall rails', 'color': '#f44336', 'status': 'planning'},
  ],
  'attachments': ['assembly-notes.pdf', 'grid-layout.png'],
  'cover_image_filename': 'gridfinity-bin.png',
  'created_at': '2030-01-01T10:00:00',
  'updated_at': '2030-01-02T10:00:00',
  'stats': {
    'total_archives': 8,
    'total_items': 8,
    'completed_prints': 7,
    'failed_prints': 1,
    'queued_prints': 2,
    'total_print_time_hours': 14.6,
    'total_filament_grams': 512.4,
    'progress_percent': 58.3,
    'parts_progress_percent': 35.0,
    'estimated_cost': 12.8,
    'total_energy_kwh': 1.6,
    'total_wear_cost': 3.7,
    'remaining_prints': 5,
    'remaining_parts': 26,
    'bom_total_items': 2,
    'bom_completed_items': 1,
  },
});

const _folders = [
  LibraryFolder(id: 5, name: 'Gridfinity', projectId: 1, fileCount: 2),
  LibraryFolder(id: 6, name: 'Rails', projectId: 1),
];

const _files = [
  LibraryFile(
    id: 31,
    folderId: 5,
    filename: 'Print the lid.gcode.3mf',
    fileType: '3mf',
    fileSize: 1200,
    printCount: 3,
    printName: 'Print the lid',
  ),
  LibraryFile(
    id: 32,
    folderId: 5,
    filename: 'Reference photo.png',
    fileType: 'png',
    fileSize: 900,
    printCount: 0,
  ),
];

const _timeline = [
  TimelineEvent(
    eventType: 'print_completed',
    timestamp: '2030-01-02T10:00:00',
    title: 'Lid finished',
    description: 'X1C-01 · 2 h 10 min',
  ),
  TimelineEvent(
    eventType: 'print_failed',
    timestamp: '2030-01-01T12:00:00',
    title: 'Bin failed',
  ),
];

/// Hands the detail screen a fixed project instead of asking the demo.
class _DetailOf extends ProjectDetailNotifier {
  _DetailOf(this.project, super.arg);

  final ProjectResponse project;

  @override
  Future<ProjectResponse> build() async {
    // The sections below read the API client; creating it for the first time
    // while one of them builds notifies the reachability listeners mid-build.
    // The real screen always has the client by the time it has a project.
    ref.read(projectsRepositoryProvider);
    return project;
  }
}

class _FailingDetail extends ProjectDetailNotifier {
  _FailingDetail(super.arg);

  @override
  Future<ProjectResponse> build() async =>
      throw const ApiException(AppErrorCode.malformedResponse);
}

class _FailingList extends ProjectsListNotifier {
  @override
  Future<List<ProjectListResponse>> build() async =>
      throw const ApiException(AppErrorCode.malformedResponse);
}

class _EveryStatusList extends ProjectsListNotifier {
  @override
  Future<List<ProjectListResponse>> build() async => const [
    ProjectListResponse(
      id: 1,
      name: 'Planned shelves',
      status: 'planning',
      color: '#ff9800',
    ),
    ProjectListResponse(
      id: 2,
      name: 'Active bins',
      description: 'Bins for the drawers.',
      completedCount: 3,
      failedCount: 1,
      queueCount: 2,
      progressPercent: 40,
    ),
    ProjectListResponse(
      id: 3,
      name: 'Paused lamp',
      status: 'on_hold',
      color: '#ffeb3b',
      progressPercent: 10,
    ),
    ProjectListResponse(
      id: 4,
      name: 'Done gifts',
      status: 'completed',
      color: '#9c27b0',
      completedCount: 5,
      progressPercent: 100,
    ),
    ProjectListResponse(id: 5, name: 'Archived rails', status: 'archived'),
    ProjectListResponse(id: 6, name: 'Odd one', status: 'someday'),
  ];
}

/// A library with no folder left to link.
class _NoFolders extends LibraryRepository {
  _NoFolders() : super(Dio());

  @override
  Future<List<LibraryFolder>> listFolders() async => const [];
}
