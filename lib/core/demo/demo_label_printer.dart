import 'package:app_util/app_util.dart';
import 'package:dio/dio.dart';

import '../network/label_printer_discovery.dart';

/// The label print server of the demo: a printer that is "found on the
/// network", answers `/info` and takes a job, so the whole path — search,
/// choose, print, the refusal of a label of another shape — can be walked
/// without a Brother printer.
///
/// It is its own host rather than part of the demo bambuddy: the real one is a
/// separate service, and the app talks to it through a Dio of its own.
const demoLabelPrinterHost = 'demo-label-printer';
const demoLabelPrinterUrl = 'http://$demoLabelPrinterHost:8000';

/// What a search turns up in the demo.
const demoLabelPrinter = DiscoveredLabelPrinter(
  name: 'Demo label printer',
  baseUrl: demoLabelPrinterUrl,
  model: 'QL-600',
  labelId: '62x29',
);

/// A search in the demo: the printer shows up a moment in, and the search ends
/// a moment after, as a real one does.
Stream<List<DiscoveredLabelPrinter>> demoDiscoverLabelPrinters() async* {
  await Future<void>.delayed(const Duration(milliseconds: 900));
  yield const [demoLabelPrinter];
  await Future<void>.delayed(const Duration(milliseconds: 600));
}

bool isDemoLabelPrinter(String baseUrl) =>
    Uri.tryParse(baseUrl)?.host == demoLabelPrinterHost;

/// Serves the demo printer. A job takes a moment, like the real thing's.
HttpClientAdapter demoLabelPrinterAdapter() => DemoHttpClientAdapter(
  _handle,
  uploads: _print,
  latency: const Duration(milliseconds: 700),
);

DemoResult _handle(String method, Uri uri, Object? body) {
  if (method == 'GET' && uri.path == '/info') {
    return (
      status: 200,
      body: {
        'service': 'label-printer',
        'version': 1,
        'printer': {'model': 'QL-600', 'connected': true},
        'label': {'id': '62x29', 'width_mm': 62, 'height_mm': 29, 'dpi': 300},
        'limits': {
          'max_copies': 50,
          'max_labels': 100,
          'max_prints': 500,
          'max_file_mb': 25,
        },
        'accepts': ['.png', '.jpg', '.jpeg', '.pdf', '.zip'],
      },
    );
  }
  return (status: 404, body: {'detail': 'Not Found'});
}

/// `POST /print`: the checks of the real server that a label can fail on in
/// the app — copies out of range, and a label that is not the loaded stock.
/// The app names a file after its template, which is all the demo has to go by.
DemoResult _print(FormData form) {
  final files = [
    for (final f in form.files)
      if (f.key == 'files') f.value,
  ];
  if (files.isEmpty) {
    return (status: 422, body: {'detail': 'files: field required'});
  }
  final copies =
      int.tryParse(
        form.fields.where((f) => f.key == 'copies').firstOrNull?.value ?? '1',
      ) ??
      0;
  if (copies < 1 || copies > 50) {
    return (status: 422, body: {'detail': 'copies must be 1 to 50'});
  }
  for (final file in files) {
    final name = file.filename ?? 'labels.pdf';
    if (!name.contains('box_62x29')) {
      return (
        status: 400,
        body: {
          'detail': '$name: wrong_format (not 62 x 29 mm)',
          'errors': [
            {
              'name': name,
              'code': 'wrong_format',
              'detail': 'the loaded label is 62 x 29 mm',
            },
          ],
        },
      );
    }
  }
  return (
    status: 200,
    body: {
      'status': 'ok',
      'labels': files.length,
      'copies': copies,
      'printed': files.length * copies,
    },
  );
}
