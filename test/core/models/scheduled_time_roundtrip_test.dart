import 'package:bambuddy_mobile/core/models/json_utils.dart';
import 'package:bambuddy_mobile/core/models/queue_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// Termin zaplanowanego druku musi przejść pełną pętlę bez dryfu.
///
/// Regresja z 2026-07-30, znaleziona w logu z emulatora na `Europe/Warsaw`:
/// zapis był poprawny (`DateTime(...)` lokalny → `.toUtc()`), ale odczyt oddawał
/// DateTime **w UTC**, a formularz czytał z niego `d.hour` wprost. Efekt:
/// pozycja zapisana na 18:00 pokazywała się jako 16:00, a zapis bez ruszania
/// czegokolwiek zjeżdżał na 14:00Z — czyli każde wejście w edycję przesuwało
/// druk o offset strefy. Nie literówka w wyświetlaniu, a psucie danych w pętli.
///
/// **Uwaga o strefie maszyny testowej.** Asercje na godzinach mają moc tylko przy
/// niezerowym offsecie — na hoście w UTC czas lokalny i UTC to ta sama liczba,
/// więc wykryć takiego błędu nie sposób. Sprawdzone: na `Europe/Warsaw` cały ten
/// plik pada na kodzie sprzed poprawki (`Expected: <18> Actual: <16>`). Asercją
/// niezależną od strefy jest `isUtc, isFalse` w `json_utils_test.dart` — ta łapie
/// połowę „oddajemy UTC" wszędzie, bo `toLocal()` zawsze zeruje ten znacznik.
void main() {
  /// Co ekran edycji wysyła: `_scheduledTimeIso`.
  String outbound(DateTime picked) => picked.toUtc().toIso8601String();

  /// Co ekran edycji odczytuje z pozycji z serwera.
  DateTime inbound(String fromServer) =>
      QueueItem.fromJson({
        'id': 1,
        'position': 1,
        'status': 'pending',
        'scheduled_time': fromServer,
      }).scheduledTime!;

  test('wybrana godzina wraca tą samą godziną', () {
    // 18:00 czasu lokalnego, jakkolwiek strefa urządzenia jest ustawiona.
    final picked = DateTime(2026, 7, 30, 18);

    final stored = outbound(picked);
    final reopened = inbound(stored);

    expect(reopened.hour, 18, reason: 'formularz czyta .hour wprost');
    expect(reopened.minute, 0);
    expect(reopened, picked);
  });

  test('edycja i zapis bez zmian nie przesuwa terminu', () {
    // To jest ta pętla: każdy obrót dokładał offset strefy.
    var wire = outbound(DateTime(2026, 7, 30, 18));

    for (var round = 0; round < 3; round++) {
      final shown = inbound(wire);
      expect(shown.hour, 18, reason: 'obrót $round');
      // Formularz odbudowuje wartość z pól pickera — tak jak po tapnięciu
      // „Zapisz" bez tknięcia godziny.
      wire = outbound(
        DateTime(shown.year, shown.month, shown.day, shown.hour, shown.minute),
      );
    }

    expect(inbound(wire), DateTime(2026, 7, 30, 18));
  });

  test('naive z serwera to ta sama chwila co z Z', () {
    // ArchiveResponse nie dokleja Z, PrintQueueItemResponse dokleja. Ten sam
    // moment w dwóch zapisach nie może dać dwóch różnych godzin na ekranie.
    expect(
      dateTimeFromJson('2026-07-30T16:00:00'),
      dateTimeFromJson('2026-07-30T16:00:00Z'),
    );
  });

  test('zepsuta odpowiedź PATCH nie gubi terminu', () {
    // Serwer odpowiada `+00:00Z` na PATCH; gdyby ktoś zaczął czytać to ciało
    // zamiast robić refetch, termin zrobiłby się null i druk wyglądałby na ASAP.
    final item = QueueItem.fromJson({
      'id': 182,
      'position': 1,
      'status': 'pending',
      'scheduled_time': '2026-07-30T16:00:00+00:00Z',
    });

    expect(item.scheduledTime, isNotNull);
    expect(item.scheduledTime, dateTimeFromJson('2026-07-30T16:00:00Z'));
  });
}
