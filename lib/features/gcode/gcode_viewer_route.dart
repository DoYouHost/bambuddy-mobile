/// The in-app route of the full-screen G-code preview, and the one place that
/// builds a link to it.
///
/// Three screens open this viewer — the archive sheet, a queue item and the
/// library file manager — and each used to assemble the query by hand, with its
/// own `Uri.encodeQueryComponent` on the title and its own decision about which
/// parameters to pass. All three simply left the plate out, which is why a
/// multi-plate print used to preview as plate 1; the screen had accepted a
/// plate the whole time.
///
/// The screen's own arguments come back out of this query in `router.dart`, so
/// the parameter names here and the ones read there are the same contract.
const gcodeViewerPath = '/gcode-viewer';

/// A link to the viewer for one source.
///
/// [archiveId] and [libraryFileId] are mutually exclusive — the archive wins if
/// both are given, matching the screen. [plate] is the plate of a multi-plate
/// 3MF and is left out below 1, since `Metadata/plate_0.gcode` does not exist;
/// it is ignored for a library file, whose route serves the first plate whatever
/// is asked. [title] names the app bar.
///
/// Built through [Uri] rather than by string concatenation: a print name can
/// carry `&`, `?`, `#` or `%`, and hand-encoding the title while pasting the
/// rest together is how one of those ends up truncating the query.
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
