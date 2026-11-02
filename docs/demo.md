# The demo backend

`lib/core/demo/demo_backend.dart` is an in-process server (the API client swaps to it, and
nothing leaves the device). It has to present **every** feature the app has, the newest
included, because it is what a reviewer, the guided tour and a first-time user see.

## Rules

- **A feature built for a new server contract ships its demo in the same branch**: the
  routes, the observed keys the gate reads, and seed data rich enough for every state the
  screen has. Not a follow-up. A feature built without it is invisible in the demo, because
  its gate stays closed (suppliers once did: no `suppliers` key on the spools, no routes).
- **The demo's reported server version must never be what hides a feature.** Gates are
  settled by observation first ([server-gates.md](server-gates.md)), so serve the key or
  route the gate observes.
- **Demo copy must be true.** Describe the feature; never invent claims about firmware or
  hardware.
- Read the real demo data before writing a fixture that points at its ids; the ids below
  are what the fixtures use.
- Stateful features get a stateful demo (`DemoFinance` in
  `lib/core/demo/demo_finance.dart` for billing), so a write is visible on the next read.
- A route family the demo answers should filter like the server does. `GET /queue/` used to
  ignore `status`; it filters now, which the resume banner relies on.

## Slicer

`use_slicer_api` is `true`; with `false`, half of the pipelines feature is unreachable
(Slice and "Run pipeline" both hang on it). Rules that are easy to break:

- `GET /slicer/preset-values` values are **strings** (`'0.2'`, `'15%'`); a number makes the
  panel treat the field as changed by the user on open. The `standard` tier deliberately has
  no entry, so it answers `sidecar_outdated`, the only path to "defaults from the schema,
  and why".
- `/library/files/{id}/plates`: a `.3mf` carries `embedded_printer` (spelled as in
  `/slicer/presets`) and the **key** `design_overrides`; a non-3MF omits the key, and the
  absence is the signal that "slice as designed" is not on offer.
- Slice jobs are computed from the clock. `DemoBackend.sliceSeconds` (default 9) is public
  so tests need not wait; restore it in `addTearDown`. It is longer than the dialog's 1.5 s
  poll on purpose: a job already finished by the first poll never shows a stage or a
  percentage. The result row is created once, on the first poll that finds the job done.
- Library ids: 1 to 5 are sliced output, 6 to 9 are sliceable sources (9 is a STEP file);
  a completed slice adds rows from id 20 up.

## Pictures

Thumbnails, photos and camera frames are bundled as WebP under `assets/demo/{thumbs,photos,camera}/`
(about 1.3 MB) and **pruned from the watch APK** (`wearPrunedAssetPaths` in
`android/app/build.gradle.kts`, paired with `tool/check_wear_apk.py`, which fails if the
path reaches the watch).

- The picture key sits in the fixture's own `thumbnail_path` (`archive/demo/<key>.png`),
  `photos` (`<key>.jpg`) and `cover_image_filename`. `DemoBackend.pictureFor(route)` maps an
  image route to `thumbs/<key>` or `photos/<key>`, and to null where the real server would
  send nothing (STEP files, an offline printer, an idle printer's cover).
- `demoAssetFor` (in `demo_backend.dart`, phone only) is what `MediaImage` reads, because
  the app loads images outside Dio and the demo's HTTP adapter cannot answer them.
- Camera: `DemoBackend.cameraFrames(id)` returns a 12-frame loop for printer 1 while it
  prints and a still otherwise; `DemoCameraFeed` (`lib/features/camera/`) plays it in
  `CameraView` and `WallCamera`.
