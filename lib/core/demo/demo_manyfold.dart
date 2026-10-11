import 'dart:typed_data';

import 'package:app_util/app_util.dart';

import 'demo_labels.dart';

/// The demo's Manyfold library (#1471): a connected install with two pages of
/// models, every file state the model view draws (importable, already in the
/// library, a type the server cannot print) and a model with no files.
///
/// Importing is the demo backend's: it owns the library the file lands in.
class DemoManyfold {
  DemoManyfold({required this.libraryFileFor});

  /// The library row an earlier import of `model/file` created, if it is still
  /// there.
  final Map<String, dynamic>? Function(String sourceKey) libraryFileFor;

  /// Small enough that five models make two pages.
  static const _pageSize = 4;

  var _config = <String, dynamic>{
    'url': 'http://192.168.1.50:3214',
    'client_id': 'bambuddy-demo',
    'has_client_secret': true,
    'configured': true,
  };

  static const _models = <Map<String, dynamic>>[
    {
      'id': 'k3x9pq2a',
      'name': 'Articulated dragon',
      'caption': 'Print-in-place, no supports',
      'description':
          'Every joint prints in place. Slice with 0.2 mm layers and 15% infill.',
      'license': 'CC-BY-4.0',
      'tags': ['articulated', 'toy', 'print-in-place'],
      'color': 0x2E7D32,
      'files': [
        {'id': 'f1dragon', 'name': 'dragon.3mf', 'mime': 'model/3mf'},
        {'id': 'f2tail', 'name': 'dragon_tail_long.stl', 'mime': 'model/stl'},
        {'id': 'f3readme', 'name': 'README.pdf', 'mime': 'application/pdf'},
      ],
    },
    {
      'id': 'h7m2vd4n',
      'name': 'Filament swatch box',
      'caption': 'Holds 40 swatches',
      'license': 'CC0-1.0',
      'tags': ['storage', 'filament'],
      'color': 0x1565C0,
      'files': [
        {'id': 'f4box', 'name': 'swatch_box.stl', 'mime': 'model/stl'},
        {'id': 'f5lid', 'name': 'swatch_lid.stl', 'mime': 'model/stl'},
        {'id': 'f6step', 'name': 'swatch_box.step', 'mime': 'model/step'},
      ],
    },
    {
      'id': 'p4w8ze1c',
      'name': 'Desk cable tray',
      'tags': ['desk'],
      'color': 0x6D4C41,
      'files': [
        {'id': 'f7tray', 'name': 'cable_tray.3mf', 'mime': 'model/3mf'},
      ],
    },
    {
      'id': 'r2t6yb8s',
      'name': 'Planetary gear set',
      'description': 'Sun, three planets and a ring.',
      'license': 'MIT',
      'tags': ['mechanical'],
      'color': 0xEF6C00,
      'files': [
        {'id': 'f8gears', 'name': 'planetary_gears.3mf', 'mime': 'model/3mf'},
        {'id': 'f9render', 'name': 'render.png', 'mime': 'image/png'},
      ],
    },
    // No preview and no files: both empty states.
    {'id': 'z9c1fk5u', 'name': 'Lithophane frame', 'files': <Object>[]},
  ];

  DemoResult route(
    String m,
    List<String> s,
    Map<String, String> q,
    Object body,
  ) {
    final at1 = s.length > 1 ? s[1] : null;
    switch (at1) {
      case 'status':
        return _ok({
          'configured': _config['configured'],
          'url': _config['configured'] == true ? _config['url'] : '',
        });
      case 'config':
        if (s.length > 2 && s[2] == 'test') return _test(body);
        if (m == 'PUT') return _save(body);
        if (m == 'DELETE') {
          _config = {
            'url': '',
            'client_id': '',
            'has_client_secret': false,
            'configured': false,
          };
          return (status: 204, body: null);
        }
        return _ok(_config);
      case 'models':
        if (_config['configured'] != true) return _notConfigured();
        if (s.length == 2) return _list(q);
        final model = _models.where((e) => e['id'] == s[2]).firstOrNull;
        if (model == null) {
          return _refuse(404, 'manyfold_not_found', 'Model not found');
        }
        if (s.length > 3 && s[3] == 'preview') return _preview(model);
        return _ok(_detail(model));
    }
    return (status: 404, body: {'detail': 'Not Found'});
  }

  /// `(file name, error)` of [fileId] in [modelId], for the backend's import.
  ({String? name, DemoResult? error}) fileFor(String modelId, String fileId) {
    if (_config['configured'] != true) {
      return (name: null, error: _notConfigured());
    }
    final model = _models.where((e) => e['id'] == modelId).firstOrNull;
    final file = (model?['files'] as List?)
        ?.cast<Map<String, dynamic>>()
        .where((f) => f['id'] == fileId)
        .firstOrNull;
    if (file == null) {
      return (
        name: null,
        error: _refuse(404, 'manyfold_not_found', 'File not found'),
      );
    }
    if (!_importable(file)) {
      return (
        name: null,
        error: _refuse(400, 'manyfold_not_importable', 'Not importable'),
      );
    }
    return (name: file['name'] as String, error: null);
  }

  DemoResult _list(Map<String, String> q) {
    final query = (q['q'] ?? '').trim().toLowerCase();
    final hits = [
      for (final m in _models)
        if (query.isEmpty ||
            (m['name'] as String).toLowerCase().contains(query))
          {'id': m['id'], 'name': m['name']},
    ];
    final page = (int.tryParse(q['page'] ?? '') ?? 1).clamp(1, 100000);
    final start = (page - 1) * _pageSize;
    return _ok({
      'total': hits.length,
      'page': page,
      'has_next': start + _pageSize < hits.length,
      'has_previous': page > 1,
      'models': hits.skip(start).take(_pageSize).toList(),
    });
  }

  Map<String, dynamic> _detail(Map<String, dynamic> model) {
    final id = model['id'] as String;
    return {
      'id': id,
      'name': model['name'],
      'caption': model['caption'],
      'description': model['description'],
      'license': model['license'],
      'tags': model['tags'] ?? const <String>[],
      'url': '${_config['url']}/models/$id',
      'has_preview': model['color'] != null,
      'files': [
        for (final f in (model['files'] as List).cast<Map<String, dynamic>>())
          {
            'id': f['id'],
            'name': f['name'],
            'mime': f['mime'],
            'importable': _importable(f),
            'library_file': switch (libraryFileFor('$id/${f['id']}')) {
              final row? => {
                'id': row['id'],
                'filename': row['filename'],
                'folder_id': row['folder_id'],
              },
              null => null,
            },
          },
      ],
    };
  }

  DemoResult _preview(Map<String, dynamic> model) {
    final color = model['color'] as int?;
    if (color == null) {
      return _refuse(404, 'manyfold_not_found', 'This model has no preview');
    }
    const size = 96;
    final pixels = Uint8List(size * size * 3);
    for (var y = 0; y < size; y++) {
      // Lighter at the top, so the tile reads as a picture, not a swatch.
      final shade = 1.4 - y / size * 0.6;
      for (var x = 0; x < size; x++) {
        final i = (y * size + x) * 3;
        pixels[i] = (((color >> 16) & 0xFF) * shade).clamp(0, 255).round();
        pixels[i + 1] = (((color >> 8) & 0xFF) * shade).clamp(0, 255).round();
        pixels[i + 2] = ((color & 0xFF) * shade).clamp(0, 255).round();
      }
    }
    return (
      status: 200,
      body: DemoFile(demoPng(size, size, pixels), 'image/png'),
    );
  }

  DemoResult _save(Object body) {
    final error = _validate(body);
    if (error != null) return error;
    final b = body as Map;
    _config = {
      'url': (b['url'] as String).trim(),
      'client_id': (b['client_id'] as String).trim(),
      'has_client_secret': true,
      'configured': true,
    };
    return _ok(_config);
  }

  DemoResult _test(Object body) =>
      _validate(body) ?? _ok({'model_count': _models.length});

  /// What `update_config` and `test_config` refuse before signing in.
  DemoResult? _validate(Object body) {
    final b = body is Map ? body : const {};
    final url = b['url'];
    if (url is! String ||
        !(url.startsWith('http://') || url.startsWith('https://'))) {
      return _refuse(400, 'manyfold_bad_url', 'Bad URL');
    }
    final secret = b['client_secret'];
    final hasSecret = secret is String && secret.trim().isNotEmpty;
    if (!hasSecret && _config['has_client_secret'] != true) {
      return _refuse(400, 'manyfold_secret_required', 'Enter the secret');
    }
    return null;
  }

  static bool _importable(Map<String, dynamic> file) =>
      const {'model/3mf', 'model/stl', 'model/step'}.contains(file['mime']);

  static DemoResult _ok(Object? body) => (status: 200, body: body);

  static DemoResult _notConfigured() =>
      _refuse(409, 'manyfold_not_configured', 'Manyfold is not set up');

  static DemoResult _refuse(int status, String code, String message) => (
    status: status,
    body: {
      'detail': {'code': code, 'message': message},
    },
  );
}
