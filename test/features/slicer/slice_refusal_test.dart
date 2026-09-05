import 'package:bambuddy_mobile/core/api/api_exceptions.dart';
import 'package:bambuddy_mobile/features/slicer/slice_refusal.dart';
import 'package:bambuddy_mobile/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sentences the server actually writes, copied from
/// `routes/library.py::slice_library_file` and `routes/archives.py::slice_archive`.
const _step = 'STEP files cannot be sliced. The OrcaSlicer and Bambu Studio '
    'command-line slicers load only STL and 3MF -- open the STEP in your '
    'slicer and export it as one of those first.';
const _libraryFormat = 'Source file must be STL or 3MF';
const _archiveFormat = "Archive's source file must be STL, 3MF, or STEP to slice";
const _noSource = 'Archive has no source file to slice';

AppApiException _refusal([String? detail]) =>
    ApiException(AppErrorCode.badResponse, statusCode: 400, detail: detail);

void main() {
  late AppLocalizations en;
  late AppLocalizations pl;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    pl = await AppLocalizations.delegate.load(const Locale('pl'));
  });

  test('a STEP source is named, not left as the server\'s paragraph', () {
    expect(sliceRefusalMessage(en, _refusal(_step)), en.sliceRefusedStep);
    expect(sliceRefusalMessage(pl, _refusal(_step)), pl.sliceRefusedStep);
  });

  test('both routes phrase the format refusal their own way; both land', () {
    expect(sliceRefusalMessage(en, _refusal(_libraryFormat)),
        en.sliceRefusedFormat);
    expect(sliceRefusalMessage(en, _refusal(_archiveFormat)),
        en.sliceRefusedFormat,
        reason: 'it names STEP without being about STEP — the format check has '
            'to run first or this reads as the STEP refusal');
  });

  test('an archive with no model kept says so', () {
    expect(sliceRefusalMessage(en, _refusal(_noSource)), en.sliceRefusedNoSource);
  });

  test('a refusal we do not know is quoted rather than swallowed', () {
    expect(
      sliceRefusalMessage(en, _refusal('Slicer sidecar is not configured')),
      'Slicer sidecar is not configured',
      reason: "a phrasing we don't know yet still beats a generic failure",
    );
  });

  test('a refusal with nothing written falls back to the code', () {
    expect(sliceRefusalMessage(en, _refusal()), en.errBadResponse(400));
    expect(sliceRefusalMessage(en, _refusal('   ')), en.errBadResponse(400));
  });

  test('a failure that never reached the server keeps its own wording', () {
    expect(
      sliceRefusalMessage(en, const ApiException(AppErrorCode.serverUnreachable)),
      en.errServerUnreachable,
    );
    // With the detail a real `NetworkException` carries: Dio's own message,
    // which the bare-detail fallback used to put on screen untranslated.
    expect(
      sliceRefusalMessage(
        en,
        const NetworkException(AppErrorCode.serverUnreachable,
            detail: 'Connecting timed out [10000ms]'),
      ),
      en.errServerUnreachable,
    );
  });
}
