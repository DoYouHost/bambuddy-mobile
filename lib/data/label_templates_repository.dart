import 'package:dio/dio.dart';

import '../core/api/endpoints.dart';
import '../core/api/observed_capability.dart';
import '../core/api/server_version.dart';
import '../core/api/server_version_service.dart';
import '../core/models/label_template.dart';

/// Custom label sheets saved under a name (server #3296). One list whichever
/// inventory is live, shared by everyone on the install.
///
/// Printing on a custom sheet is not here: the label routes take the layout in
/// the request, and the saved list is never read to print. This is the list and
/// its three writes.
class LabelTemplatesRepository {
  LabelTemplatesRepository(this._dio, [this._serverVersion]);

  final Dio _dio;

  /// Answers [capability] until the listing has.
  final ServerVersionService? _serverVersion;

  /// Whether the server takes a custom sheet at all: the saved list, and a
  /// `layout` on a label request. An older server answers 404 to the list and
  /// 422 to the request, so the listing — which the label picker makes anyway —
  /// settles it.
  late final capability = ObservedCapability(
    ServerFeature.labelTemplates,
    _serverVersion,
  );

  /// The saved sheets in the server's natural name order. A 404 or a 403 answers
  /// with an empty list and records why in [capability].
  ///
  /// A row whose page this app does not know is left out rather than failing
  /// the list ([SheetLayout.tryFromJson]).
  Future<List<SavedLabelTemplate>> list() => capability.watching(
    () async {
      final res = await _dio.get<List<dynamic>>(Endpoints.labelTemplates);
      return [
        for (final row in res.data ?? const [])
          if (row is Map<String, dynamic>) ?SavedLabelTemplate.tryFromJson(row),
      ];
    },
    absent: () => const [],
    observing: treat404AsAbsent,
  );

  /// Saves [layout] under [name]. A 409 is a name already taken (ignoring case
  /// and Unicode composition), a 422 a layout the server refuses.
  ///
  /// None of the writes settles [capability]: their 403 is a missing
  /// `inventory:update`, and taking it for "no templates here" would hide the
  /// list from a session that may still read and print from it.
  Future<SavedLabelTemplate> create(String name, SheetLayout layout) =>
      capability.watching(observing: const {}, () async {
        final res = await _dio.post<Map<String, dynamic>>(
          Endpoints.labelTemplates,
          data: _body(name, layout),
        );
        return _saved(res.data);
      });

  /// Replaces the whole template — the route has no merge. A 404 is the row
  /// gone, a 409 a rename onto a taken name.
  Future<SavedLabelTemplate> update(int id, String name, SheetLayout layout) =>
      capability.watching(observing: const {}, () async {
        final res = await _dio.put<Map<String, dynamic>>(
          Endpoints.labelTemplate(id),
          data: _body(name, layout),
        );
        return _saved(res.data);
      });

  /// Labels already printed with it are unaffected.
  Future<void> delete(int id) => capability.watching(
    observing: const {},
    () => _dio.delete<dynamic>(Endpoints.labelTemplate(id)),
  );

  static Map<String, dynamic> _body(String name, SheetLayout layout) => {
    'name': name,
    'layout': layout.toJson(),
  };

  /// A saved row the app cannot read is the server answering with a page this
  /// build does not know — a contract change, not something to guess past.
  static SavedLabelTemplate _saved(Map<String, dynamic>? json) =>
      SavedLabelTemplate.tryFromJson(json ?? const {}) ??
      (throw const FormatException('unreadable label template'));
}
