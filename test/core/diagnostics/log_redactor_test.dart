import 'package:bambuddy_mobile/core/diagnostics/log_redactor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LogRedactor redactor;

  setUp(() => redactor = LogRedactor());

  group('known values', () {
    test('replaces a remembered secret wherever it appears', () {
      redactor.remember('sk-super-secret-key', '[APIKEY]');

      expect(
        redactor.scrubString('auth failed for sk-super-secret-key (401)'),
        'auth failed for [APIKEY] (401)',
      );
    });

    test('replaces the longest match first', () {
      redactor
        ..remember('printer.lan', '[HOST]')
        ..remember('printer.lan.example.com', '[HOST]');

      expect(
        redactor.scrubString('GET https://printer.lan.example.com/api'),
        'GET https://[HOST]/api',
      );
    });

    test('rememberServerUrl masks the host where it appears bare', () {
      redactor.rememberServerUrl('https://bambuddy.local:8443');

      expect(
        redactor.scrubString("Failed host lookup: 'bambuddy.local'"),
        "Failed host lookup: '[HOST]'",
      );
    });

    test('rememberServerUrl leaves the port for the authority pass to keep',
        () {
      redactor.rememberServerUrl('https://bambuddy.local:8443');

      expect(
        redactor.scrubString('GET https://bambuddy.local:8443/api/v1/printers'),
        'GET https://[HOST]:8443/api/v1/printers',
      );
    });

    test('rememberServerUrl ignores junk instead of throwing', () {
      redactor
        ..rememberServerUrl(null)
        ..rememberServerUrl('')
        ..rememberServerUrl('not a url');

      expect(redactor.scrubString('not a url'), 'not a url');
    });

    test('ignores null and very short values to avoid over-redaction', () {
      redactor
        ..remember(null, '[X]')
        ..remember('ok', '[X]');

      expect(redactor.scrubString('ok, everything is ok'),
          'ok, everything is ok');
    });

    test('forget removes a value that is no longer held', () {
      redactor.remember('rotating-token', '[TOKEN]');
      redactor.forget('rotating-token');

      expect(redactor.scrubString('rotating-token'), 'rotating-token');
    });
  });

  group('shape-based passes', () {
    test('masks an unknown host but keeps scheme and port', () {
      expect(
        redactor.scrubString('GET http://192.168.1.9:8080/api/v1/status'),
        'GET http://[HOST]:8080/api/v1/status',
      );
      expect(
        redactor.scrubString('ws upgrade wss://home.example.com/api/v1/ws'),
        'ws upgrade wss://[HOST]/api/v1/ws',
      );
    });

    test('keeps http and https distinguishable — that is the point', () {
      expect(redactor.scrubString('https://a.example.com/x'),
          isNot(contains('http://')));
      expect(redactor.scrubString('http://a.example.com/x'),
          startsWith('http://'));
    });

    test('masks credentials embedded in a url, host and all', () {
      expect(
        redactor.scrubString('connect rtsps://bblp:12345678@camera.lan/stream'),
        'connect rtsps://[CREDENTIALS]@[HOST]/stream',
      );
    });

    test('masks a jwt anywhere in the text', () {
      const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abc-def_123';

      expect(redactor.scrubString('Bearer $jwt'), 'Bearer [JWT]');
    });

    test('masks a bambuddy API key by its shape', () {
      // The app's own key is remembered and caught that way; this is for one
      // that turns up where nobody registered it — a sampled body, a server
      // message, a field the name pass has never heard of.
      expect(
        redactor.scrubString('created key bb_9fA-3kZ_x7Qq for the kiosk'),
        'created key [APIKEY] for the kiosk',
      );
      // Too short to be a key, and "bb_" is also a plausible prefix in a name.
      expect(redactor.scrubString('plate bb_2'), 'plate bb_2');
    });

    test('masks token query parameters but keeps the parameter name', () {
      expect(
        redactor.scrubString('/archives/7/thumbnail?token=abcdef123456'),
        '/archives/7/thumbnail?token=[REDACTED]',
      );
      expect(
        redactor.scrubString('/stream?fps=5&api_key=zzz&x=1'),
        '/stream?fps=5&api_key=[REDACTED]&x=1',
      );
    });

    test('masks emails and Bambu serials', () {
      expect(redactor.scrubString('user@example.com'), '[EMAIL]');
      expect(redactor.scrubString('printer 01P00A123456789 ready'),
          'printer [SERIAL] ready');
    });

    test('masks the serial shapes a live X2D answers with', () {
      // The shape came off a real server — the digits here are anonymised, the
      // pattern is not. Neither matched the original `0[0-3]…` pattern, and both
      // travel inside a status frame where no field name says "serial".
      expect(redactor.scrubString('sn 20P0AA000000001'), 'sn [SERIAL]');
      expect(redactor.scrubString('ams 19C0AA000000002'), 'ams [SERIAL]');
      // Not a serial: a 14-digit stamp of the kind our own file names carry.
      expect(redactor.scrubString('20260728181959'), '20260728181959');
    });

    test('leaves HMS codes and plain numbers alone', () {
      // Both of these matched the serial pass before a live capture showed them
      // up. An HMS code masked as `[SERIAL]` blinds the log to the one field the
      // HMS catalog exists to read, and `hours_until_due` is not anybody's
      // printer.
      expect(redactor.scrubString('full_code 030001000001000A'),
          'full_code 030001000001000A');
      expect(
          redactor.scrubString('due in 33.01666666666665 h'),
          'due in 33.01666666666665 h');
    });

    test('masks IPv4 addresses', () {
      expect(redactor.scrubString('connecting to 192.168.1.50:8080'),
          'connecting to [IP]:8080');
    });

    test('leaves firmware versions alone', () {
      // Leading-zero octets are not valid IPv4 — that is what separates a
      // firmware string from an address.
      expect(redactor.scrubString('firmware 01.09.01.00'),
          'firmware 01.09.01.00');
    });
  });

  group('fields', () {
    test('redacts values by field name whatever their shape', () {
      final out = redactor.scrubFields(const {
        'method': 'GET',
        'api_key': 'plain-looking-value',
        'access_code': '11223344',
        'serial': 'not-a-serial-shape',
      });

      expect(out['method'], 'GET');
      expect(out['api_key'], '[REDACTED]');
      expect(out['access_code'], '[REDACTED]');
      expect(out['serial'], '[REDACTED]');
    });

    test('a username is a person, not a diagnosis', () {
      // Every queue and archive record the log samples carries
      // `created_by_username`; on a shared server that is somebody else's name
      // in a public issue.
      final out = redactor.scrubFields(const {
        'created_by_username': 'SomeoneElse',
        'printer_name': 'X2D-3DP',
      });

      expect(out['created_by_username'], '[REDACTED]');
      expect(out['printer_name'], 'X2D-3DP');
    });

    test('a field called key is a secret, monkey and keyboard are not', () {
      // bambuddy answers with the full API key under exactly `key`
      // (`POST /api-keys`), so the name pass has to know that one on its own —
      // without turning every field whose name contains "key" into a secret.
      final out = redactor.scrubFields(const {
        'key': 'bb_wouldbeleaked',
        'full_key': 'bb_alsoleaked',
        'monkey': 'PLA monkey figurine',
        'keyboard': 'keyboard tray v2',
      });

      expect(out['key'], '[REDACTED]');
      expect(out['full_key'], '[REDACTED]');
      expect(out['monkey'], 'PLA monkey figurine');
      expect(out['keyboard'], 'keyboard tray v2');
    });

    test('walks nested maps and lists', () {
      final out = redactor.scrubFields(const {
        'body': {
          'printers': ['192.168.0.7', '10.0.0.1'],
          'nested': {'token': 'deep-secret'},
        },
      });

      expect(out['body'], {
        'printers': ['[IP]', '[IP]'],
        'nested': {'token': '[REDACTED]'},
      });
    });

    test('non-string scalars pass through untouched', () {
      final out = redactor.scrubFields(const {'status': 502, 'ok': false});

      expect(out, {'status': 502, 'ok': false});
    });

    test('clips a long value so one stack trace cannot fill the buffer', () {
      final short = LogRedactor(maxStringLength: 10);

      expect(short.scrubString('abcdefghijklmnop'), 'abcdefghij…[clipped]');
    });

    test('clipping happens after redaction, never mid-secret', () {
      final short = LogRedactor(maxStringLength: 12)
        ..remember('long-secret-value-here', '[APIKEY]');

      // Clipping the raw string first would have left a secret fragment in
      // the record; redacting first means the label survives instead.
      expect(short.scrubString('key long-secret-value-here rejected'),
          'key [APIKEY]…[clipped]');
    });
  });

  test('leaves a control identifier alone when a host looks like a word', () {
    // The demo server is `http://demo`, so `demo` is a known host — and the id
    // `setup.demo` came back as `setup.[HOST]` from a real session.
    final redactor = LogRedactor()..remember('demo', '[HOST]');

    final fields = redactor.scrubFields(const {
      'id': 'setup.demo',
      'msg': 'could not reach demo',
    });

    expect(fields['id'], 'setup.demo');
    expect(fields['msg'], 'could not reach [HOST]');
  });

  test('still scrubs an id that is not shaped like one of ours', () {
    // A dotted word is ours; anything with spaces or punctuation came from
    // somewhere else and gets the usual treatment.
    final redactor = LogRedactor()..remember('demo', '[HOST]');

    expect(
      redactor.scrubFields(const {'id': 'Rain Gauge on demo'})['id'],
      'Rain Gauge on [HOST]',
    );
  });

  test('leaves the material alone when a host is named after one', () {
    // Same trap as `setup.demo`, one field over: a server called `pla` would
    // turn every `mat` into `[HOST]`.
    final redactor = LogRedactor()..remember('PLA-CF', '[HOST]');

    expect(redactor.scrubFields(const {'mat': 'PLA-CF'})['mat'], 'PLA-CF');
  });

  test('leaves a nested material alone too', () {
    // The WebSocket probe reports an AMS slot's material one level down, inside
    // the `ams` list — the exemption is about what the key means, not how deep
    // it sits.
    final redactor = LogRedactor()..remember('PLA-CF', '[HOST]');

    final fields = redactor.scrubFields(const {
      'ams': [
        {
          'id': 0,
          'trays': [
            {'id': 0, 'mat': 'PLA-CF'},
          ],
        },
      ],
    });

    final unit = (fields['ams']! as List).single as Map<String, Object?>;
    final tray = (unit['trays']! as List).single as Map<String, Object?>;
    expect(tray['mat'], 'PLA-CF');
  });

  test('still scrubs a material that is not shaped like one of ours', () {
    final redactor = LogRedactor()..remember('Bambu PLA Basic', '[HOST]');

    expect(
      redactor.scrubFields(const {'mat': 'Bambu PLA Basic'})['mat'],
      '[HOST]',
    );
  });

  test('leaves the notification event and reason alone on a LAN host', () {
    // A server at `http://printer:8080` registers `printer`, which turned
    // `printerError` into `[HOST]Error` — mangling the one field that says which
    // notification the record is about.
    final redactor = LogRedactor()..rememberServerUrl('http://printer:8080');

    final fields = redactor.scrubFields(const {
      'event': 'printerError',
      'reason': 'typeOff',
      'msg': 'could not reach printer',
    });

    expect(fields['event'], 'printerError');
    expect(fields['reason'], 'typeOff');
    expect(fields['msg'], 'could not reach [HOST]');
  });

  test('still scrubs an event that is not shaped like one of ours', () {
    // Letters only is the whole guarantee: anything carrying a space, a digit or
    // punctuation did not come from the enum and is treated as user content.
    final redactor = LogRedactor()..rememberServerUrl('http://printer:8080');

    expect(
      redactor.scrubFields(const {'event': 'printer 3 finished'})['event'],
      '[HOST] 3 finished',
    );
  });
}
