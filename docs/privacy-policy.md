# Bambuddy mobile — Privacy Policy

_Last updated: 28 July 2026_

Bambuddy mobile is an unofficial, open-source Android companion app for a **self-hosted
bambuddy server** that manages Bambu Lab 3D printers. It is **not affiliated with,
endorsed by, or connected to Bambu Lab.**

This policy explains what data the app handles. In short: **Bambuddy mobile does not
collect, transmit, or share any personal data with the developer or any third
party.** All data stays on your device and travels only to the bambuddy server
address that **you** configure.

## Who the app talks to

Bambuddy mobile communicates **only** with the self-hosted bambuddy server whose address
you enter during setup. There is no cloud backend, no analytics service, and no
advertising SDK. The developer never receives your data.

## Data stored on your device

- **Server address and login credentials** (API key or username/password/token for
  your bambuddy server). Credentials are stored in the Android **Keystore-backed
  encrypted storage** on your device and are never sent anywhere except to your own
  server, over the connection you configure.
- **App settings and notification preferences**, stored in local app storage.

This data is removed when you uninstall the app or clear its storage.

## Diagnostic logs

The app **can** record a diagnostic log, but only when **you** start one yourself from
"Report a bug". Nothing is recorded before you press start, and a recording stops by
itself after 30 minutes.

Such a log describes what the app did: screens you opened, controls you pressed,
requests to your server and the status codes that came back, live-view connection
events, what the background service decided about notifications, and crashes. It never
contains your API key, your password, or text you type. Your server address is reduced
to its shape — whether it is http or https, a name or an IP, and the port — and file,
model and spool names are left out.

**The log stays on your device, and the app never uploads it anywhere.** You review it
in full on screen, and the only way it leaves the phone is if you save it to a file, in
a location you choose, and then decide to send that file to someone — for example when
attaching it to a bug report. Whether and when that happens is entirely your decision.
Once you save the log, or discard it, the app deletes its own copy.

## Permissions and why they are used

- **Internet / network state** — to reach the bambuddy server you configure.
- **Camera** — used **only** when you open the spool QR scanner. Frames are processed
  on-device to read a spool code; images are not stored or transmitted. The scanned
  spool identifier is sent only to your bambuddy server.
- **Notifications + foreground service (data sync)** — to keep a live connection to
  your server while a print is running and show print status and alerts. No data
  leaves your device beyond the connection to your server.
- **Wake lock** — keeps the background print-status connection alive during a print.

## Wear OS companion

If you use Bambuddy mobile on a paired Wear OS watch, your server configuration can be sent
from the phone to the watch over Google's encrypted **Wear Data Layer** between your
own paired devices. This transfer happens directly between your phone and your watch;
the developer has no access to it.

## Children

Bambuddy mobile is a utility app for 3D-printer owners and is not directed at children.

## Data deletion

Because no data is collected on any server operated by the developer, there is
nothing for the developer to delete. To remove all locally stored data, uninstall the
app or clear its storage in Android settings. Data held by your bambuddy server is
governed by that server, which you control.

## Changes to this policy

Updates to this policy will be published at this page. Material changes will be noted
by the "Last updated" date above.

## Contact

Questions about this policy: **info.doyouhost@gmail.com**

Source code (AGPL-3.0): https://codeberg.org/DoYouHost/bambuddy-mobile
