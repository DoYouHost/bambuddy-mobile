import 'package:http_mock_adapter/http_mock_adapter.dart';

/// Answers `GET /updates/version` with [version]. The version service reads
/// `version` only, so [repo] is whatever a file wants to see on the wire.
void stubServerVersion(
  DioAdapter adapter,
  String version, {
  String repo = 'x/y',
}) => adapter.onGet(
  '/api/v1/updates/version',
  (s) => s.reply(200, {'version': version, 'repo': repo}),
);
