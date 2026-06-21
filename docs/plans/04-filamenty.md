# Plan: Filamenty (magazyn szpul + katalog) — bambuddy-mobile

Kontrakt: bambuddy v0.2.4.4 (`/api/v1`). Dotyczy dwóch obszarów API: **Inventory**
(`/inventory/*`, 43 endpointy) i **Filament Catalog** (`/filament-catalog/*`, 8).

## Decyzje (ustalone z userem 2026-06-20)

- **Dwa backendy magazynu za wspólnym interfejsem.** User korzysta z **natywnego
  `/inventory`**, ale aplikacja ma być przygotowana, by działać też na **Spoolman**
  (`/spoolman/inventory/*`). Wzorzec swap-owalny jak `BackgroundMonitor`/
  `backgroundMonitorProvider` — UI i providery nie wiedzą, który backend działa.
- **Domyślny backend = natywny.** Spoolman to drop-in (inny kształt JSON →
  warstwa mapperów do wspólnego modelu domenowego).
- **Najpierw widok szpul (read-only).** Zarządzanie (CRUD, przypisania AMS,
  katalog) w kolejnej fazie.
- Brak WS dla inventory (jak smart-plugs/maintenance) → fetch przy wejściu +
  pull-to-refresh; bez agresywnego pollingu (stan zmienia się wolno).

## Dwa byty „filamentów"

| Byt | API | Czym jest |
|---|---|---|
| **Szpule (inventory)** | `/inventory/spools/*`, `/inventory/assignments/*` | Fizyczny magazyn: materiał, kolor, marka, waga/zużycie, koszt/kg, lokalizacja, próg low-stock, archiwizacja, historia zużycia, tag NFC, **przypisanie do slotu AMS** |
| **Katalog filamentów** | `/filament-catalog/*` | Definicje/profile typów: `name`,`type`,`brand`,`color_hex`,`cost_per_kg`, temperatury, gęstość + `calculate-cost`, `seed-defaults` |
| Katalogi pomocnicze | `/inventory/catalog` (wagi rdzeni), `/inventory/colors` (mapa/lookup/search/sync) | Dane referencyjne dla formularzy |
| Spoolman mirror | `/spoolman/inventory/*` | Alternatywny backend |

### Kluczowe pola `SpoolResponse` (natywny)

`material*`, `subtype`, `color_name`, `rgba` (swatch), `brand`, `label_weight`,
`weight_used`, `weight_used_baseline`, `cost_per_kg`, `low_stock_threshold_pct`,
`storage_location`, `archived_at`, `tag_uid`, `note`, `nozzle_temp_min/max`,
`category`, `last_used`, `k_profiles[]`, `id*`, `created_at*`, `updated_at*`.

Wyliczane: `remainingWeight = label_weight − weight_used`,
`remainingPct = remaining / label_weight`,
`isLowStock = remainingPct*100 ≤ low_stock_threshold_pct`.

### Różnica Spoolman

`GET /spoolman/inventory/spools` zwraca **luźny `object` (additionalProperties)** —
passthrough Spoolmana, nie typowany w openapi. `SpoolmanSlotAssignmentEnriched`
ma `spoolman_spool_id` zamiast `spool_id`, brak osadzonego obiektu szpuli.
Dlatego mapper Spoolmana jest bardziej defensywny (czyta luźną mapę).

## Architektura — abstrakcja backendu

```
UI (zakładka Filamenty)
  → providery (Riverpod)
    → InventoryRepository  (fasada)
      → SpoolInventorySource  (interfejs)
         ├── NativeInventorySource   → /inventory/*        (SpoolResponse)
         └── SpoolmanInventorySource → /spoolman/inventory/* (luźna mapa)
```

```dart
abstract class SpoolInventorySource {
  Future<List<Spool>> fetchSpools({bool includeArchived = false});
  Future<Spool> fetchSpool(int id);
  Future<List<SpoolAssignment>> fetchAssignments();
  // Faza 2: create/update/delete/archive/restore/resetUsage/assign/unassign…
}
```

- Wspólny **domenowy `Spool`** (znormalizowany, defensywny — wzorzec `Archive`/
  `SmartPlug`); mappery per backend tłumaczą surowy JSON.
- `inventoryBackendProvider` (ustawienie, domyślnie `native`) wybiera źródło;
  `inventorySourceProvider` buduje odpowiednią impl na współdzielonym Dio.
- Reuse `AuthInterceptor` + `mapDioException`; 403 → `forbidden` (bez wylogowania,
  jak M4/smart-plugs).

## Fazy

> **Status (2026-06-21):** Faza 0, Faza 1 i **Faza 2 — CRUD szpul** zrobione +
> zweryfikowane na żywo (AVD pixel35, realny serwer). Niezacommitowane (working
> tree). Pozostało w Fazie 2: przypisania AMS, katalog filamentów (+ świadomie
> odłożone Slicer Preset i PA Profile — patrz niżej).

### ✅ Faza 0 — fundament (ZROBIONE)
- [x] `endpoints.dart`: `inventorySpools`, `inventorySpool(id)`, `inventoryAssignments`
  (+ spoolmanowe odpowiedniki), `inventorySpoolUsage(id)`, `filamentCatalog`.
- [x] Modele: domenowy `Spool` + `SpoolAssignment` + `SpoolUsageEntry` +
  `SpoolKProfile`; gettery `remainingWeight/remainingFraction/isLowStock/isArchived`.
  Mappery per backend (`fromNative`/`fromSpoolman`). **Uwaga:** pisane RĘCZNIE
  i defensywnie, nie przez `json_serializable` (dwa luźne backendy → tolerancyjne
  parsowanie kluczy).
- [x] `SpoolInventorySource` + `NativeInventorySource` + `SpoolmanInventorySource`;
  `InventoryRepository` (cienka fasada).
- [x] Providery: `inventoryBackendProvider` (SharedPreferences, default `native`),
  `inventorySourceProvider`, `inventoryRepositoryProvider`, `inventoryProvider`
  (szpule + przypisania), `inventoryQueryProvider`, `inventoryFiltersProvider`,
  `spoolUsageProvider`. Testy modeli (`test/core/models/inventory_test.dart`).

### ✅ Faza 1 — widok szpul (read-only) (ZROBIONE)
- [x] **5. zakładka** dolnej belki „Filamenty" (`StatefulShellRoute`, `root_scaffold`).
- [x] Lista: swatch `rgba` + materiał/marka, pasek pozostałej wagi + chip low-stock,
  lokalizacja, etykieta slotu AMS/ekstrudera. Pull-to-refresh.
- [x] Szukanie (materiał/marka/kolor/lokalizacja) + **arkusz filtrów** (kompaktowy
  przycisk z plakietką liczby filtrów): Status (Aktywne/Archiwum), Zapas
  (Wszystkie/Mało), Materiał, Marka, Lokalizacja — wszystko po stronie klienta.
- [x] Sheet szczegółów: pełne dane, historia zużycia (`/spools/{id}/usage`), slot
  AMS / ekstruder (z assignments), k-profiles.
- [x] Lokalizacja stringów (`app_en.arb`/`app_pl.arb` + gen-l10n), nawigacja, ikona.
- [x] **Ponad plan:** plakietki rodzaju filamentu (PLA/PETG/TPU…) na liście;
  sortowanie szpul załadowanych (AMS/external) na górę.

### Faza 2 — zarządzanie

#### ✅ CRUD szpul (ZROBIONE, zweryfikowane na żywo)
- [x] Szpula: dodaj/edytuj/usuń/archiwizuj/przywróć, reset zużycia, korekta wagi
  (pole „Pozostała waga" steruje `weight_used = etykieta − pozostało`), próg
  low-stock, lokalizacja, kategoria. Write-endpointy `/inventory/spools*` (POST/
  PATCH/DELETE + `/archive`/`/restore`/`/reset-usage`) + spoolmanowe odpowiedniki.
- [x] Mutacje na `inventoryProvider` przeładowują listę; akcje (edytuj/reset/
  archiwizuj/przywróć/usuń) w sheecie szczegółów + FAB „Dodaj szpulę".
  Destrukcyjne (usuń, reset) z dialogiem potwierdzenia.
- [x] **Formularz `_SpoolFormSheet` w układzie bambuddy „Add Spool"** — sekcje
  FILAMENT / KOLOR / DODATKOWE: dropdowny Materiał/Marka/Wariant (opcje scalane
  z `/filament-catalog` + istniejących szpul + stałe popularne), **picker
  kolorów** z `/inventory/colors` (siatka „Popularne kolory" `is_default` +
  szukajka, wybór wypełnia hex/nazwę/gradient/efekt), **katalog wag rdzeni** z
  `/inventory/catalog` (Empty Spool Weight → `core_weight`+`core_weight_catalog_id`),
  Zmierzona waga (`last_scale_weight`), Dodatkowe kolory (`extra_colors`),
  Efekt (`effect_type`).
- [x] Nowe modele `inventory_reference.dart` (`CoreWeightEntry`/`ColorEntry`/
  `FilamentPreset`) + providery referencyjne (`coreWeightsProvider`/
  `colorCatalogProvider`/`filamentPresetsProvider`/`materialOptionsProvider`/
  `brandOptionsProvider`/`subtypeOptionsProvider`). Dane referencyjne degradują
  się do pustych list (formularz dopuszcza wpis ręczny; Spoolman zwraca puste).
- [x] ID szpuli jako `#id` (tekst pomocniczy w wierszu listy).
- [x] **HACZYK 422:** `SpoolCreate.rgba` = `^[0-9A-Fa-f]{8}$` (8 hex, bez `#`) →
  `normalizeRgba` (`#RRGGBB`→`RRGGBBAA`, dokłada `FF`); `low_stock_threshold_pct`
  klamrowany 1..99. Body POST może być podzbiorem pól (reszta = defaulty serwera).

#### Przypisania AMS (DO ZROBIENIA)
- Przypisz/odepnij szpulę do slotu AMS (`POST /inventory/assignments` body
  `SpoolAssignmentCreate {spool_id,printer_id,ams_id,tray_id}`,
  `DELETE /inventory/assignments/{printer_id}/{ams_id}/{tray_id}`) →
  integracja: czipy AMS na dashboardzie (M3) pokazują nazwę/kolor + dokładną
  pozostałą wagę przypisanej szpuli; wzbogacony próg `lowFilament`
  ([[configurable-notifications]]).

#### Katalog filamentów + reszta (DO ZROBIENIA)
- Katalog filamentów: CRUD + `calculate-cost` + `seed-defaults`.
- „Zsynchronizuj wagi z AMS" (`sync-ams-weights`). Lista zakupów / sync kolorów —
  opcjonalnie. Link tagu NFC (`PATCH /spools/{id}/link-tag`).

#### Świadomie ODŁOŻONE (wymagają cloud/printer — osobna faza)
- **Slicer Preset** (`GET /slicer/presets` → `UnifiedPresetsResponse`) — złożona
  integracja cloud, prefill materiału/marki/temp/koloru z presetu.
- **Zakładka PA Profile** — k-profile per drukarka (`PUT /inventory/spools/{id}/
  k-profiles` body `SpoolKProfileBase[]`); zwykle synchronizowane z drukarki, nie
  wpisywane ręcznie, a przy nowej szpuli brak `id`.

## Do zweryfikowania na żywo (verify-on-phone-before-commit)
- [x] Format `rgba` — hex8 `RRGGBBAA` (`#RRGGBB` też obsłużone). Swatch OK.
- [x] Czy assignment realnie mapuje się na sloty/ekstrudery z dashboardu (M3) —
  TAK. Szpule zewnętrzne mają **obie `ams_id=255`**, ekstruder rozróżnia `tray_id`
  (0 → lewy, 1 → prawy). Zweryfikowane fizycznie na X2D. (To inna reprezentacja
  niż MQTT `vtTray` 254/255 z dashboardu — patrz `SpoolAssignment.extruder`.)
- [x] Który backend na serwerze usera — **natywny** (`/inventory/*`).
- [x] Zapisy (create/update/delete/archive/restore/reset-usage) przechodzą na
  bieżącym kluczu API — **brak 403**. Jedyny napotkany błąd to **422** (walidacja
  `rgba`/`low_stock`, nie uprawnienia). `X-API-Key` dokładany przez `AuthInterceptor`.
- Inne ustalenia: nazwy wydruków w historii zużycia są URL-encoded (`%20`) i tak
  ZOSTAJĄ (taka jest nazwa pliku na serwerze); `cost_per_kg` jako `N.NN/kg`.
