# Library tags, projects and model sources — what the contract hides

The file manager (`lib/features/files/`), the projects screens
(`lib/features/projects/`) and the Model Sources screen
(`/model-sources`: a MakerWorld tab and a Manyfold tab) lean on routes whose
behaviour does not show in the OpenAPI document. The gates for the routes that
older servers lack are in [server-gates.md](server-gates.md).

## Library tags

The catalog is `/library/tags` (CRUD), assignment is `bulk-assign`, and the filter is
`GET /library/files?tag_ids=…`.

- **`tag_ids` voids the folder scope on the server.** With a non-empty `tag_ids`,
  `list_files` skips `folder_id` and `include_root` and answers from the whole
  library (every tag must match). So the repository has a separate
  `listFilesByTags`, not a parameter on `listFiles`, and the UI hides the folders
  while a tag filter is on.
- **`tag_ids` must be a repeated key** (`tag_ids=1&tag_ids=2`). Dio does this by
  default (`ListFormat.multi`), but `tag_ids[]=` or `tag_ids=1,2` reads as zero tags
  and **silently returns the whole library**. The test checks the URL's shape
  (`test/data/library_repository_test.dart`), not the parameter map.
- **`files_updated` from `bulk-assign` can be lower than the number sent.** The
  server silently skips files the caller may not edit (`TagAssignResult`), and that
  difference is the only sign of a partial application.
- Catalog writes (create, rename, delete) need `LIBRARY_UPDATE_ALL`; tagging a file
  needs only the `*_OWN` permission. The app does not know the caller's permissions,
  so a rename or delete can answer 403: it shows the message instead of hiding the
  button.
- A duplicate name is a **409**, compared without case (`LOWER(TRIM(name))`).
- **A 404 on `/library/tags` is the feature gate**: an older server has no such
  routes, `listTags()` returns null, and every tag control disappears
  (`LibraryRepository.tagsCapability`). Any other error is a real error, so a network
  blip does not remove the feature.
- Tag names travel inside the file listing, so a rename refreshes the file list as
  well as the catalog.

## Projects (`/api/v1/projects/*`)

- **Unlinking a folder takes `{"project_id": 0}`.** `{"project_id": null}` answers 200
  and does **not** unlink: the route reads null as "no change"
  (`library.py`, `if data.project_id is not None` / `== 0` unlinks).
  `ProjectsRepository.setFolderProject` therefore sends `projectId ?? 0`.
- **`GET /projects/{id}/timeline` has answered 500 for some projects** (a server
  defect, not the app's). The repository turns every failure but an auth error into
  an empty list, so the Timeline section reads "no activity" rather than a red
  screen.
- The detail screen is **one scrolling page of sections**, as on the web, not tabs:
  header, progress, statistics, notes, files (linked folders), attachments, parts
  list, timeline. "Plates" are print jobs (`target_count`), "Parts" are
  `target_parts_count`.

## MakerWorld

The tab lives in **Model Sources**, beside Manyfold; the drawer entry is
`drawer.makerworld` and the old `/makerworld` route redirects to `/model-sources`.
Flow: paste a URL, resolve it, pick a plate, import to the library.

- **"Signing in to MakerWorld" is signing in to the Bambu cloud.** The gate is
  `GET /makerworld/status` -> `{has_cloud_token, can_download}`. Without
  `can_download` the import action does not download: it opens `/settings/cloud`, a
  screen of its own in the settings, **not** a login embedded in the MakerWorld tab.
  On return the tab invalidates `cloudAuthStatusProvider` and
  `makerworldStatusProvider`.
- The cloud login with a second factor is `POST /cloud/login {email, password,
  region}` -> `{success, needs_verification, verification_type, tfa_key}`, then
  `POST /cloud/verify {email, code, tfa_key?, region}`; the region must be the one
  used for the login. `GET /cloud/status` and `POST /cloud/logout` complete it. This
  is the cloud account's flow, unrelated to the bambuddy login's second factor in
  [screens.md](screens.md#two-factor-login).
- `POST /makerworld/resolve {url}` works **without** a token; only
  `POST /makerworld/import` needs one, and it is idempotent (`was_existing=true`,
  no second download).
- `design` and `instances` are MakerWorld's own opaque maps: parse them defensively.
  The keys are camelCase (`profileId`, `cover`).
- `GET /makerworld/thumbnail?url=<enc>` is **public on purpose** (an `<img>` cannot
  send a token), so a plain `Image.network` is right for it
  (`makerworld_thumbnail.dart`).
- **Snack bar trap:** `SnackBar.persist` defaults to `action != null`, so a snack
  bar with a `SnackBarAction` never closes. Pass `persist: false` and a `duration`
  explicitly (`MakerWorldTab._snack`).

## Manyfold

- The tab shows when `GET /manyfold/status` answers **and** either Manyfold is
  configured or the session may configure it (`manyfoldTabShownProvider`) — the
  web's rule (`ModelSourcesPage.tsx`). Configuring needs `settings:update`, which an
  API key never holds (`canConfigureManyfoldProvider`), so on a key an unconfigured
  Manyfold has no tab at all. Accepted by the maintainer as the cost of the key's
  scope.
- Manyfold errors come as `{detail: {code: "manyfold_…"}}` (409, 404 or 502, never
  401/403) and become `ManyfoldFailure(code, cause)`. `manyfoldCause` holds the rule
  "expected, or rethrow", so a bug in the app still reaches the bug report.
- The contract test runs against a real Manyfold in the `daily` CI job
  (`tool/ci/manyfold_setup.rb`, the `BAMBUDDY_CONTRACT_MANYFOLD_*` variables).
