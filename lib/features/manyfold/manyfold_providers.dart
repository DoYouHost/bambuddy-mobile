import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/library_folder.dart';
import '../../core/models/manyfold.dart';
import '../../providers.dart';

/// `null`: no Manyfold on this server, or not for this session. Read afresh
/// each time Model Sources opens, as the web's query is.
final manyfoldStatusProvider = FutureProvider.autoDispose<ManyfoldStatus?>(
  (ref) => ref.watch(manyfoldRepositoryProvider).status(),
);

/// The web's tab rule (`ModelSourcesPage.tsx`): shown to whoever may browse,
/// once connected — and before that only to whoever may connect it. False
/// while the status is out, so the tab arrives rather than flickers away.
final manyfoldTabShownProvider = Provider.autoDispose<bool>((ref) {
  final status = ref.watch(manyfoldStatusProvider).valueOrNull;
  if (status == null) return false;
  return status.configured || ref.watch(canConfigureManyfoldProvider);
});

/// One page of models for `(query, page)`.
final manyfoldModelsProvider = FutureProvider.autoDispose
    .family<ManyfoldModelPage, (String, int)>(
      (ref, key) => ref
          .watch(manyfoldRepositoryProvider)
          .models(query: key.$1, page: key.$2),
    );

final manyfoldModelProvider = FutureProvider.autoDispose
    .family<ManyfoldModel, String>(
      (ref, id) => ref.watch(manyfoldRepositoryProvider).model(id),
    );

/// Kept for the session: the server fetches each one from Manyfold, and the
/// grid asks again on every page turn otherwise (the web's `staleTime:
/// Infinity`).
final manyfoldPreviewProvider = FutureProvider.family<Uint8List?, String>(
  (ref, id) => ref.watch(manyfoldRepositoryProvider).preview(id),
);

/// The folders an import may target, with their depth for the picker. The web
/// leaves out a read-only external top-level folder with its subtree, and lists
/// the rest with the ones the user may not write to disabled (#3201).
final manyfoldImportFoldersProvider =
    FutureProvider.autoDispose<List<(LibraryFolder, int)>>((ref) async {
      final tree = await ref.watch(libraryRepositoryProvider).listFolders();
      return [
        for (final top in tree)
          if (!(top.isExternal && top.externalReadonly)) ..._withDepth(top, 0),
      ];
    });

Iterable<(LibraryFolder, int)> _withDepth(LibraryFolder f, int depth) sync* {
  yield (f, depth);
  for (final child in f.children) {
    yield* _withDepth(child, depth + 1);
  }
}
