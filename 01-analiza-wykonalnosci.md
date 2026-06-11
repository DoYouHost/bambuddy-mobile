# Analiza wykonalności: natywna aplikacja mobilna dla BambuBuddy

*Stan badania: 2026-06-11. Wersja serwera w dniu analizy: bambuddy v0.2.4.6.*

## Werdykt

**Stworzenie natywnej aplikacji na Androida jest umiarkowanie łatwe.** Serwer BambuBuddy wystawia kompletne, dobrze udokumentowane API, a cała trudna integracja z drukarkami (MQTT, RTSP, FTPS) jest po stronie serwera. Aplikacja mobilna to „cienki klient": JSON przez HTTP, WebSocket i strumień MJPEG. Istniejący natywny klient iOS (BamPocket) dowodzi w praktyce, że API nadaje się do konsumpcji. **Na Androida odpowiednika nie ma — jest wyraźna nisza.**

Wybrany stack: **Flutter** (uzasadnienie w sekcji „Kotlin vs Flutter").

## Czym jest BambuBuddy

[BambuBuddy](https://github.com/maziggy/bambuddy) — self-hosted, bezchmurowe centrum zarządzania drukarkami Bambu Lab („Your Bambu Lab. No Cloud. Your Rules."). Skaluje się od pojedynczej A1 po farmy 40 drukarek. Projekt bardzo aktywny: utworzony 2025-11-28, ~2000 gwiazdek, 246 forków, ostatni push w dniu analizy. Licencja **AGPL-3.0**.

**Architektura:**
- **Backend**: Python 3.10+, **FastAPI** + SQLAlchemy (SQLite domyślnie, opcjonalnie PostgreSQL), uvicorn
- **Frontend**: React 19 + TypeScript, Vite, Tailwind, TanStack Query
- **Wdrożenie**: Docker (obrazy amd64/arm64, `network_mode: host` dla wykrywania SSDP, port 8000), instalator Windows, instalacja ręczna
- **Komunikacja z drukarkami**: MQTT po TLS (tryb LAN/Developer — bez chmury Bambu), FTPS do transferu plików, SSDP do wykrywania

## API serwera — wszystko, czego potrzebuje klient mobilny

| Element | Szczegóły |
|---|---|
| REST | 200+ endpointów pod `/api/v1` (~53 routery: printers, print_queue, archives, camera, auth, api_keys…) |
| OpenAPI | Spec pod `/openapi.json`, Swagger UI pod `/docs` (domyślne FastAPI) |
| WebSocket | `/api/v1/ws` — serwer pcha `printer_status` dla wszystkich drukarek; klient może słać `{"type":"ping"}` i `{"type":"get_status","printer_id":...}`; przy włączonym auth wymagany `?token=` z `POST /api/v1/auth/ws-token` (60 min), błędny token → kod zamknięcia 4401 |
| Auth | **Opcjonalny** (można całkiem wyłączyć). JWT HS256 Bearer (24 h, revokacja po jti) lub klucze API z prefiksem `bb_` (nagłówek `X-API-Key` lub Bearer) ze scope'ami: `can_read_status`, `can_queue`, `can_control_printer`… Dodatkowo 2FA/OIDC/LDAP po stronie serwera |
| Kamera | **MJPEG** `multipart/x-mixed-replace; boundary=frame` pod `GET /api/v1/printers/{id}/camera/stream`; snapshot pod `/camera/snapshot`; tokeny strumienia z `POST /camera/stream-token` (60 min, `?token=` w query). Serwer sam transkoduje protokoły Bambu (A1/P1: binarny protokół port 6000; X1/H2/P2: RTSP→ffmpeg→MJPEG) i rozgłasza jeden strumień do wielu widzów |
| Powiadomienia | Wbudowane integracje: **ntfy**, Telegram, Discord, Pushover, WhatsApp, e-mail, webhooki, Home Assistant |

## Dlaczego PWA nie wystarcza (uzasadnienie projektu)

- **Brak działającego Web Push**: service worker ma handler `push`, ale nigdy nie woła `pushManager.subscribe()`, a backend nie ma endpointów VAPID — powiadomienia są martwe; użytkownicy muszą używać ntfy/Telegram/Pushover
- Instalacja wymaga HTTPS (Chrome/Android), a serwery domowe to zwykle `http://` po LAN; na iOS tylko „Dodaj do ekranu głównego" w Safari
- Powtarzające się problemy UX dotykowego (issues #1583, #1404, #1669 — małe cele dotykowe)
- Dokumentacja projektu wprost: „Bambuddy is web-based only"

## Kotlin vs Flutter — porównanie

| Kryterium | Kotlin + Compose | Flutter | Wniosek |
|---|---|---|---|
| Nakład pracy (Android) | ~4–8 tyg. MVP | ~4–8 tyg. MVP | Remis |
| WebSocket / real-time | OkHttp/Ktor + Flow — wzorowe | `web_socket_channel` + Streams — dojrzałe (Mobileraker to potwierdza) | Remis |
| MJPEG | własny dekoder ~100 linii (Media3 NIE wspiera MJPEG) | `flutter_mjpeg` lub własny dekoder ~100 linii | Remis |
| RTSP/WebRTC (przyszłość, kamery zewn.) | Media3 RTSP — natywnie | `flutter_vlc_player` / `flutter_webrtc` | Lekka przewaga Kotlin |
| Push self-hosted (ntfy/UnifiedPush) | konektor natywny, apka ntfy jest w Kotlinie | oficjalny pakiet `unifiedpush` (zweryfikowany wydawca) | Lekka przewaga Kotlin, Flutter w pełni zdolny |
| Ograniczenia tła Androida | identyczne (problem OS, nie frameworka) | identyczne | Remis |
| **Opcja iOS** | osobna aplikacja lub KMP: +30–50% pracy | **+10–15% pracy** | **Wyraźna przewaga Flutter** |
| Wydajność | natywna | Impeller, 60/120 Hz; binarka +10–20 MB, nieco więcej RAM | Bez znaczenia praktycznego dla cienkiego klienta |

**Decyzja: Flutter.** Warunek użytkownika („Flutter tylko jeśli nie jest dużo bardziej wymagający od Kotlina") jest spełniony — nakład porównywalny, a droga na iOS zostaje otwarta. Jedyna uczciwa uwaga: push self-hosted na iOS i tak będzie wymagał przekaźnika APNs — to ograniczenie platformy Apple, nie Fluttera.

### Wydajność — czy obie technologie udźwigną projekt?

Tak, z dużym zapasem. Aplikacja robi trzy rzeczy: parsuje JSON (kilka KB/s), dekoduje MJPEG (5–30 klatek JPEG/s — w obu technologiach dekodują kodeki platformowe, nie interpretowany kod) i renderuje UI (chleb powszedni Compose i Impellera). Dwa miejsca wymagające uwagi w **obu** technologiach:
- **siatka wielu kamer** (farma) → w siatce snapshoty co kilka sekund, pełny strumień dopiero w szczegółach drukarki;
- **podgląd 3D G-code** (web używa Three.js) → poza zakresem v1.

## Aplikacje referencyjne

| Aplikacja | Nisza | Stack | Licencja / użyteczność |
|---|---|---|---|
| [BamPocket](https://github.com/clabeuhtegrite/bambuddy-pocket) | klient iOS **dla bambuddy** | SwiftUI | **AGPL — można czytać i adaptować z atrybucją**; żywy dowód konsumowalności API |
| [Mobileraker](https://github.com/Clon1998/mobileraker) | Klipper/Moonraker | **Flutter** + Riverpod | licencja non-commercial, **nie wolno kopiować kodu** — tylko inspiracja architektoniczna |
| [OctoApp](https://gitlab.com/realoctoapp/octoapp) | OctoPrint/Klipper | Kotlin → KMP | AGPL — dowód, że ścieżka Kotlin/KMP też działa (nie wybrana) |
| Bambu Handy | oficjalna apka Bambu | zamknięta, uwiązana do chmury | jej słabości to racja bytu tego projektu |

## Licencja

Aplikacja będzie na **AGPL-3.0** — spójnie z bambuddy i BamPocket; pozwala legalnie czerpać z obu. Wszystkie planowane pakiety Flutter są na licencjach permisywnych (BSD/MIT/Apache) — zgodne z AGPL.

## Źródła

- Repo: https://github.com/maziggy/bambuddy · wiki: https://wiki.bambuddy.cool/ (mobile: https://wiki.bambuddy.cool/getting-started/mobile/)
- Kod serwera (raw): `backend/app/main.py`, `backend/app/core/{auth,config}.py`, `backend/app/api/routes/{websocket,camera,printers,api_keys}.py`, `frontend/public/{manifest.json,sw.js}`
- BamPocket: https://github.com/clabeuhtegrite/bambuddy-pocket
- Mobileraker: https://github.com/Clon1998/mobileraker · OctoApp: https://gitlab.com/realoctoapp/octoapp
- UnifiedPush: https://unifiedpush.org/ · pakiet Flutter: https://pub.dev/packages/unifiedpush · ntfy: https://docs.ntfy.sh/subscribe/phone/
- Ograniczenia tła Android 15: https://developer.android.com/about/versions/15/changes/foreground-service-types
- Media3 RTSP (brak MJPEG): https://developer.android.com/media/media3/exoplayer/rtsp · flutter_mjpeg: https://pub.dev/packages/flutter_mjpeg
