# API keys and server settings

What a session can write to the server depends on how it signed in, and the server's own
settings have traps of their own. The general rule for choosing a feature under an API key
is in [server-contract-traps.md](server-contract-traps.md); this file is the specifics.

## Server settings: the hub

`/settings/server` (`ServerSettingsScreen`) is the home for **every** setting the app
changes on the server; the drawer has one entry for it (`drawer.server_settings`). It
holds Queue & preheat (`/settings/queue`), Maintenance (`/settings/maintenance`), the
Bambu Cloud account (`/settings/cloud`) and Administration (`/admin`); those routes keep
their paths because other screens push to them. The line it keeps:

- **hub** = changed for every user of the server;
- **Notifications** = changed for this phone, and stays its own drawer entry.

A new server-side setting goes into the hub, not into the drawer.

### Who may write

`SETTINGS_UPDATE`, `SETTINGS_BACKUP` and `SETTINGS_RESTORE` are in
`_APIKEY_DENIED_PERMISSIONS` and absent from `_APIKEY_SCOPE_BY_PERMISSION`
(`core/auth.py`); `SETTINGS_READ` maps to `can_read_status`, so a key reads, with sensitive
fields blanked. The one key-writable piece is `POST /settings/electricity-price`.

| Session | Read | Write |
|---|---|---|
| API key | yes | **never** |
| authentication off (`AuthMode.none`) | yes | **yes**, there is nobody to check |
| JWT | yes | with `settings:update` |

The middle row is the trap. `identifiedPermissionProvider` and `canOpenAdminProvider`
answer `false` for an unknown identity, so gating settings on them hides the feature from
the session with the most rights. The hub is therefore ungated, and
`queueSettingsLockProvider` decides by `authMode` first and only then by the user's
permission (an unresolved `/auth/me` keeps the form in loading rather than lighting it up
for a session about to be refused; a failed one is presumed allowed like every permission
here, and the first 403 closes the form).

### Route traps

- **`PUT /settings/` needs the trailing slash.** It is registered only as `"/"`
  (`routes/settings.py`); without it FastAPI redirects, Dio replays the request as a
  `GET`, the answer is 200 and nothing is saved. `Endpoints.appSettingsUpdate` holds the
  right spelling.
- **Partial, and forgiving the wrong way.** The body is `AppSettingsUpdate`, applied with
  `exclude_unset=True` and pydantic's default `extra="ignore"`: an older server answers
  200 and stores nothing. The gate is therefore the key's **presence in `GET /settings`**,
  which always serializes the full schema with defaults (`QueueSettings.known`). A version
  is no threshold here, every 1.2.6 daily reports `1.2.6b1`. The bounds in `QueueSetting`
  are the schema's own, and the server answers 422 rather than clamping.
- **Blobs, not objects.** `drying_presets` and `ams_humidity_thresholds` are strings with
  JSON inside (default `""`). A configured blob **replaces** the default table entirely
  (`print_scheduler.py::_get_drying_presets`), so the client replaces too
  (`dryingPresetsFrom`); merging would offer a filament the server's auto-drying has never
  heard of.
- A table in the app that "mirrors the web frontend" may really be a server setting.
  Check `AppSettings` before copying constants from the web.

### Queue and preheat

The first `AppSettings` writer: one key per write, optimistic, rolled back on a refusal
(`QueueSetting`, `lib/core/models/queue_settings.dart`). Out of scope on purpose:
`preheat_filament_targets` needs a list editor, and an empty value means "the built-in
table", which the app would have to duplicate.
`queue_keep_warm_bed_temp` is **not** greyed out when keep-warm is off: it is also the bed
temperature preheat falls back to when a chamber-heated job's metadata carries none.

### Pause warning

`pause_warning_minutes` (server #2984, 1 to 120, default 5) is how long before a slicer
pause the **server** sends its own "Pause Coming Up" alert, and the lead time the app's
own pause alert uses too. It is a server setting, so it lives in the hub
(`PauseWarningScreen`), and it borrows the queue block's machinery whole: it is a
`QueueSetting`, written one key at a time, offered only when `GET /settings` answers the
key, and locked by `queueSettingsLockProvider` — which is also why the screen reuses the
queue screen's two read-only sentences.

- **An API key reads it and never writes it.** The value is no secret (only the
  `SETTINGS_SECRETS` fields are blanked for a key), so a key and an account without
  `settings:update` see the same slider, greyed, with the value the server holds and the
  sentence that says why. An account that may write gets the live slider.
- **The server's alert and the app's are two alerts.** Whether the server's reaches the
  user depends on a notification provider configured there
  (`on_print_pause_upcoming`, `NOTIFICATIONS_UPDATE`, not writable with a key), which the
  app neither reads nor assumes.

## Pipelines

Since server 1.2.5.3 (commit `a4795c5c`) an API key can read and run slicer pipelines,
never author them. The gate is an allowlist, so `PIPELINES_WRITE` is refused on every
version, current and future; the deny list next to it is documentation only.

| Permission | Key scope | Routes |
|---|---|---|
| `PIPELINES_READ` | `can_read_status` | list, get, check-eligibility, list runs, get run |
| `PIPELINES_RUN` | `can_queue` **and** `can_manage_library` | run, cancel, retry-failed |
| `PIPELINES_WRITE` | none (outside the allowlist) | create, update, delete, `POST /pipeline-runs/clear` |

Run needs both flags because a run slices into the library and then queues prints; a key
holding one of the two is refused. The app does not offer authoring on
`authMode == apiKey` at all: `/auth/me` claimed an admin with every permission for a key up
to 1.2.5.x, and reports the real set (`apikey_effective_permissions`) from 1.2.6, so both
answers are settled on the auth mode, like `identifiedPermissionProvider`. How the three
latches are built is in [queue-and-pipelines.md](queue-and-pipelines.md#slicer-pipelines).

## Billing under a key

`GET /finance/cost-centers/mine` answers 200 to an API key from server #3256 on and 401
before it; the app words that as "refused", not "none"
([billing.md](billing.md)). The Finance screen needs `cost_centers:read_own`, which no key
can hold.

An admin created by `/auth/setup` has **no private cost center**; only users created
through the API or the admin screen get one, so `mine` is empty for that admin. The web
behaves identically.

## Media credentials

A key reaches thumbnails and photos through the `X-API-Key` header, not a token. The
three-way choice and its traps are in
[server-contract-traps.md](server-contract-traps.md#media-credentials).
