# The diagnostic log

What `lib/core/diagnostics/` records, what it refuses to record, and how the
pieces fit. The individual files carry only the non-obvious "why" of their own
code; the policy that binds them lives here.

A recording is attached to a bug report and uploaded to a **public, permanent
GitHub issue**. Every rule below follows from that one fact.

## The naming rule

The log records **identifiers, never accessibility labels.** A label is the
user's own text — a model name, a file name, a spool name — and those values are
dynamic, so no redactor can catch them.

Controls worth naming declare an identifier with `logTag`; anything else reports
its role alone (`role=button`). Ids are dotted, lowercase, stable, never
localized, and carry no data: `archive.card`, not `archive.card.MyModel`.
Repeated rows share one id — which row it was is not what a bug report needs.

The probe carries an identifier down to the node actually hit, so tagging a card
names taps anywhere inside it. That means an identifier on a whole screen would
name every tap in it; in practice they go on controls, and a slightly over-broad
name beats no name at all.

**Filament material is the single exception.** "PETG in slot 3" explains a real
share of AMS reports and a name out of a fixed list identifies nobody. A control
opts in with `logTagMaterial`, the value rides on the identifier
(`inventory.spool@PETG`) because the semantics tree is the probe's only channel,
and only `FilamentMaterial.known` values survive — checked on both sides, since
`join` is a call site anyone can add to and `split` is what actually writes.

## What never enters a record

| lane | excluded | why |
|---|---|---|
| HTTP | headers | the API key lives there |
| HTTP | query string | camera and thumbnail tokens live there |
| HTTP | host | the user's private network; the header carries scheme, port and name-vs-IP instead |
| HTTP | `/auth/*`, `/cloud/*`, `/makerworld/*`, `/settings/*`, `/users/*` bodies | tokens, credentials, people |
| WebSocket | the frame payload | model and file names, spool names, printer serials |
| notifications | `title` and `body` | the job label or the printer's name |
| interactions | accessibility labels | see the naming rule |
| 2FA | pre-auth token, cookie value, the code typed, the address | |

Sampling is an **allowlist, not a denylist**: forgetting an endpoint costs a
diagnosis, forgetting one in a denylist costs a secret. A prefix on the allowlist
is not a promise that everything under it is content — `/printers/camera/
stream-token` mints a token and sits inside `printers`, so paths matching
`token|api-keys` are excluded first.

The redactor is the net that exists so as not to be leaned on. It blanks any
field whose *name* looks like a secret, which is why the 2FA record reports
`binding: true/false` rather than a field called `cookie`: a live recording
logged `"cookie":"[REDACTED]"`, the same text whether the binding arrived or not.

## What a successful answer contributes

A status code cannot separate "the screen is empty" from "the screen shows the
wrong thing" — a 200 with twenty records the app then hides looks exactly like a
200 with nothing in it. So a content endpoint contributes its record count plus
**one** record in full. The rest of the list stays a number, and an unchanged
sample degrades to `same`, or a poll answering twice a minute for half an hour
would *be* the log.

WebSocket frames follow the same shape for the same reason: sometimes the point
of a report is *what* arrived. The rule for which fields go in is not "which are
worth it" — that produced a first version logging a third of the frame with the
rest left to guess. The rule is **whose the value is**: everything the printer or
the server owns goes in, nothing the user wrote does. The set deliberately covers
the server's own `status_key`, the tuple it deduplicates broadcasts on, so a
`repeated` record means "identical in everything the server compares" rather than
"changed something we chose not to look at".

## What stopped somebody: `app action_failed`

Every error response is already in the log as an `http` record, with its status
and a preview of the body. What that cannot say is whether anyone was *stopped*
by it: a screen that quietly hides a section on a 403 and one that refuses the
tap the user just made look identical there.

So the shared `ActionOutcome.failed` — the single funnel every feature's actions
now pass through — writes one record for a failure the user is about to be told
about: the `action` they touched (in the `logTag` vocabulary), the `code`, the
`status`, and the server's own `reason`. That `reason` is the field worth having.
A 403 is the one refusal a code cannot explain, and the sentence naming the
missing permission (`API key owner does not have 'printers:control' permission`)
exists nowhere else in structured form — only inside the `http` record's body
blob, if it was not clipped.

Reading a report, the `http` record above it says which call it was; this one
says it reached the user and how it was worded to them.

## Repeats

Three lanes collapse consecutive identical events into a count, for the same
reason each time: an unbounded run would sweep the ring buffer clean of
everything that explains the bug.

- a widget that throws in `build` throws again on **every frame** — sixty records
  a second empty the buffer in about a minute (`ErrorProbe`)
- the server pushes on any change to its status key, including fields a record
  would be a status dump to carry, so a frame that changes nothing we log is
  normal (`WsProbe`)
- scrolling is one drag per flick (`InteractionProbe`)

The count is written out when the run ends and every window while it lasts, so a
burst lands on the timeline where it happened instead of collapsing into one
number at the end. The window is checked when an event arrives — a storm by
definition keeps arriving, so none of this needs a timer.

## Streams and the merge

Each isolate has its own heap and therefore its own always-null
`DiagnosticRecorder.active`, so each writes its own file with its own header:

- `ui` — the app
- `fgs` — the foreground service
- `action` — the short-lived engine the notification plugin spawns to perform
  "Mark Done", which does real HTTP on the way

A background stream is strictly a *continuation* of the UI's. The session id
comes from `SettingsRepository`, and the header is the UI's re-tagged — so the
fingerprint cannot drift between two files of one session, and `ts` is the
session's start. That puts both streams on one clock, which makes `t` values
directly comparable and the merge a no-shift. Without a readable UI header there
is nothing to merge into, so the isolate does not record at all.

`mergeSessions` rebases onto the earlier of the two headers, the only origin that
keeps every offset positive, and stamps the secondary's records with `iso` naming
their stream. Without that the merged header says `stream:"merged"` and a
`GET /printers/` from the service is indistinguishable from the UI's — which is
exactly the bug this log has already caught once, both isolates polling at the
same time.

Order is by `t`, never by arrival: a tap is stamped with the moment the finger
went down, so it is written after events that happened later than it. Ties keep
arrival order via a sequence number, because Dart's sort is not stable.

## Ceilings

A session ends itself on whichever comes first, and the closing record says
which. It is `limit_reached`, not `recording_stopped` — nobody stopped it, it ran
out.

- **30 minutes.** The reports that need this most start before the print does:
  powering the printer on and getting a job to actually start does not fit in
  five, and cutting the recording there leaves the half without the answer. A
  recording forgotten overnight still cannot exist.
- **20 MB.** Every accepted record is mirrored to disk and nothing takes one back
  out, so without this the only bound on the file is time — measured with
  wall-clock deltas that a clock correction can stall. Twenty megabytes is ~30×
  what a busy half hour produces (measured: ~18 KB a minute with one printer
  printing), so reaching it means something is wrong.

The ring buffer's own caps are **runaway guards, not budgets**. The report is read
back from the file, which nothing evicts from, so eviction costs the heap nothing
and the report nothing.

## The durable mirror

The foreground service can be killed at any time and its heap dies with it, so
every line is written and flushed as it arrives rather than held in memory. That
is also what makes recovery possible: a native crash or an OOM kill takes the
buffer, but every line was already on disk, redacted on the way in.

Nothing in the recorder may throw. The service's `onStart` is called through a
platform channel that swallows a Dart exception and reports success anyway — the
service would stay up, its notification would keep saying "monitoring", and
nothing would be monitored. A diagnostic recorder must not be able to cause the
failure it exists to describe.
