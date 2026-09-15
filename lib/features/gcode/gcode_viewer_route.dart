/// The in-app route of the full-screen G-code preview, and the one place that
/// builds a link to it.
///
/// The screen's own arguments come back out of this query in `router.dart`, so
/// the parameter names here and the ones read there are one contract.
const gcodeViewerPath = '/gcode-viewer';

/// A link to the viewer for one source.
///
/// [archiveId] and [libraryFileId] are mutually exclusive — the archive wins,
/// matching the screen. [plate] is left out below 1, since
/// `Metadata/plate_0.gcode` does not exist, and ignored for a library file,
/// whose route serves the first plate whatever is asked.
///
/// Built through [Uri] rather than by concatenation: a print name can carry
/// `&`, `?`, `#` or `%`, any of which truncates a hand-pasted query.
String gcodeViewerRoute({
  int? archiveId,
  int? libraryFileId,
  int? plate,
  String? title,
}) {
  assert(
    archiveId != null || libraryFileId != null,
    'archiveId or libraryFileId required',
  );
  final name = title?.trim();
  return Uri(
    path: gcodeViewerPath,
    queryParameters: {
      if (archiveId != null)
        'archive': '$archiveId'
      else if (libraryFileId != null)
        'library_file': '$libraryFileId',
      if (archiveId != null && plate != null && plate >= 1) 'plate': '$plate',
      if (name != null && name.isNotEmpty) 'name': name,
    },
  ).toString();
}
