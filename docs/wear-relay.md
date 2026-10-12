# The phone↔watch relay

`lib/core/watch/` (`wear_rpc.dart`, `wear_relay_handler.dart`,
`wear_relay_claim.dart`). The watch has no server session of its own by default:
it asks the phone, over the Wear Data Layer, and the phone answers with its own
authenticated connection. The code keeps one line per rule; the reasons are here.
The watch's own poll is in [wear-fleet-poll.md](wear-fleet-poll.md).

## The RPC contract (`wear_rpc.dart`)

- The watch sends a `WearRpcRequest`; the phone executes it and replies with a
  `WearRpcResponse` carrying the **raw server JSON**, which the watch parses with
  the same model `fromJson`s it uses for direct REST. There is no `toJson`
  anywhere: models are parse-only.
- `watch_connectivity` hardcodes **one `MessageClient` path** for every message,
  so requests and responses share a stream and are told apart by `kind`, not by
  Data Layer paths. Correlation is by `id`. Delivery is not guaranteed, so
  callers pair it with a timeout.
- **Retry semantics** (`WearRpcRetry`). `mayRepeatOverRest` is true for a *read*
  only, `idempotent` included: after the relay timed out, a command may have run
  with the reply lost on the way back, and the watch cannot tell that from a
  phone that never heard it. The user is owed one answer about one command, not
  two attempts at it.
- **`wearRpcVersion`** is bumped on incompatible changes; a decoder that sees a
  newer one still tries to parse, because fields are additive. **v2** = the sender
  understands `WearRpcAck` and waits `wearRpcWakeTimeout` once acked. The phone
  reads the version off a request to decide whether it may execute one on the
  *cold* path at all: a v1 watch has already given up by then, and its retry
  would run the command twice.
- **`WearRpcAck`** is the phone→watch "hold on": the phone had no relay
  listening, the message woke its process, and an answer to the `id` is coming
  later than the watch's normal deadline. It is a **separate `kind`**, not a
  field on the response, because a watch built before it existed must not read it
  as an answer: its decoders match on the kind and drop everything else, so an ack
  is silently ignored there and the request keeps the deadline it always had.

## The phone side (`WearRelayHandler`)

It runs only while a Flutter engine hosts it: the app's own, the foreground
service's, or the headless one the native listener service starts when the process
was dead (`wear_relay_engine.dart`). **Which of them may answer at any moment is
decided by `WearRelayClaim`**, so a request never reaches both a listener and a
freshly woken engine. Fleet statuses are fetched as raw JSON and passed through
untouched.

Constructor arguments, and why each exists:

- **`dio`** returns the current authenticated client, or null when no server
  profile is configured (the watch is then told `phone-unconfigured`).
- **`liveStatus`** (FGS isolate only) returns the raw last-known WebSocket status
  frame for a printer, or null when there is nothing trustworthy (socket down,
  printer never seen); the handler then falls back to a REST status fetch for that
  printer. Live frames are served only while the socket is up: after a disconnect
  the cache may be stale.
- **`claim`** tells the native listener service that this process is answering.
  Null where there is nothing to coordinate with: tests, and the woken engine
  itself, which never listens (the service hands it each request).
- **`plateGateAcknowledged`** lets that cache be told the plate-clear gate is
  down. The server pushes a fresh frame for the flag only while the printer has a
  live MQTT client, so after acknowledging a printer that Auto Power Off already
  switched off nothing would ever correct the cached `true`, and the watch's own
  post-action refresh would draw the button again.
- Only one responder listens at a time (the UI-engine handler is stopped on
  pause): a command answered twice would execute twice, e.g. a double `startNext`.

### `start` and `stop` order

`start` is idempotent. Requests are handled sequentially per message (each in its
own async task; the stream is not awaited), which is fine for a watch that sends
one request at a time per screen.

**Claim first, listener second, and the reverse in `stop`.** Between those two
acts the native service believes nobody is answering, and a request arriving then
would be answered by a woken engine as well as by this listener. A claim that
could not be written means no listener at all, for the same reason.

**`_sequenced` runs start and stop one at a time.** Each is two steps (the claim
and the subscription) and every caller is a lifecycle callback that fires them
without awaiting, so the next one arrives while the previous is in flight.
Interleaved, they leave either a listener with no claim (a woken engine answers
the same request) or a claim with no listener (nothing answers at all), and
`start`'s own `_sub` check would read a subscription that `stop` is half-way
through cancelling.
