import 'package:app_util/app_util.dart';

/// A 200 answer carrying [body].
DemoResult demoOk(Object? body) => (status: 200, body: body);

/// The 404 the real server sends for an unknown route or id.
DemoResult demoNotFound() => (status: 404, body: {'detail': 'Not Found'});

/// A refusal with a plain `detail` string, as FastAPI's HTTPException sends it.
DemoResult demoRefuse(int status, String detail) =>
    (status: status, body: {'detail': detail});

/// The row whose `id` equals [id], or null. The comparison is `==` on the raw
/// value, so an id of '3' does not match a row whose id is the int 3.
Map<String, dynamic>? rowById(
  Iterable<Map<String, dynamic>> rows,
  Object? id,
) => rows.where((row) => row['id'] == id).firstOrNull;

/// A timestamp as the server writes it: UTC, ISO 8601, with fractional seconds.
String isoUtc(DateTime t) => t.toUtc().toIso8601String();

/// The integer in query parameter [key], or [fallback] when it is absent or not
/// a number. Negative and zero values are returned as parsed.
int intQuery(Map<String, String> q, String key, int fallback) =>
    int.tryParse(q[key] ?? '') ?? fallback;
