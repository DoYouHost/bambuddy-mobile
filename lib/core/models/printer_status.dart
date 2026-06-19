import 'package:json_annotation/json_annotation.dart';

part 'printer_status.g.dart';

/// Status drukarki z `GET /printers/{id}/status` (i docelowo z ramek WS
/// `printer_status` w M2). Centralne DTO — tu obowiązuje wzorzec
/// parsowania defensywnego: pola nullable, liczby przez konwertery
/// tolerujące int/double/string, nieznane klucze ignorowane,
/// nigdy `!` na danych z serwera.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class PrinterStatus {
  const PrinterStatus({
    required this.id,
    this.name,
    this.connected,
    this.state,
    this.currentPrint,
    this.gcodeFile,
    this.progress,
    this.remainingTime,
    this.layerNum,
    this.totalLayers,
    this.temperatures,
    this.coverUrl,
    this.stgCurName,
    this.coolingFanSpeed,
    this.bigFan1Speed,
    this.bigFan2Speed,
    this.heatbreakFanSpeed,
    this.speedLevel,
    this.chamberLight,
    this.airductMode,
    this.ams,
    this.vtTray,
    this.trayNow,
    this.activeExtruder,
    this.amsExtruderMap,
    this.model,
    this.wifiSignal,
    this.doorOpen,
    this.awaitingPlateClear,
    this.hmsErrors,
  });

  factory PrinterStatus.fromJson(Map<String, dynamic> json) =>
      _$PrinterStatusFromJson(json);

  final int id;
  final String? name;
  final bool? connected;

  /// Surowy stan z serwera (np. RUNNING/IDLE/FAILED) — nie enumujemy,
  /// żeby nowe wartości nie wywalały parsera.
  final String? state;
  final String? currentPrint;
  final String? gcodeFile;

  /// Postęp w procentach 0–100.
  @JsonKey(fromJson: _toDoubleOrNull)
  final double? progress;

  /// Pozostały czas w minutach.
  @JsonKey(fromJson: _toIntOrNull)
  final int? remainingTime;

  @JsonKey(fromJson: _toIntOrNull)
  final int? layerNum;

  @JsonKey(fromJson: _toIntOrNull)
  final int? totalLayers;

  /// Klucze nieudokumentowane po stronie serwera (zwykle nozzle/bed/
  /// chamber) — renderujemy co przyjdzie, nie zakładamy zestawu.
  @JsonKey(fromJson: _toTemperaturesOrNull)
  final Map<String, double>? temperatures;

  /// Ścieżka do okładki bieżącego wydruku (np. `/api/v1/printers/1/cover`).
  /// Wymaga tokenu strumienia kamery jako `?token=` przy pobieraniu.
  final String? coverUrl;

  /// Nazwa bieżącego etapu z serwera (np. „Auto bed leveling", „Heating");
  /// null/pusta poza fazą przygotowania. Przychodzi po angielsku.
  final String? stgCurName;

  /// Wentylator chłodzenia części (part cooling), 0–100%.
  @JsonKey(fromJson: _toIntOrNull)
  final int? coolingFanSpeed;

  /// Wentylator pomocniczy (aux/big fan 1), 0–100%.
  @JsonKey(fromJson: _toIntOrNull)
  final int? bigFan1Speed;

  /// Wentylator komory (big fan 2), 0–100%.
  @JsonKey(fromJson: _toIntOrNull)
  final int? bigFan2Speed;

  /// Wentylator heatbreaku, 0–100% (zwykle 0 — sterowany przez firmware).
  @JsonKey(fromJson: _toIntOrNull)
  final int? heatbreakFanSpeed;

  /// Poziom prędkości Bambu: 1 Silent, 2 Standard, 3 Sport, 4 Ludicrous.
  @JsonKey(fromJson: _toIntOrNull)
  final int? speedLevel;

  /// Czy światło komory jest włączone.
  final bool? chamberLight;

  /// Tryb nawiewu komory: 0 = chłodzenie, 1 = grzanie. Inne wartości → null
  /// w [airductIsHeating] (nie zakładamy więcej trybów niż znane).
  @JsonKey(fromJson: _toIntOrNull)
  final int? airductMode;

  /// Jednostki AMS (po jednej na moduł). Parsowane defensywnie — element
  /// nie-mapowy jest pomijany, nigdy nie wywraca statusu.
  @JsonKey(fromJson: _toAmsListOrNull)
  final List<AmsUnit>? ams;

  /// Zewnętrzna szpula (external spool) — ta sama struktura co slot AMS.
  /// Serwer zwykle podaje 1–2 wpisy (id 254/255).
  @JsonKey(fromJson: _toTrayListOrNull)
  final List<AmsTray>? vtTray;

  /// Globalny numer aktywnego slotu (AMS: jednostka*4 + slot; szpula 254/255).
  @JsonKey(fromJson: _toIntOrNull)
  final int? trayNow;

  /// Aktywny ekstruder (dysza) na maszynach dwudyszowych (X2D/H2D); 0/1.
  /// null/0 na zwykłych jednodyszowych.
  @JsonKey(fromJson: _toIntOrNull)
  final int? activeExtruder;

  /// Mapa „id jednostki AMS → ekstruder, który karmi". Klucze przychodzą
  /// jako stringi (np. `{"0":1}`) — normalizujemy do int.
  @JsonKey(fromJson: _toExtruderMapOrNull)
  final Map<int, int>? amsExtruderMap;

  /// Model drukarki z serwera (np. „X2D", „P1S").
  final String? model;

  /// Siła sygnału Wi-Fi w dBm (ujemna; bliżej 0 = lepiej). null = brak/LAN.
  @JsonKey(fromJson: _toIntOrNull)
  final int? wifiSignal;

  /// Czy drzwiczki/pokrywa są otwarte (jeśli drukarka to raportuje).
  final bool? doorOpen;

  /// Czy maszyna czeka na zdjęcie wydruku z płyty przed kolejnym zadaniem
  /// (klucz `awaiting_plate_clear`). Źródło zdarzenia „płyta niepusta".
  final bool? awaitingPlateClear;

  /// Aktywne błędy HMS drukarki (`hms_errors`). Lista bywa pusta = brak błędów;
  /// kształt elementu różni się między wersjami serwera, więc parsujemy
  /// defensywnie (patrz [HmsError]).
  @JsonKey(fromJson: _toHmsListOrNull)
  final List<HmsError>? hmsErrors;

  /// Scala świeżą ramkę na poprzednim stanie tej samej drukarki. Reguła:
  /// **nigdy nie zeruj znanej wartości** — każde pole, którego nowa ramka nie
  /// niesie (`null`), dziedziczy ostatnią znaną. Powód: ani REST, ani WS nie
  /// gwarantują kompletnego snapshotu — WS i REST niosą rozłączne podzbiory
  /// (WS nie ma `airduct_mode`; REST nie ma `model`/`vt_tray`/`cover_url`/
  /// `stg_cur_name`/…), a do tego pojedynczy poll bootującej się drukarki bywa
  /// częściowy/zaszumiony. Bezwarunkowe nadpisanie „żywych" pól (postęp, temp,
  /// wentylatory) gasiło je wtedy na chwilę do `—`, by następny poll je
  /// przywrócił — stąd miganie wartości co 5 s na fallbacku REST (zanim WS
  /// nawiąże połączenie). Wartość, która realnie się zmienia, i tak przychodzi
  /// nie-null (np. `connected:false`, fan `0`), więc się propaguje; dziedziczenie
  /// łapie tylko brak pola, nie jego zmianę.
  ///
  /// `temperatures` scalamy PER-KLUCZ (nakładka): brak jednego czujnika w ramce
  /// nie wygasza jego kafelka, a obecne czujniki dostają świeże odczyty.
  PrinterStatus mergedWith(PrinterStatus? previous) {
    if (previous == null) return this;
    return PrinterStatus(
      id: id,
      name: name ?? previous.name,
      connected: connected ?? previous.connected,
      state: state ?? previous.state,
      currentPrint: currentPrint ?? previous.currentPrint,
      gcodeFile: gcodeFile ?? previous.gcodeFile,
      progress: progress ?? previous.progress,
      remainingTime: remainingTime ?? previous.remainingTime,
      layerNum: layerNum ?? previous.layerNum,
      totalLayers: totalLayers ?? previous.totalLayers,
      temperatures: _mergeTemps(previous.temperatures),
      coverUrl: coverUrl ?? previous.coverUrl,
      stgCurName: stgCurName ?? previous.stgCurName,
      coolingFanSpeed: coolingFanSpeed ?? previous.coolingFanSpeed,
      bigFan1Speed: bigFan1Speed ?? previous.bigFan1Speed,
      bigFan2Speed: bigFan2Speed ?? previous.bigFan2Speed,
      heatbreakFanSpeed: heatbreakFanSpeed ?? previous.heatbreakFanSpeed,
      speedLevel: speedLevel ?? previous.speedLevel,
      chamberLight: chamberLight ?? previous.chamberLight,
      airductMode: airductMode ?? previous.airductMode,
      ams: ams ?? previous.ams,
      vtTray: vtTray ?? previous.vtTray,
      trayNow: trayNow ?? previous.trayNow,
      activeExtruder: activeExtruder ?? previous.activeExtruder,
      amsExtruderMap: amsExtruderMap ?? previous.amsExtruderMap,
      model: model ?? previous.model,
      wifiSignal: wifiSignal ?? previous.wifiSignal,
      doorOpen: doorOpen ?? previous.doorOpen,
      awaitingPlateClear: awaitingPlateClear ?? previous.awaitingPlateClear,
      hmsErrors: hmsErrors ?? previous.hmsErrors,
    );
  }

  /// Nakładka odczytów temperatur na poprzednie: świeże klucze nadpisują,
  /// brakujące zostają z ostatniej znanej wartości (czujnik nieobecny w danej
  /// ramce nie gaśnie do `—`).
  Map<String, double>? _mergeTemps(Map<String, double>? previous) {
    if (temperatures == null) return previous;
    if (previous == null) return temperatures;
    return {...previous, ...temperatures!};
  }

  /// true = grzanie, false = chłodzenie, null = brak/nieznany tryb.
  bool? get airductIsHeating => switch (airductMode) {
        0 => false,
        1 => true,
        _ => null,
      };

  /// Procent prędkości odpowiadający [speedLevel] (mapowanie Bambu);
  /// null gdy poziom nieznany/nieustawiony.
  int? get speedPercent => switch (speedLevel) {
        1 => 50,
        2 => 100,
        3 => 124,
        4 => 166,
        _ => null,
      };

  /// Czy trwa zadanie wydruku — w tym fazy przygotowania (nagrzewanie,
  /// auto bed leveling, pauza), gdzie `progress`/`remainingTime` bywają
  /// zerowe, a serwer i tak raportuje aktywny stan. Fallback na dane
  /// postępu, gdy serwer nie poda stanu.
  bool get isPrinting {
    switch (state?.toUpperCase()) {
      case 'RUNNING':
      case 'PREPARE':
      case 'PAUSE':
      case 'PAUSED':
        return true;
      case 'IDLE':
      case 'FINISH':
      case 'FINISHED':
      case 'FAILED':
        return false;
    }
    return (progress ?? 0) > 0 && (remainingTime ?? 0) > 0;
  }

  /// Faza przygotowania: aktywny wydruk, ale jeszcze bez realnego postępu —
  /// wtedy w UI pokazujemy nazwę etapu zamiast paska 0%.
  bool get isPreparing => isPrinting && (progress ?? 0) <= 0;

  /// Wydruk wstrzymany (pauza). Sterowanie pokazuje wtedy „Wznów" zamiast
  /// „Pauza". Stan z serwera, więc bywa po angielsku w różnych wariantach.
  bool get isPaused => switch (state?.toUpperCase()) {
        'PAUSE' || 'PAUSED' => true,
        _ => false,
      };

  /// Szpule zewnętrzne uporządkowane po id rosnąco (254, 255, …).
  List<AmsTray> get externalSpools {
    final list = [...?vtTray];
    list.sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
    return list;
  }

  /// Maszyna dwudyszowa — wtedy w UI rozróżniamy, który materiał siedzi na
  /// którym ekstruderze (na zwykłej jednodyszowej to zbędne).
  bool get isDualExtruder =>
      externalSpools.length > 1 || (amsExtruderMap?.length ?? 0) > 1;

  /// Numer ekstrudera, który karmi szpula zewnętrzna o danym `id`.
  ///
  /// Kontrakt H2D/X2D potwierdzony przy fizycznej drukarce: szpule mapują się
  /// ODWROTNIE do kolejności id — 254 → ekstruder 1 (lewy), 255 → ekstruder 0
  /// (prawy). Stąd odwrócony indeks względem [externalSpools] (rosnących).
  int? extruderForExternal(int? trayId) {
    if (trayId == null) return null;
    final spools = externalSpools;
    final i = spools.indexWhere((t) => t.id == trayId);
    return i < 0 ? null : (spools.length - 1) - i;
  }

  /// Materiał aktualnie załadowany na drukarce (na aktywnym ekstruderze).
  ///
  /// Założenie kontraktu X2D/H2D (zweryfikowane na żywo dla AMS; dla szpuli
  /// przyjęte wg ustaleń): `tray_now` ≥ 254 oznacza szpulę zewnętrzną — wtedy
  /// liczy się szpula karmiąca [activeExtruder] (254→ekstruder 0, 255→1).
  /// Dla `tray_now` < 254 to slot AMS o numerze globalnym `jednostka*4 + slot`.
  AmsTray? get activeTray {
    final now = trayNow;
    if (now == null) return null;

    // Szpula zewnętrzna: wybór po aktywnym ekstruderze, nie po samym id
    // (na dwudyszowej `tray_now` nie rozróżnia obu szpul jednoznacznie).
    // Mapowanie szpula→ekstruder jest odwrotne do id (patrz extruderForExternal).
    if (now >= 254) {
      final spools = externalSpools;
      if (spools.isEmpty) return null;
      final ext = activeExtruder ?? 0;
      for (final t in spools) {
        if (extruderForExternal(t.id) == ext) return t;
      }
      // Fallback: dopasowanie po id, a w ostateczności pierwsza szpula.
      return spools.firstWhere(
        (t) => t.id == now,
        orElse: () => spools.first,
      );
    }

    // Slot AMS: numer globalny = indeks jednostki * 4 + numer slotu.
    final units = ams ?? const [];
    for (var u = 0; u < units.length; u++) {
      for (final t in units[u].trays ?? const []) {
        if (u * 4 + (t.id ?? -1) == now) return t;
      }
    }
    return null;
  }

  /// Czy są jakiekolwiek dane do rozwinięcia w sekcji szczegółów
  /// (AMS, szpula zewnętrzna lub metadane łączności/modelu).
  bool get hasDetails =>
      (ams != null && ams!.isNotEmpty) ||
      (vtTray != null && vtTray!.isNotEmpty) ||
      model != null ||
      wifiSignal != null ||
      doorOpen != null;
}

/// Pojedyncza jednostka AMS: wilgotność, temperatura i sloty (tace).
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class AmsUnit {
  const AmsUnit({this.id, this.humidity, this.temp, this.trays, this.isAmsHt});

  factory AmsUnit.fromJson(Map<String, dynamic> json) =>
      _$AmsUnitFromJson(json);

  @JsonKey(fromJson: _toIntOrNull)
  final int? id;

  /// Czy to moduł AMS-HT (high-temperature) — rozróżniany w treści powiadomień
  /// o wilgotności/temperaturze. Klucz serwera `is_ams_ht`.
  final bool? isAmsHt;

  /// Wilgotność wewnątrz AMS w procentach (jeśli moduł ją mierzy).
  @JsonKey(fromJson: _toIntOrNull)
  final int? humidity;

  /// Temperatura wewnątrz AMS w °C (serwer bywa, że podaje jako string).
  @JsonKey(fromJson: _toDoubleOrNull)
  final double? temp;

  /// Sloty na filament. Klucz serwera to `tray`.
  @JsonKey(name: 'tray', fromJson: _toTrayListOrNull)
  final List<AmsTray>? trays;
}

/// Slot filamentu (taca AMS lub szpula zewnętrzna). Tylko pola potrzebne
/// do chipów — kolor, materiał i pozostała ilość; reszta ignorowana.
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class AmsTray {
  const AmsTray({
    this.id,
    this.trayColor,
    this.trayType,
    this.traySubBrands,
    this.remain,
  });

  factory AmsTray.fromJson(Map<String, dynamic> json) =>
      _$AmsTrayFromJson(json);

  @JsonKey(fromJson: _toIntOrNull)
  final int? id;

  /// Kolor filamentu jako hex RRGGBBAA (np. „F55A74FF"); null/puste = brak.
  final String? trayColor;

  /// Typ materiału (np. „PLA", „PETG", „TPU"); null/puste = pusty slot.
  final String? trayType;

  /// Wariant marki (np. „PLA Basic"), gdy serwer poda.
  final String? traySubBrands;

  /// Pozostała ilość w procentach (0–100); -1 = nieznana (bez tagu RFID).
  @JsonKey(fromJson: _toIntOrNull)
  final int? remain;

  /// Pusty slot: brak materiału lub w pełni przezroczysty kolor (alpha 00).
  bool get isEmpty {
    final type = trayType?.trim();
    if (type == null || type.isEmpty) return true;
    final color = trayColor;
    return color != null && color.length == 8 && color.endsWith('00');
  }

  /// Etykieta materiału do chipa (wariant marki, gdy jest sensowny).
  String? get materialLabel {
    final sub = traySubBrands?.trim();
    if (sub != null && sub.isNotEmpty) return sub;
    final type = trayType?.trim();
    return (type == null || type.isEmpty) ? null : type;
  }
}

/// Pojedynczy błąd HMS drukarki z `hms_errors`. Serwer raportuje go w dwóch
/// kształtach zależnie od wersji: `{code, attr, module, severity}` albo
/// `{code, message}` — dlatego wszystko nullable, a `code` normalizujemy do
/// stringa (bywa hex-stringiem albo liczbą).
@JsonSerializable(createToJson: false, fieldRename: FieldRename.snake)
class HmsError {
  const HmsError({
    this.code,
    this.message,
    this.severity,
    this.attr,
    this.module,
  });

  factory HmsError.fromJson(Map<String, dynamic> json) =>
      _$HmsErrorFromJson(json);

  @JsonKey(fromJson: _toCodeStringOrNull)
  final String? code;

  final String? message;

  @JsonKey(fromJson: _toIntOrNull)
  final int? severity;

  /// Atrybut HMS (górne 32 bity pełnego kodu). Z firmware Bambu.
  @JsonKey(fromJson: _toIntOrNull)
  final int? attr;

  /// Numer modułu/podsystemu (np. 5=płyta główna, 7=AMS) — patrz `hmsModuleKey`.
  @JsonKey(fromJson: _toIntOrNull)
  final int? module;

  /// Numeryczna wartość `code` (firmware podaje hex-stringiem „0x20070"
  /// albo liczbą); null gdy `code` jest już w formie kanonicznej z separatorami.
  int? get _codeInt {
    final c = code?.trim();
    if (c == null || c.isEmpty) return null;
    if (c.contains('_') || c.contains('-')) return null;
    final hex = c.toLowerCase().startsWith('0x') ? c.substring(2) : c;
    return int.tryParse(hex, radix: 16);
  }

  /// Pełny 16-hex kod HMS (`attr`+`code`) używany przez katalog Bambu, np.
  /// `0500060000020070`. null gdy brak `attr` lub `code` nie jest liczbą.
  String? get ecode {
    final a = attr;
    final c = _codeInt;
    if (a == null || c == null) return null;
    return (a.toRadixString(16).padLeft(8, '0') +
            c.toRadixString(16).padLeft(8, '0'))
        .toUpperCase();
  }

  /// Czytelny kanoniczny kod z myślnikami: `0500-0600-0002-0070`. Fallback na
  /// surowy `code` (po normalizacji separatorów), gdy nie da się złożyć pełnego.
  String get displayCode {
    final e = ecode;
    if (e != null && e.length == 16) {
      return '${e.substring(0, 4)}-${e.substring(4, 8)}'
          '-${e.substring(8, 12)}-${e.substring(12, 16)}';
    }
    final c = code?.trim();
    if (c == null || c.isEmpty) return '?';
    return c.replaceAll('_', '-').replaceAll(' ', '-').toUpperCase();
  }
}

/// Kod HMS przychodzi raz jako string (`"0x20070"`, `"0500_0100"`), raz jako
/// liczba — sprowadzamy do stringa, by dało się dedupować zbiorami.
String? _toCodeStringOrNull(dynamic value) => switch (value) {
      String s when s.trim().isNotEmpty => s.trim(),
      num n => n.toString(),
      _ => null,
    };

/// Lista błędów HMS — elementy nie-mapowe pomijamy (parsowanie defensywne).
List<HmsError>? _toHmsListOrNull(dynamic value) {
  if (value is! List) return null;
  return [
    for (final e in value)
      if (e is Map) HmsError.fromJson(Map<String, dynamic>.from(e)),
  ];
}

double? _toDoubleOrNull(dynamic value) => switch (value) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };

int? _toIntOrNull(dynamic value) => switch (value) {
      num n => n.toInt(),
      String s => int.tryParse(s),
      _ => null,
    };

Map<String, double>? _toTemperaturesOrNull(dynamic value) {
  if (value is! Map) return null;
  final out = <String, double>{};
  for (final entry in value.entries) {
    final v = _toDoubleOrNull(entry.value);
    if (v != null) out[entry.key.toString()] = v;
  }
  return out;
}

/// Mapa `id AMS → ekstruder` z kluczami-stringami (`{"0":1}`) → `{0:1}`.
Map<int, int>? _toExtruderMapOrNull(dynamic value) {
  if (value is! Map) return null;
  final out = <int, int>{};
  for (final entry in value.entries) {
    final k = _toIntOrNull(entry.key);
    final v = _toIntOrNull(entry.value);
    if (k != null && v != null) out[k] = v;
  }
  return out;
}

/// Lista jednostek AMS — elementy nie-mapowe pomijamy (parsowanie defensywne).
List<AmsUnit>? _toAmsListOrNull(dynamic value) {
  if (value is! List) return null;
  return [
    for (final e in value)
      if (e is Map) AmsUnit.fromJson(Map<String, dynamic>.from(e)),
  ];
}

/// Lista slotów filamentu (tace AMS lub szpule) — elementy nie-mapowe pomijamy.
List<AmsTray>? _toTrayListOrNull(dynamic value) {
  if (value is! List) return null;
  return [
    for (final e in value)
      if (e is Map) AmsTray.fromJson(Map<String, dynamic>.from(e)),
  ];
}
