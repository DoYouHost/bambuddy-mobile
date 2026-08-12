import 'package:bambuddy_mobile/core/api/server_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ServerVersion parse(String s) {
    final v = ServerVersion.tryParse(s);
    expect(v, isNotNull, reason: 'nie sparsowano: $s');
    return v!;
  }

  group('parsowanie', () {
    test('trzy człony', () {
      final v = parse('1.2.5');
      expect([v.major, v.minor, v.patch, v.micro], [1, 2, 5, 0]);
      expect(v.isPrerelease, isFalse);
    });

    test('cztery człony — stara numeracja 0.2.x', () {
      final v = parse('0.2.4.9');
      expect([v.major, v.minor, v.patch, v.micro], [0, 2, 4, 9]);
      expect(v.isPrerelease, isFalse);
    });

    test('prefiks v', () {
      expect(parse('v1.2.5.1').micro, 1);
    });

    test('beta', () {
      final v = parse('1.2.6b1');
      expect([v.major, v.minor, v.patch], [1, 2, 6]);
      expect(v.isPrerelease, isTrue);
      expect(v.prereleaseNum, 1);
    });

    test('daily build — sufiks obcinany jak na serwerze', () {
      final v = parse('1.2.6b1-daily.20260729');
      expect([v.major, v.minor, v.patch], [1, 2, 6]);
      expect(v.prereleaseNum, 1);
      expect(v.isPrerelease, isTrue);
      expect(v.raw, '1.2.6b1-daily.20260729',
          reason: 'w logu ma być to, co serwer podał');
    });

    test('rc i alpha też', () {
      expect(parse('1.3.0rc2').prereleaseNum, 2);
      expect(parse('1.3.0alpha1').isPrerelease, isTrue);
    });

    test('nie-wersja → null, nie wyjątek', () {
      for (final junk in [null, '', '   ', 'nieznana', '1', '1.2', '<html>']) {
        expect(ServerVersion.tryParse(junk), isNull, reason: 'wejście: $junk');
      }
    });
  });

  group('porównanie', () {
    test('kolejność członów', () {
      expect(parse('1.2.5') < parse('1.2.6'), isTrue);
      expect(parse('0.2.4.9') < parse('1.2.5'), isTrue);
      expect(parse('1.2.5') < parse('1.2.5.1'), isTrue);
    });

    test('wydanie bije swoją betę', () {
      expect(parse('1.2.5') >= parse('1.2.5b7'), isTrue);
      expect(parse('1.2.5b7') < parse('1.2.5'), isTrue);
    });

    test('późniejsza beta bije wcześniejszą', () {
      expect(parse('1.2.5b10') >= parse('1.2.5b7'), isTrue);
    });

    test('beta następnej wersji bije obecne wydanie', () {
      expect(parse('1.2.6b1') >= parse('1.2.5'), isTrue);
    });
  });

  group('trójstanowe kalibracje', () {
    test('od 1.2.5 w górę', () {
      for (final v in ['1.2.5', '1.2.5.1', '1.2.6', '2.0.0']) {
        expect(parse(v).supportsTriStateCalibration, isTrue, reason: v);
      }
    });

    test('cała linia 0.2.x jeszcze nie', () {
      for (final v in ['0.2.4.9', '0.2.4.8', '0.2.3', '0.1.5']) {
        expect(parse(v).supportsTriStateCalibration, isFalse, reason: v);
      }
    });

    test('beta 1.2.5 liczy się jako obsługująca', () {
      // Zmiana weszła w tym cyklu; potraktowanie bety jako starszego kształtu
      // wysłałoby boolean tam, gdzie user poprosił o auto.
      expect(parse('1.2.5b1').supportsTriStateCalibration, isTrue);
    });

    test('0.2.5bN wychodzi na „nie obsługuje" — i to jest granica tej metody',
        () {
      // bambuddy przenumerowało cykl 0.2.5 na 1.2.5 w trakcie, więc `0.2.5b2`
      // (wersja, którą raportuje nasz serwer) jest betą DOKŁADNIE tego wydania,
      // co wprowadziło trójstan — a mimo to leży pod 1.2.5 w każdym sensownym
      // porządku. Żadne porównanie tych dwóch napisów nie odpowie, czy ta
      // konkretna beta jest przed zmianą czy po niej.
      //
      // Zostaje ostrożne „nie": wysłanie stringa serwerowi, który go nie zna, to
      // 422, a brak pozycji auto to tylko brak funkcji. Prawdziwą odpowiedź daje
      // obserwacja odpowiedzi serwera — patrz
      // QueueRepository.supportsTriStateCalibration i jej testy.
      expect(parse('0.2.5b2').supportsTriStateCalibration, isFalse);
      expect(parse('0.2.5b2') < parse('1.2.5'), isTrue);
    });
  });

  group('mapa wersja → możliwości', () {
    test('każda możliwość ma wpis — brak wpisu cicho wyłącza funkcję', () {
      // supports() na niezmapowanej funkcji zwraca false, więc zapomniany wpis
      // nie wysypie się na teście typów, tylko po cichu zabierze funkcję
      // wszystkim. Ten test jest jedynym miejscem, które to złapie.
      for (final f in ServerFeature.values) {
        expect(ServerVersion.introducedIn[f], isNotNull,
            reason: 'brak progu wersji dla $f');
      }
    });

    test('supports() czyta próg z mapy, nie z osobnego porównania', () {
      final v125 = parse('1.2.5.2');
      final v126 = parse('1.2.6');

      // Tri-state przyszło w 1.2.5, reszta w 1.2.6 — to jedyna różnica między
      // tymi dwiema wersjami w całej tabeli.
      expect(v125.supports(ServerFeature.triStateCalibration), isTrue);
      expect(v126.supports(ServerFeature.triStateCalibration), isTrue);

      for (final f in const [
        ServerFeature.chamberTemp65,
        ServerFeature.crossModelVariants,
        ServerFeature.sliceLayoutOptions,
        ServerFeature.processOverrides,
        ServerFeature.usersSlimListing,
      ]) {
        expect(v125.supports(f), isFalse, reason: '$f nie istnieje w 1.2.5');
        expect(v126.supports(f), isTrue, reason: '$f istnieje w 1.2.6');
      }
    });
  });

  group('bramki 1.2.6', () {
    test('sufit komory: 60 do 1.2.5.x, 65 od 1.2.6', () {
      // Serwer podniósł MAX_CHAMBER_TEMP_C z 60 na 65 (commit b04664c6), a bound
      // jest w Query(le=…) — starszy serwer odpowiada 422, nie przycina.
      expect(parse('1.2.5.2').chamberMaxTargetC, 60);
      expect(parse('1.2.6').chamberMaxTargetC, 65);
    });

    test('beta 1.2.6 liczy się jako obsługująca — funkcje weszły w tym cyklu',
        () {
      // 1.2.6b1 to wydanie, w którym te zmiany faktycznie są (tam siedzi #671
      // i podniesiony sufit), więc czytanie bety jako starszego kontraktu
      // odbierałoby funkcje serwerowi, który je ma.
      final beta = parse('1.2.6b1');
      expect(beta.chamberMaxTargetC, 65);
      expect(beta.supportsCrossModelVariants, isTrue);
      expect(beta.supportsSliceLayoutOptions, isTrue);
      expect(beta.supportsProcessOverrides, isTrue);
    });

    test('daily build bety też liczy się jako obsługujący', () {
      expect(parse('1.2.6b1-daily.20260809').chamberMaxTargetC, 65);
    });

    test('starszy serwer nie dostaje żadnej z bramek', () {
      final old = parse('1.2.5.2');
      expect(old.supportsCrossModelVariants, isFalse);
      expect(old.supportsSliceLayoutOptions, isFalse);
      expect(old.supportsProcessOverrides, isFalse);
    });
  });
}
