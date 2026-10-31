# How the print monitor decides to alert

`PrintMonitor` (`lib/features/notifications/print_monitor.dart`) turns a stream of
printer frames into alerts. Most of its rules are parity with bambuddy's own
notifier, and the rest are ours for a stated reason. The code keeps one line per
rule; the reasoning is here. Tests: `test/features/notifications/print_monitor_test.dart`.

## Baseline: the first frame fires nothing

The first frame for a printer records *what is already there*, so later frames
detect only true edges. A print in progress, a first layer already done, an
existing HMS error or a low tray are not events that just happened from the
app's point of view. `awaitingBedCool` stays false: a cold bed at start-up does
not mean a print just finished. The record is keyed by the map key, not
`status.id`, so a frame filed under another key cannot make the priming
disagree with the records that follow it.

**Nothing job-scoped is read off a frame that does not describe the job**
(`PrinterStatus.jobUnderway`). Priming off a calibration frame ("60%" at layer
0) would latch the 25 % and 50 % milestones as already sent and swallow both
when the real print reaches them. The dispatch race reaches priming too,
through an isolate that restarts while a job is being sent: the pre-print
sequence has ticked `layer_num` past 2 while the name and the percentage are
still the finished print's. A latch set from that frame has no edge left to
clear it, because priming records the printer as already printing, so the new
print's first layer would go by in silence. The frame is instead recorded as
the one to beat (`previousJob`), exactly as the print-start edge does.

The baseline first-layer reading deliberately has no window ceiling; the two
are one pair in `PrinterStatus.firstLayerPassed`.

## Which frame describes *this* print

bambuddy's state is a rolling merge of the printer's partial MQTT reports, so
the frame that flips a printer to RUNNING still carries the previous print's
name, layer and percentage. That frame is why a job sent seconds earlier once
announced the *finished* one's first layer. Nothing job-scoped runs until one of
the three moves (`_describesThisPrint`).

It is deliberately not a comparison against the new job's identity: the app
cannot know it (the name arrives in its own time) and printing the same file
twice in a row is legitimate. "Something new arrived" is the weakest question
that answers this, and it stays open for the rest of the print once answered.
The one frame turned down is recorded once per print (`previousJob`), with no
`event`, because the reading gates both the first layer and the milestones.

## First layer

Parity with bambuddy's `on_layer_change` (server #1837):

- layer **2** is the first layer *done*; layer 1 is it being printed;
- the window stops at **10**: a counter far past 2 belongs to a print joined
  halfway or to the job that has just ended, and neither is news;
- a printer **in a stage of its own is not laying that layer down**: the
  firmware ticks `layer_num` through bed levelling and nozzle cleaning, which
  announced a first layer minutes early and, right after a dispatch, under the
  previous print's name. bambuddy gates on `mc_print_sub_stage`, which the
  WebSocket does not carry, so `PrinterStatus.inNamedStage` asks the same
  question of the field both lanes do.

The one frame turned down per print is recorded (`prepPhase`): "the first layer
went by and nothing arrived" is otherwise indistinguishable from the alert
being switched off.

**The latch is set regardless of the preference**, so the decision (an alert or
one suppression record) is made once per edge; inside the condition it was
retaken on every frame, which a record would have turned into hundreds of
lines. This is sound only because `_prefs` is immutable for the monitor's whole
life (the service is rebuilt on the next background entry). If live preferences
ever land, it silently becomes "enable mid-print, stay quiet until the next
one". The latch stays *clear* while a frame is merely unusable, so an alert this
frame could not settle is still owed on the next one; bambuddy holds its own
flag the same way (`_first_layer_notified`).

## Pause coming up

`pauseUpcoming` warns before a pause the slicer put into the print (server #2984). The
server has its own alert for the same thing (`on_print_pause_upcoming`), sent through
whatever notification providers an administrator set up there; this one is the app's and
does not ask what the server has configured.

- **Source:** `PrinterStatus.nextPause` on the status frames — `{layer, minutes}`, see
  [server-contract-traps.md](server-contract-traps.md). No route, so it works with an API
  key.
- **When:** the first frame on which `minutes` is at most the lead time, **once per pause
  layer** (`_PrinterMemo.pauseWarnedLayers`, cleared when a print starts). The server's own
  rule, kept so the two alerts agree.
- **Lead time:** the server's `pause_warning_minutes`, read by the foreground service at
  start and every 30 minutes (`PrintMonitorTaskHandler._setUpPauseLead`), the server's own
  default of 5 until it answers or when it never sends the key. The monitor reads it per
  frame, so a change on the server is picked up without a restart. An unreadable answer
  keeps the last value.
- **No minutes, no warning.** `minutes` is null at the start of a print and in a speed mode
  other than standard; a warning by time with no time in it would be a guess. The layer
  alone is shown on the card, never warned about.
- **Baseline:** a pause already inside the lead time on the first frame is recorded as
  warned and says nothing, like every other event ([above](#baseline-the-first-frame-fires-nothing)).
- **On by default,** including for an install that predates it: it was not in the saved
  manifest, so it takes the default it ships with. The latch is set whatever the
  preference says, as for the first layer, so switching it on mid-print does not warn
  about a pause that was already inside the lead.

## HMS faults

- **Clear grace, 30 s** (`_hmsClearGrace`): a code that drops out of
  `hms_errors` for less than this is the same ongoing fault and does not
  re-alert when it flickers back. Some codes (chamber-temperature regulation)
  toggle every few seconds around a threshold. Parity with bambuddy's
  `_HMS_CLEAR_GRACE_SECONDS = 30`.
- **Hold, 15 s** (`_hmsHold`): a fault has to stand this long before it alerts,
  counted over the time the printer actually carries it. *Our* rule: the server
  notifies on first sight. An X2D switched on at the plug reports its AC board
  as broken for about five seconds while that board powers up (bug report #46),
  and that must not wake anyone. A gap shorter than the grace *pauses* the count
  instead of restarting it, so a fault that keeps flickering through a print
  still adds up to an alert.
- **Offline printers.** An offline printer cannot be actively faulting, the rule
  `displayableHmsErrors` applies on every screen
  ([notification-delivery.md](notification-delivery.md)). This path needs the
  carried-forward codes that function drops; change the meaning of "offline" there
  and the line here moves with it. Never alert while disconnected, but still *refresh* last-seen for
  present codes: that pauses the clear-grace clock across the outage, so a fault
  known before the disconnect does not re-alert on reconnect. Forgetting absent
  codes runs only while connected: a frame from a disconnected printer carries
  no evidence that anything cleared.
- **A new code seen while offline is deferred, not latched** (`hmsDeferredOffline`).
  Latching it would silence it for good: the printer can come back with the
  fault still standing, and until then nothing ages it out (with a second
  printer streaming, the grace window refreshes faster than it can elapse). One
  suppression record is written per such code.
- **A break in the feed** (`_carryHmsMemoryOverFeedGap`): the grace window is
  wall time, but the only evidence a fault cleared is a frame that no longer
  carries it. When nothing arrives at all (socket dropped, phone dozed) the
  window elapses against silence, and the first frame back would forget every
  standing code and alert about all of them again. Every remembered code is
  therefore held over a gap longer than the grace. The socket's own idle
  watchdog is longer than the window, so every disconnect it catches lands here.
- **User-action codes** (`0300_400C`, `0500_400E`) are what the firmware echoes
  during a normal cancel, not faults. bambuddy drops them; they are dropped here
  as a safety net for older servers and the `print_error` path.
- **Three separate reasons for no alert** (`_hmsSkipReason`): switched off by
  the user, a user-action code, or an undocumented code. The last is the largest
  silent drop on this path, since one physical fault emits several codes and
  only one is a real fault; notification is only for a documented fault (parity
  with bambuddy). Every answer settles the code for the life of the isolate; a
  disconnected printer is the one case that does not, so the caller defers it.
- **Records are per code per grace window**, written only on the first sighting.
  A record for the already-known case is deliberately absent: the WebSocket lane
  carries `hms_codes` on every frame, so a standing code with no notification
  record beside it *is* the dedup, visible on the same timeline.

## AMS humidity

- **Re-arm margin, 3 points** (`_humidityRearmMargin`): how far humidity must
  fall back below the user's threshold before the alert re-arms. bambuddy
  compares against a bare threshold and needs no band, because it looks every
  five minutes (`AMS_HISTORY_INTERVAL`) and holds the cooldown below. This
  monitor sees about one frame a second, so a reading resting on the threshold
  would cross it constantly and every dip would re-arm.
- **Cooldown, 1 h** (`_humidityAlertCooldown`): the number is bambuddy's
  `AMS_ALARM_COOLDOWN_MINUTES = 60`; the meaning is not. There it is a reminder
  interval: a unit above the threshold is announced again every hour. Here a
  stay is announced once, and the cooldown only rations how often a fresh stay
  counts as fresh, because every other event in this monitor alerts on the edge
  rather than on a timer.

## Once per print

`OncePerPrint` is a latch plus, for the ones that explain a silence, exactly one
record. `docs/logging-guide.md` requires that collapsing ("one record for a run,
not one per frame"); a hand-written `bool` latch is where it gets forgotten,
since prep lasts minutes at about a frame a second.

## Alert or record why not

`_alertOrRecordOff` is one decision, not two: an alert that never arrives must
leave a trace, or a report cannot tell a switched-off preference from a lost
event. Ten call sites once wrote the pair by hand, ten chances to write only the
half that alerts.

## Print end

Every end is recorded (`NotifProbe.printEnd`), including the ones that alert. A
user cancel lands as neither `FINISH` nor `FAILED`; that branch silently drops
the maintenance reminder as well as the alert, so this one line covers "my print
ended and nothing happened" whatever the reason, and shows a partial frame
faking an end.

## The ongoing notification

- The lead is the printer that **finishes earliest** (`PrinterStatus.etaRank`);
  the ETA line branches in the same order so it cannot name a printer the
  ranking would not have picked. It is a concrete finish time ("21:20"), not
  "in X", and carries the date when the print runs past midnight. The system
  24-hour switch is read per notification, because the user can flip it while
  the service runs.
- **One printer**: the title is the job (the machine needs no saying). **Several**:
  the title is how many are running; the bar, the line and the ETA belong to the
  one that finishes first, prefixed with the dashboard's own label so both
  surfaces pick the same printer and call it the same thing. A printer named
  "  " must not leave a gap between two separators.
- **A preparing machine gets the indeterminate bar**: its percent is zero because
  nothing has been measured, and a bar pinned at zero says "nothing is
  happening" about a machine heating its bed.
- **The mean over every printing machine is for the log only** (it answers "how
  far along was the rest of the shelf" for a report about a bar that looked
  wrong). A printer that sends no `progress` has not reported yet and is left
  out; one that reports 0 is genuinely at 0 and counts. Each figure is clamped
  *before* averaging. The mean is not part of the re-post key: it used to be,
  and keeping it would re-post a notification whose every visible field is
  unchanged.
- Recorded in the monitor, not the notification decorator (why:
  [notification-delivery.md](notification-delivery.md), `showOngoing`).
- **At most three action buttons** (`_maxAlertActions`): Android's shade lays
  out three and drops what follows without a word.

## Preferences and the master switch

- **The master switch gates inside `NotificationPrefs.isOn()`**
  (`alertsEnabled && enabled.contains(e)`), so every consumer honours it without
  asking. `_updateOngoing` does not call `isOn()`: the ongoing foreground-service
  notification stays up with alerts muted. A missing key in the stored JSON reads as
  `true`, so older installs keep their alerts.
- **Preferences are read once, when the foreground service starts.** A change in the
  UI applies from the next entry into the background. There is one HIGH-importance
  channel, `print_alerts`, and deliberately no separate silent one.
- The event list and its defaults live in `NotifEvent` / `notification_prefs.dart`;
  the numeric defaults there (bed cooled 35 °C, AMS humidity 60%, low filament 10%)
  are the thresholds the monitor uses.
