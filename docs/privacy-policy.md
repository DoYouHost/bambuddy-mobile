# Bambuddy mobile — Privacy Policy

_Last updated: 1 August 2026_

Bambuddy mobile is an unofficial, open-source Android companion app for a **self-hosted
bambuddy server** that manages Bambu Lab 3D printers. It is **not affiliated with,
endorsed by, or connected to Bambu Lab.**

This policy explains what data the app handles. In short: the app has **no analytics, no
advertising and no cloud account**, and everything it does while you use it stays between
your device and the bambuddy server address **you** configure.

There is one exception, and only you can trigger it: if you decide to report a bug from
inside the app, your description and a diagnostic log you have read through first are
published as a **public issue on GitHub**. Nothing is sent unless you choose that, and
the whole path is described under [Sending a bug report](#sending-a-bug-report).

## Who the app talks to

- **Your bambuddy server** — the self-hosted address you enter during setup. While you
  use the app, this is the only server it talks to. There is no cloud backend, no
  analytics service and no advertising SDK.
- **The bug-report relay and GitHub** — contacted **only** when you open "Report a bug"
  and choose to publish a report. The relay (`relay-bambu.morganmlg.com`) is a small
  Cloudflare Worker operated by the developer; it exists so that you can file a report
  without having a GitHub account. If you never send a report, the app never contacts
  either of them.

## Data stored on your device

- **Server address and login credentials** (API key or username/password/token for
  your bambuddy server). Credentials are stored in the Android **Keystore-backed
  encrypted storage** on your device and are never sent anywhere except to your own
  server, over the connection you configure.
- **App settings and notification preferences**, stored in local app storage.
- **A random installation identifier** — a UUID the app makes up for itself the first
  time you open the report form. It is not a device identifier and is not derived from
  one; its only job is to pace bug reports, so that whoever keeps sending them waits
  longer each time. Reinstalling the app replaces it.
- **A diagnostic log**, while a recording is running or waiting for you to decide what
  to do with it.

This data is removed when you uninstall the app or clear its storage.

## Diagnostic logs

The app **can** record a diagnostic log, but only when **you** start one yourself from
"Report a bug". Nothing is recorded before you press start, and a recording stops by
itself after 30 minutes, or sooner if it reaches 20 MB.

Such a log describes what the app did: screens you opened, controls you pressed, requests
to your server and the status codes that came back, live-view connection events, what the
background service decided about notifications, and crashes. It never contains your API
key, your password, or **any text you type into the app**. Your server address is reduced
to its shape — whether it is http or https, a name or an IP, and the port — file, model
and spool names are left out, and a control you press is recorded under an internal name
rather than the label shown on screen.

You review the whole log on screen, and then you choose one of two destinations:

- **Save to a file** — the log is written where you pick and stays on your phone. Nothing
  is uploaded, and whether you ever send that file to anyone is entirely your decision.
- **Report on GitHub** — the log is published, as described in the next section.

Once the log has been saved, published or discarded, the app deletes its own copy.

## Sending a bug report

This happens only when you write a description in the report form and press Report. It is
voluntary from beginning to end: if you do not send a report, nothing described in this
section takes place.

### What leaves your phone

- **Your description**, exactly as you wrote it, in whatever language you used.
- **The diagnostic log** you have just reviewed, compressed.
- **A short session header**: the app version and build number, whether it is the phone
  or the watch build, your Android version, your device's language tag (for example
  `pl-PL`), the bambuddy version your server reports, the *shape* of your server address
  as described above, and which authentication mode you use.
- **The installation identifier** described above.
- **Your IP address**, which the relay necessarily sees, as does any server you connect
  to.

### Where it goes

The relay checks the report, commits the log file to the `bug-report-assets` branch of the
app's public GitHub repository, and opens a **public issue** that quotes your description
and the session header and links to the log. The app then shows you the address of that
issue.

**A public issue is public and permanent by its nature.** Anyone can read it, search
engines index it, and other people can copy or quote it. Deleting an issue later cannot
undo a copy somebody has already taken. Please treat the description as something you are
publishing: do not put your name, e-mail address, home address, network details or
anything else you would not post publicly into it.

### What the relay stores

The relay's job is to keep this endpoint from being abused, and it holds as little as it
can to do that:

- Your installation identifier, your IP address and your description are turned into
  **keyed hashes (HMAC-SHA-256)** before anything is written down. The relay never stores
  or logs any of the three in the clear.
- Those hashes, with timestamps, sit in a small counter database used for the hourly and
  daily caps, the per-IP cap and duplicate detection. Report rows are deleted
  automatically within **25 hours**, and the rows that pace repeat reporting within
  **36 hours**.
- The relay keeps **no copy of your log or your description**. Both are forwarded to
  GitHub, and from then on they exist there and nowhere else.
- When a cap is hit, the developer receives an alert over Telegram. It carries counters
  only — never any part of any report.

### Services involved

- **Cloudflare** — hosts the relay and filters abusive traffic at the edge. It processes
  connection metadata, including your IP address, in the course of delivering and
  protecting the request.
- **GitHub** — hosts the public issue and the log file attached to it.
- **Telegram** — carries the maintainer alerts described above, which contain no report
  content.

## Permissions and why they are used

- **Internet / network state** — to reach the bambuddy server you configure, and the
  report relay if you choose to send a report.
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

- **On your device** — uninstall the app or clear its storage in Android settings. That
  also removes the installation identifier and any log still waiting on the phone.
- **A report you published** — write to the contact address below with the address of the
  issue, and the issue together with its log file will be deleted from the repository.
  Because the repository is public, copies that other people, forks, mirrors or search
  engines have already taken are outside the developer's control.
- **Relay counters** — they expire on their own within about a day and hold nothing but
  keyed hashes, so there is nothing there to identify or delete.
- **Your bambuddy server** — the data it holds is governed by that server, which you
  control.

## Changes to this policy

Updates to this policy will be published at this page. Material changes will be noted
by the "Last updated" date above.

## Contact

Questions about this policy: **info.doyouhost@gmail.com**

Source code (AGPL-3.0): https://github.com/DoYouHost/bambuddy-mobile
