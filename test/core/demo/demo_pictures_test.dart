import 'dart:io';

import 'package:bambuddy_mobile/core/demo/demo_backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DemoBackend demo;
  setUp(() => demo = DemoBackend.fresh());

  String? picture(String route) => demo.pictureFor('/api/v1$route');

  test('every picture the demo can name ships in assets/demo', () {
    final routes = [
      for (var id = 40; id <= 51; id++) ...[
        '/archives/$id/thumbnail',
        for (final photo
            in (demo.handle('GET', Uri.parse('/api/v1/archives/$id'), null).body
                    as Map)['photos']
                as List)
          '/archives/$id/photos/$photo',
      ],
      for (var id = 900; id < 1000; id++) '/print-log/$id/thumbnail',
      for (var id = 1; id <= 9; id++) '/library/files/$id/thumbnail',
      for (var id = 1; id <= 2; id++) '/projects/$id/cover-image',
      for (var id = 1; id <= 5; id++) '/printers/$id/cover',
    ];
    final named = {
      for (final r in routes) ?picture(r),
      for (var id = 1; id <= 5; id++) ...demo.cameraFrames(id),
    };

    expect(named.length, greaterThan(20));
    for (final p in named) {
      expect(File('assets/demo/$p.webp').existsSync(), isTrue, reason: p);
    }
  });

  test('a print keeps its render and its photos', () {
    expect(picture('/archives/40/thumbnail'), 'thumbs/bag-dispenser');
    expect(
      picture('/archives/40/photos/bag-dispenser.jpg'),
      'photos/bag-dispenser',
    );
    // A photo the print never had is not served from another print's list.
    expect(picture('/archives/40/photos/box.jpg'), isNull);
  });

  test('a print log row shows its archive\'s render', () {
    final rows =
        (demo.handle('GET', Uri.parse('/api/v1/print-log/'), null).body
                as Map)['items']
            as List;
    final row = rows.cast<Map>().firstWhere((r) => r['archive_id'] == 40);
    expect(
      picture('/print-log/${row['id']}/thumbnail'),
      'thumbs/bag-dispenser',
    );
  });

  test('a queued library job carries the file\'s thumbnail', () {
    final queue =
        demo.handle('GET', Uri.parse('/api/v1/queue/'), null).body as List;
    final job = queue.cast<Map>().firstWhere((j) => j['id'] == 101);
    expect(job['library_file_id'], 5);
    expect(picture('/library/files/5/thumbnail'), 'thumbs/gridfinity-bin');
    expect(job['library_file_thumbnail'], isNotNull);
  });

  test('nothing where the real server has nothing', () {
    // STEP is never rendered by the server.
    expect(picture('/library/files/9/thumbnail'), isNull);
    // Printer 3 is the offline one.
    expect(picture('/printers/3/camera/stream'), isNull);
    // Only the machine that is printing has a cover.
    expect(picture('/printers/2/cover'), isNull);
    expect(picture('/printers/1/cover'), 'thumbs/bag-dispenser');
    expect(demo.pictureFor('/not/an/api/route'), isNull);
  });

  test('a cache-busting query does not hide the cover', () {
    expect(picture('/projects/1/cover-image?v=2026'), 'thumbs/gridfinity-bin');
  });

  test('the printing machine\'s camera loops a recording of its job', () {
    final frames = demo.cameraFrames(1);
    expect(frames, hasLength(12));
    expect(frames.toSet(), hasLength(12));
    expect(picture('/printers/1/camera/stream'), frames.first);
    // An idle one shows a still of its plate.
    expect(demo.cameraFrames(2), ['photos/mop-station']);
  });
}
