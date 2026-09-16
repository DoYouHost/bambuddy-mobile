import 'dart:async';

import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/core/models/project.dart';
import 'package:bambuddy_mobile/data/projects_repository.dart';
import 'package:bambuddy_mobile/features/projects/projects_providers.dart';
import 'package:bambuddy_mobile/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

/// Deletes the test drives by hand, so two can be in flight at once — which is
/// the whole point: the rollback of the first must not speak for the second.
class _FakeRepository extends ProjectsRepository {
  _FakeRepository() : super(Dio());

  final pending = <int, Completer<void>>{};

  List<ProjectListResponse> listed = const [];

  @override
  Future<List<ProjectListResponse>> list({String? status}) async => listed;

  @override
  Future<void> delete(int id) {
    final completer = Completer<void>();
    pending[id] = completer;
    return completer.future;
  }
}

ProjectListResponse _project(int id) =>
    ProjectListResponse(id: id, name: 'Project $id');

void main() {
  late _FakeRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = _FakeRepository();
    repo.listed = [_project(1), _project(2), _project(3)];
    container = ProviderContainer(
      overrides: [
        projectsRepositoryProvider.overrideWithValue(repo),
        noServerProfileOverride,
      ],
    );
    container.listen(projectsListProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  List<int> idsOnScreen() => container
      .read(projectsListProvider)
      .valueOrNull!
      .map((p) => p.id)
      .toList();

  test('a failed delete puts back its own row and no one else\'s', () async {
    await container.read(projectsListProvider.future);
    final notifier = container.read(projectsListProvider.notifier);

    // Two swipes, both optimistic, both still out.
    unawaited(notifier.delete(1));
    unawaited(notifier.delete(2));
    await pumpEventQueue();
    expect(idsOnScreen(), [3]);

    // The second one succeeds, the first is refused.
    repo.pending[2]!.complete();
    await pumpEventQueue();
    repo.pending[1]!.completeError(
      const ApiException(AppErrorCode.serverUnreachable),
    );
    await pumpEventQueue();

    // Restoring the list as it was before project 1's request would have
    // brought project 2 back from the dead.
    expect(idsOnScreen(), [1, 3]);
  });

  test('a failed delete restores the row where it was', () async {
    await container.read(projectsListProvider.future);
    final notifier = container.read(projectsListProvider.notifier);

    unawaited(notifier.delete(2));
    await pumpEventQueue();
    expect(idsOnScreen(), [1, 3]);

    repo.pending[2]!.completeError(
      const ApiException(AppErrorCode.serverUnreachable),
    );
    await pumpEventQueue();

    expect(idsOnScreen(), [1, 2, 3], reason: 'not appended at the end');
  });

  test('a row whose index no longer exists lands at the end, not out of '
      'range', () async {
    await container.read(projectsListProvider.future);
    final notifier = container.read(projectsListProvider.notifier);

    // Project 3 goes out from the last position, and the list shrinks under it
    // — its remembered index is past the end by the time the failure arrives.
    unawaited(notifier.delete(3));
    await pumpEventQueue();
    repo.listed = [_project(1)];
    await notifier.refresh();
    repo.pending[3]!.completeError(
      const ApiException(AppErrorCode.serverUnreachable),
    );
    await pumpEventQueue();

    expect(idsOnScreen(), [1, 3]);
  });

  test('a refresh that landed first keeps the row it fetched', () async {
    await container.read(projectsListProvider.future);
    final notifier = container.read(projectsListProvider.notifier);

    unawaited(notifier.delete(1));
    await pumpEventQueue();

    // The server kept project 1 and a refresh has already said so. The
    // rollback must not insert a second copy of it.
    repo.listed = [_project(1), _project(2), _project(3)];
    await notifier.refresh();
    repo.pending[1]!.completeError(
      const ApiException(AppErrorCode.serverUnreachable),
    );
    await pumpEventQueue();

    expect(idsOnScreen(), [1, 2, 3]);
  });
}
