# Bambuddy — Privacy Policy

_Last updated: 9 July 2026_

Bambuddy is an unofficial, open-source Android companion app for a **self-hosted
bambuddy server** that manages Bambu Lab 3D printers. It is **not affiliated with,
endorsed by, or connected to Bambu Lab.**

This policy explains what data the app handles. In short: **Bambuddy does not
collect, transmit, or share any personal data with the developer or any third
party.** All data stays on your device and travels only to the bambuddy server
address that **you** configure.

## Who the app talks to

Bambuddy communicates **only** with the self-hosted bambuddy server whose address
you enter during setup. There is no Bambuddy backend, no analytics service, and no
advertising SDK. The developer never receives your data.

## Data stored on your device

- **Server address and login credentials** (API key or username/password/token for
  your bambuddy server). Credentials are stored in the Android **Keystore-backed
  encrypted storage** on your device and are never sent anywhere except to your own
  server, over the connection you configure.
- **App settings and notification preferences**, stored in local app storage.

This data is removed when you uninstall the app or clear its storage.

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

If you use Bambuddy on a paired Wear OS watch, your server configuration can be sent
from the phone to the watch over Google's encrypted **Wear Data Layer** between your
own paired devices. This transfer happens directly between your phone and your watch;
the developer has no access to it.

## Children

Bambuddy is a utility app for 3D-printer owners and is not directed at children.

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

Source code (AGPL-3.0): https://codeberg.org/MorganMLGman/bambuddy-mobile
