# Google Play Store Listing — Bambuddy

Copy-paste source for the Play Console "Main store listing" page.
Default language: **English (en-US)**. Polish (pl-PL) provided as an optional
additional translation.

---

## App name (max 30 chars)

```
Bambuddy
```

## Short description (max 80 chars)

```
Unofficial companion for your self-hosted bambuddy Bambu Lab printer manager.
```

## Full description (max 4000 chars)

```
Bambuddy mobile is an unofficial, open-source Android companion for a self-hosted
"bambuddy" server that manages your Bambu Lab 3D printers. It is NOT an official
Bambu Lab app and is not affiliated with or endorsed by Bambu Lab.

IMPORTANT: Bambuddy mobile requires your own running bambuddy server. It does not connect
to Bambu Lab cloud on its own and will not work without a server to point it at.

MONITOR YOUR PRINTS
• Live printer status: state, progress, layer, ETA and temperatures
• Persistent notification during a print so you always know what's happening
• Configurable alerts for print events and hardware (HMS) errors

CONTROL YOUR PRINTERS
• Pause, resume and stop prints
• Clear the plate and start the next job in the queue
• Reorder and manage the print queue

MANAGE FILAMENT & HARDWARE
• Track your spool inventory and assign spools to AMS slots
• Scan spool QR codes with the camera to jump straight to a spool
• Smart-plug control and power monitoring
• Maintenance tracker with reminders

MORE
• Print archive and statistics
• Projects, plates and parts overview
• Home-screen widget with printer status and a quick spool-scan shortcut
• Wear OS companion: check status and control prints from your watch

PRIVACY
Bambuddy mobile talks only to the bambuddy server you configure. There is no analytics,
no advertising and no cloud service. Your credentials are stored in encrypted,
Keystore-backed storage on your device and are only ever sent to your own server.

OPEN SOURCE
Bambuddy mobile is free software under the AGPL-3.0 license.
Source: https://github.com/DoYouHost/bambuddy-mobile

"Bambu Lab" and "Bambu" are trademarks of their respective owner. Bambuddy mobile is an
independent, community-built companion app and is not affiliated with Bambu Lab.
```

---

## Polish translation (pl-PL) — optional

### Short description (max 80 chars)
```
Nieoficjalny towarzysz dla Twojego self-hostowanego menedżera drukarek Bambu Lab.
```

### Full description
```
Bambuddy mobile to nieoficjalna aplikacja towarzysząca (open source) dla self-hostowanego
serwera „bambuddy", który zarządza drukarkami 3D Bambu Lab. To NIE jest oficjalna
aplikacja Bambu Lab i nie jest z Bambu Lab powiązana ani przez nią wspierana.

WAŻNE: Bambuddy mobile wymaga własnego, działającego serwera bambuddy. Bez serwera, do
którego ją skierujesz, aplikacja nie działa.

MONITOROWANIE
• Status drukarki na żywo: stan, postęp, warstwa, ETA i temperatury
• Stałe powiadomienie w trakcie wydruku
• Konfigurowalne alerty o zdarzeniach i błędach sprzętowych (HMS)

STEROWANIE
• Pauza, wznów, zatrzymaj wydruk
• Zwolnij stół i uruchom kolejne zadanie z kolejki
• Zarządzanie kolejką wydruków

FILAMENT I SPRZĘT
• Magazyn szpul i przypisywanie do slotów AMS
• Skaner QR szpul (aparat)
• Sterowanie gniazdkami smart i podgląd mocy
• Śledzenie konserwacji z przypomnieniami

WIĘCEJ
• Archiwum i statystyki wydruków, projekty
• Widget na ekran główny
• Wersja na Wear OS

PRYWATNOŚĆ
Bambuddy mobile łączy się wyłącznie z serwerem bambuddy, który skonfigurujesz. Brak
analityki, reklam i chmury. Dane logowania trzymane są w szyfrowanym
magazynie (Keystore) na urządzeniu.

OPEN SOURCE (AGPL-3.0):
https://github.com/DoYouHost/bambuddy-mobile

„Bambu Lab" i „Bambu" to znaki towarowe ich właściciela. Bambuddy mobile jest niezależną
aplikacją społecznościową, niepowiązaną z Bambu Lab.
```

---

## Categorization & contact (Store settings)

- **App category:** Tools (or House & Home)
- **Tags:** 3D printing, printer, utility
- **Email:** info.doyouhost@gmail.com
- **Website:** https://doyouhost.github.io/bambuddy-mobile/ (landing page; GitHub Pages)
- **Privacy policy URL:** https://doyouhost.github.io/bambuddy-mobile/privacy.html
  (deployed from `site/` on master by `.github/workflows/pages.yml`; policy text also
  kept as Markdown in `docs/privacy-policy.md`)

> **Both URLs changed in July 2026** when the project moved off Codeberg. They must be
> updated **in the Play Console** — the app listing still carries the old
> `doyouhost.codeberg.page` addresses, and a privacy policy URL that stops resolving is
> a policy problem on a live listing, not a broken link. Keep the Codeberg Pages site up
> until the Console shows the new ones.

The `applicationId` stays `page.codeberg.morganmlgman.bambuddy_mobile` forever: it is the
identity of the Play listing and cannot be changed without publishing a different app.
Its `codeberg` prefix is now only a historical artifact.

## Graphics still required (you must create these)

- **App icon** 512×512 PNG (from your adaptive icon foreground)
- **Feature graphic** 1024×500 PNG
- **Phone screenshots** min 2 (2–8), 16:9 or 9:16
- **Wear OS screenshots** min 1 — REQUIRED to enable the Wear form factor
- (optional) 7" / 10" tablet screenshots
