import 'package:bambuddy_mobile/core/api/content_disposition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('contentDispositionFilename', () {
    test('reads the quoted name', () {
      expect(
        contentDispositionFilename('attachment; filename="log.csv"'),
        'log.csv',
      );
    });

    test('reads a name without quotes', () {
      expect(
        contentDispositionFilename('attachment; filename=log.csv'),
        'log.csv',
      );
    });

    test('the UTF-8 form wins over the ASCII fallback', () {
      // What `build_content_disposition` sends for a name with non-ASCII text.
      expect(
        contentDispositionFilename(
          "attachment; filename=\"Drukarka-log.csv\"; "
          "filename*=UTF-8''Drukarka%20%C5%81%C3%B3d%C5%BA-log.csv",
        ),
        'Drukarka Łódź-log.csv',
      );
    });

    test('a broken escape falls back to the plain form', () {
      expect(
        contentDispositionFilename(
          "attachment; filename=\"a.csv\"; filename*=UTF-8''%E0%A4%A",
        ),
        'a.csv',
      );
    });

    test('another charset in the extended form is not read', () {
      expect(
        contentDispositionFilename(
          "attachment; filename=\"a.csv\"; filename*=ISO-8859-1''b.csv",
        ),
        'a.csv',
      );
    });

    test('no header, no name, an empty name, nothing worth using', () {
      expect(contentDispositionFilename(null), isNull);
      expect(contentDispositionFilename(''), isNull);
      expect(contentDispositionFilename('attachment'), isNull);
      expect(contentDispositionFilename('attachment; filename=""'), isNull);
      expect(contentDispositionFilename('attachment; filename=".."'), isNull);
      expect(contentDispositionFilename('attachment; size=3'), isNull);
    });

    test('a semicolon inside the quotes is part of the name', () {
      expect(
        contentDispositionFilename('attachment; filename="a;b.csv"'),
        'a;b.csv',
      );
    });

    test('text inside the quotes is not a parameter of its own', () {
      expect(
        contentDispositionFilename(
          "attachment; filename=\"a; filename*=UTF-8''evil.csv\"",
        ),
        "a; filename*=UTF-8''evil.csv",
      );
    });

    test(
      'a string that is never closed drops its parameter, and what it hid',
      () {
        expect(
          contentDispositionFilename('attachment; filename="log.csv'),
          isNull,
        );
        expect(
          contentDispositionFilename(
            "attachment; filename=\"a.csv; filename*=UTF-8''b.csv",
          ),
          isNull,
        );
        expect(
          contentDispositionFilename(
            "attachment; filename=\"a\\\"; filename*=UTF-8''b.csv",
          ),
          isNull,
        );
      },
    );

    test('a stray quote inside a token hides nothing', () {
      expect(
        contentDispositionFilename('attachment; x=1"2; filename="a.csv"'),
        'a.csv',
      );
    });

    test('an escaped quote stays in the name', () {
      expect(
        contentDispositionFilename(r'attachment; filename="a\"b.csv"'),
        'a"b.csv',
      );
    });

    test('control characters are dropped', () {
      expect(
        contentDispositionFilename(
          "attachment; filename*=UTF-8''report%00%0A.csv",
        ),
        'report.csv',
      );
      expect(
        contentDispositionFilename("attachment; filename*=UTF-8''%00%1F"),
        isNull,
      );
    });

    test('an extended name with nothing usable leaves the plain one', () {
      expect(
        contentDispositionFilename(
          "attachment; filename=\"fallback.csv\"; filename*=UTF-8''",
        ),
        'fallback.csv',
      );
      expect(
        contentDispositionFilename(
          "attachment; filename=\"fallback.csv\"; filename*=UTF-8''..",
        ),
        'fallback.csv',
      );
    });

    test('only the last path segment survives, with either separator', () {
      expect(
        contentDispositionFilename('attachment; filename="../../etc/cron.d/x"'),
        'x',
      );
      expect(
        contentDispositionFilename(
          r'attachment; filename="C:\Windows\log.csv"',
        ),
        'log.csv',
      );
      expect(
        contentDispositionFilename(
          "attachment; filename*=UTF-8''..%2F..%2Fx.csv",
        ),
        'x.csv',
      );
    });
  });
}
