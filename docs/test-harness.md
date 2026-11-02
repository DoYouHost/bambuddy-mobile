# Test harness — the traps behind `test/helpers.dart`

`test/helpers.dart` holds the shared fakes and pumping helpers; the pieces that
are not about this app — `RequestLog`, `mockServer`, `ScriptedAdapter`,
`FakeTimer`, `testWithClock`, `byLogId`, `settle`, `usePhoneWindow` — live in
the `app_test_kit` package (shared with lubelogger) and `helpers.dart`
re-exports them. Each one exists
because a test went green for the wrong reason, or red with an error that hid
the real one. This file keeps the reasons; the code keeps one line each.

## HTTP mocks

- **A mock handler runs once, when the route is declared — never when a request
  arrives.** A counter or list written inside an `http_mock_adapter` handler
  records the registration, and reports the same thing whether the app sent
  nothing, one request or ten. Six tests once asserted on such a flag and two
  passed with the call under test deleted. Use `captureRequests(dio)` and
  assert on its `RequestLog`.
- **`RequestLog` is safe to assert on alone** because its interceptor runs per
  request and *before* the adapter looks for a route: a request to a path no
  mock covers is logged and still fails the test.
- **Assert the whole `calls` list, not a `contains`**, so a stray request shows
  up instead of passing unnoticed.
- **`statuses`** holds the status of each answer, `null` where the failure
  carried no response (what an unmatched route looks like). Requests fired
  concurrently can complete out of order, so it lines up with `calls` only when
  they were awaited one at a time. Assert on it wherever the code under test
  swallows what it gets: a swallow hides the difference between the refusal the
  test registered and the adapter failing to find a route.
- **`untilCount(n)`** waits until `n` requests have *finished*, for calls a
  repository starts with `unawaited`. One `Future.delayed(Duration.zero)` is
  not enough — the interceptor chain and the adapter each take a turn of the
  event loop. It counts `statuses`, not `requests` (a request is logged on its
  way out, its status only when the answer is back) and returns on its deadline
  rather than throwing, so the caller's own `expect` reports what arrived.
- **`mockServer(dio)` matches the body exactly.** The adapter's default takes a
  body that merely *contains* the mocked keys, so a mocked `{}` matched every
  request and a test named "sends only what changed" passed with extra keys going
  out. Still subsets: queries, headers, and the elements of a body that is itself
  a list (`matches_request.dart` does not pass the flag down into one) — assert
  those on `captureRequests`.
- **One host.** `fakeServerBaseUrl` is shared so a screen reading the profile
  and an adapter mocking the wire cannot disagree about it.

## Widget tests

- **Every test runs in the app's fonts**, loaded by `test/flutter_test_config.dart`
  before each file. The test font draws every glyph as a square as wide as it is
  tall, about twice the real width, and a test that forgot to load the real ones
  measured a layout the app never draws: the controller saver's clock wrapped in
  it from 10:00 on and the test went red twice a day. Not a per-file `setUpAll`,
  which is how one was forgotten.
- **`test/contract/` has its own `flutter_test_config.dart`**, without that
  font loading: loading fonts needs `TestWidgetsFlutterBinding`, which answers
  every HTTP request with a 400, and the contract tests talk to a real server.
  Every one of them failed in its `setUpAll` the day the fonts went global, and
  locally nothing showed it, because without a server they skip.
- **No profile, no widget.** A widget that reads the server profile builds its
  API client from it; without one that throws `UnimplementedError` into an
  unbounded `ErrorWidget`, and the 100000 px overflow that follows buries what
  the test was about. Pass `noServerProfileOverride` (or `serverProfileOverride`
  / `fakeServerProfileOverride`) in `overrides` almost always. The auth mode on
  the fake profile is not decoration: screens hide admin-only routes for an API
  key, and the auth interceptors differ.
- **The inert overrides** (`inertFirmwareOverride`, `inertAnnouncementsOverride`,
  `inertTotalPrintHoursOverride`, `inertChamberMaxOverride`,
  `inertHistorySupportOverrides`, `inertSmartPlugsOverride`,
  `inertStatusesOverride`) keep a provider the screen reads while it renders off
  the network. A real fetch leaves a hanging Dio timer, and a live poll
  outlives the test; both trip the framework's pending-timer check.
- **`usePhoneWindow`**: the default 800×600 is wider than tall, a shape no screen
  here is designed for — a square preview claims the viewport and the list
  below it never builds, and a settings screen builds only its first section.
  `dp` is the logical height. **A tap below 1200 dp of content silently
  misses:** `WidgetTester.tap` warns "would not hit test" on stdout and passes
  anyway, so a test that scrolls to a row far down must ask for the height.
- **`settle`** pumps three 350 ms frames instead of `pumpAndSettle`, for screens
  it can never finish on (a search field's cursor blinks forever). That is long
  enough for a sheet, a dialog or a snack to open, which is what every caller
  waits for.
- **`scrollSheetDown`**: sheets and forms are lazy lists taller than the screen;
  what sits below the fold is not built, and a finder cannot tap it.
- **`testWithClock`**: the app reads time through `package:clock`'s ambient
  clock and nothing takes a clock of its own, so this is the one way a test
  fakes time — build the subject inside the body and move it with `tick`.
- **`byLogId` / `identifiersIn`**: a control that lost its diagnostic id still
  renders and taps; only the log goes quiet, which nothing else notices. The id
  is also the only thing that tells identical tiles apart.

## Wear tests

- **`pumpWear` owns the container** through the `ProviderScope`, on purpose.
  `wearFleetProvider` runs a poll timer; a container that outlives the widget
  tree keeps it alive past the end of the test and trips the pending-timer
  check. Tearing the tree down disposes the container, which cancels it.
  `wrapInApp: false` is for `WearApp`, which builds its own `MaterialApp` (so it
  runs in the system locale, not `plApp`'s Polish).
- **`wearShapeBuilder`** puts `WearShapeScope` where `WearApp` does, above the
  navigator. Wrapping the child leaves the scope under `home`, and a route is
  `home`'s sibling, so every dialog silently fell back to round — the one shape
  a test asking for a square face is not looking for.
- **Faces:** the default is `wearFaceSmall` (384×384 px at density 2, a 192 dp
  face) because it is what Wear emulators boot with and where a size written as a
  number instead of a fraction of the display breaks: the confirm dialog's
  button row fit 225 dp and overflowed 192 dp by 11 px with every test green.
- **`useWatchFace`** replaces the 800×600 phone surface; the round-safe layout
  only means anything against a face this small. The shape is answered on the
  `wear_shape` channel the way the platform answers it.
- **`revealOnWatch`** scrolls a control the way a user does: most of a wear screen
  starts below the fold and a `ListView` builds nothing off-screen. It aligns to
  the *middle* of the face, not merely into the viewport — a scaling list runs
  to the rim, where an item is drawn at 70% and half faded, and a tap aimed at
  its unscaled box misses.
- **`expectOnGlass`** fails unless every corner of a box is on the circle. A
  widget test is happy while nothing overflows the *square* the display reports,
  and the watch lights only the inscribed circle; a bar pinned to the square's
  bottom is not an overflow, just mostly invisible on the device. Use it for
  anything the layout places itself. A scaling list (`curved: true`) is the
  exception on purpose: like Wear OS's own, it lets the bezel cut an item at the
  edge.
- **`tapOnWatch`** settles the scroll but pumps one frame after the tap: what a
  tap starts is the test's business, and an action that puts up a spinner would
  hang `pumpAndSettle` forever.

## Fakes

- `FakeWearTransport` logs every call as `name` / `name:printerId` with the real
  method names, so a stray command shows up in `calls` instead of vanishing into
  a `noSuchMethod`. `commands` is `calls` without the reads a screen runs on
  mount and after every action.
- `RecordingNotifications.alerts` carries the union of what the old per-file
  stubs recorded, both `actions` (objects) and `actionIds` (their ids), because
  asserting on the ids is what most callers mean.
- `ScriptedAdapter.script`: one step per request; the **last step stands for
  every request past the end**, so a retry that fires more often than the test
  spelled out is answered rather than crashing on a range error. A step may
  return a `ResponseBody` or a `DioException`, which is *thrown*, the way a
  transport failure reaches the code under test.
- `FakeTimer` keeps the `duration` it was asked for, which is the one thing a
  test checking *when* something was scheduled needs.
- `testRecorder` wires a `DiagnosticRecorder` as the app does: the redactor and
  the two ceilings are the app's answers, not the test's — a test that picked its
  own would assert against a session bambuddy never records.
- The two profile/user fakes left with their own class are the ones that need
  one: `current_user_provider` drives the profile by hand mid-test, and the
  watch's settings screen overrides `clear()` to record that it was called.

## Proving a test bites

A test that asserts a **status** or a **body** is only as good as the mutation it
survived. Three ways one passes while measuring nothing:

- **A mock on the wrong HTTP method.** `adapter.onGet('/x/999', reply(404))` while
  the code under test does `PUT /x/999` leaves the request unmatched: the adapter
  fails with no response, `statusCode` is `null`, and the 404 the test's name
  promises never happens. `throwsA(isA<AppApiException>())` still passes, because
  every failure maps to it. Assert on `statuses` (a `null` there gives it away) and
  invert the behaviour under test once to see the test fail.
- **A mutation that did not take effect.** `git stash push <file>` only reverts to
  `HEAD`; if the fix is already committed, the code stays fixed and the test looks
  empty. Mutate the **file's content** (copy it aside, replace the line, run, copy
  it back) and not git state.
- **A finder that compares a widget with itself.** `find.byType(TextField)` also
  matches the field a `DropdownMenu` builds inside itself, so `.last` can pick the
  select instead of its neighbour and the assertion compares it to itself. Find the
  neighbour by `Key`.
