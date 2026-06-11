# bambuddy-mobile — plany

Natywna aplikacja mobilna (Flutter, Android) dla [BambuBuddy](https://github.com/maziggy/bambuddy) — self-hosted menedżera drukarek Bambu Lab, dostępnego dziś tylko jako PWA.

Dokumenty (stan badania: 2026-06-11, bambuddy v0.2.4.6):

1. [01-analiza-wykonalnosci.md](01-analiza-wykonalnosci.md) — czym jest bambuddy, jego API, porównanie Kotlin vs Flutter, aplikacje referencyjne, licencje
2. [02-plan-implementacji.md](02-plan-implementacji.md) — architektura, pakiety, projekt WebSocketa, milestone'y M0–M7, ryzyka, plan nauki
3. [03-srodowisko-fedora.md](03-srodowisko-fedora.md) — konfiguracja środowiska Flutter/Android na Fedorze

Decyzje: **Flutter** · zakres v1: monitoring + sterowanie + kamera + kolejka + archiwum + powiadomienia · push w tle przez **ntfy/UnifiedPush** · licencja docelowa **AGPL-3.0** · szacunek: ~4–6 miesięcy po godzinach.
