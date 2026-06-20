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

### Faza 0 — fundament
- `endpoints.dart`: `inventorySpools`, `inventorySpool(id)`, `inventoryAssignments`
  (+ spoolmanowe odpowiedniki), `inventorySpoolUsage(id)`, później reszta.
- Modele: domenowy `Spool` + `SpoolAssignment` (json_serializable, defensywne);
  gettery `remainingWeight/remainingPct/isLowStock`. DTO-mappery per backend.
- `SpoolInventorySource` + `NativeInventorySource` + `SpoolmanInventorySource`;
  `InventoryRepository` (cienka fasada).
- Providery + override w testach (inertne, jak `_InertSmartPlugsNotifier`).

### Faza 1 — widok szpul (read-only) ← DOWOZIMY NAJPIERW
- **5. zakładka** dolnej belki „Filamenty" (`StatefulShellRoute`, `root_scaffold`).
- Lista: swatch `rgba` + materiał/marka, pasek pozostałej wagi + chip low-stock,
  lokalizacja. Filtr/szukaj (materiał/marka/kolor), przełącznik „zarchiwizowane".
  Pull-to-refresh.
- Sheet szczegółów: pełne dane, historia zużycia (`/spools/{id}/usage`), slot AMS
  (z assignments), k-profiles.
- Lokalizacja stringów (`app_en.arb`/`app_pl.arb`), nawigacja, ikona zakładki.

### Faza 2 — zarządzanie (później)
- Szpula: dodaj/edytuj/usuń/archiwizuj/przywróć, reset zużycia, korekta wagi,
  próg low-stock, lokalizacja, link tagu NFC.
- Przypisz/odepnij szpulę do slotu AMS (`POST/DELETE /inventory/assignments`) →
  integracja: czipy AMS na dashboardzie (M3) pokazują nazwę/kolor + dokładną
  pozostałą wagę przypisanej szpuli; wzbogacony próg `lowFilament`
  ([[configurable-notifications]]).
- Katalog filamentów: CRUD + `calculate-cost` + `seed-defaults`.
- „Zsynchronizuj wagi z AMS" (`sync-ams-weights`). Lista zakupów / sync kolorów —
  opcjonalnie.

## Do zweryfikowania na żywo (verify-on-phone-before-commit)
- Format `rgba` (hex8? `rgba(...)`?) — do swatcha.
- Jakie uprawnienie klucza API wymagają zapisy (403) — istotne dla Fazy 2.
- Czy assignment realnie mapuje się na `tray_uuid`/sloty z dashboardu (M3).
- Który backend zwraca dane na serwerze usera (autodetekt vs ustawienie).
