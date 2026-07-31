import 'dart:async';

import 'package:flutter/foundation.dart';

import 'relay_client.dart';
import 'relay_pow.dart';
import 'report_envelope.dart';
import 'report_outbox.dart';

/// Where a report is in the send flow, as far as the user is concerned.
enum SendPhase { idle, waiting, sending, sent, failed }

@immutable
class SendState {
  const SendState._(this.phase, {this.readyAt, this.issueUrl, this.failure});

  const SendState.idle() : this._(SendPhase.idle);
  const SendState.waiting(DateTime readyAt)
      : this._(SendPhase.waiting, readyAt: readyAt);
  const SendState.sending() : this._(SendPhase.sending);
  const SendState.sent(String url) : this._(SendPhase.sent, issueUrl: url);
  const SendState.failed(RelayFailure failure)
      : this._(SendPhase.failed, failure: failure);

  final SendPhase phase;

  /// When the queued report becomes sendable. Drives the countdown.
  final DateTime? readyAt;
  final String? issueUrl;
  final RelayFailure? failure;

  Duration get remaining {
    final at = readyAt;
    if (at == null) return Duration.zero;
    final left = at.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }
}

/// Drives one report from "the form is open" to "here is your issue".
///
/// The relay makes each further report from an installation wait longer than the
/// last, so the shape of this class follows from that: fetch the ticket early,
/// queue the report to disk the moment the user commits, and send when the wait
/// is over — whether or not they are still looking at the screen.
class ReportSender {
  ReportSender({
    required this._client,
    required this._outbox,
    required this._installId,
  });

  final RelayClient _client;
  final ReportOutbox _outbox;

  /// Read lazily rather than passed in: it lives in preferences, and the sender
  /// is built before those are necessarily loaded.
  final Future<String> Function() _installId;

  final _states = StreamController<SendState>.broadcast();
  Stream<SendState> get states => _states.stream;

  RelayTicket? _ticket;
  Timer? _timer;

  /// Called the moment the user decides to send, not when they tap send.
  ///
  /// That ordering is the entire reason the delay is tolerable: the relay starts
  /// the clock here, and the user spends the next half minute writing, so by the
  /// time they tap send the wait is usually already over. A failure is silent —
  /// they have not asked for anything yet.
  ///
  /// Not called any earlier than the decision, though — the relay charges for a
  /// challenge when it hands one out, not when one is used, so fetching a ticket
  /// the user turns out not to want makes their *next* report wait twice as
  /// long, and the one after that four times.
  Future<void> prepare() async {
    // Idempotent, and that is not an optimisation: a ticket in hand has already
    // been paid for, and the relay charges per challenge *issued*. Without this,
    // flipping the destination back and forth doubles the user's wait on every
    // flip and throws away a perfectly good ticket each time.
    final held = _ticket;
    if (held != null && !held.expired) return;

    try {
      final ticket = await _client.challenge(await _installId());
      // Solved now, on a background isolate, for the same reason the ticket is
      // fetched now: there is idle time here and none at all on the send tap.
      _ticket = ticket.solved(await solvePow(ticket.challenge));
    } on RelayException {
      _ticket = null;
    }
  }

  /// Commits the report: it goes to disk first, so closing the app cannot lose it.
  ///
  /// The header and the schema are not parameters: they are read out of [log]
  /// itself, so a caller cannot describe one recording while attaching another.
  Future<void> submit({
    required String description,
    required String log,
  }) async {
    final ticket = _ticket;
    if (ticket == null || ticket.expired) {
      // Nothing was reserved for us, or it went stale while the form was open.
      await prepare();
      if (_ticket == null) {
        _emit(const SendState.failed(RelayFailure.unreachable));
        return;
      }
    }
    final usable = _ticket!;

    final envelope = reportEnvelope(log);
    await _outbox.put(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      description: description,
      header: envelope.header,
      logSchema: envelope.logSchema,
      ticket: usable,
      log: log,
    );
    await flush();
  }

  /// Sends whatever is queued, or schedules the attempt for when it matures.
  /// Safe to call on app start, which is how a report queued yesterday goes out.
  Future<void> flush() async {
    _timer?.cancel();
    // An outbox that cannot be read answers the same question as an empty one:
    // there is nothing to send. Guarded because this runs at app start, where a
    // storage directory that will not resolve must not throw into a future
    // nobody is waiting on.
    PendingReport? pending;
    try {
      pending = await _outbox.peek();
    } on Object {
      pending = null;
    }
    if (pending == null) {
      _emit(const SendState.idle());
      return;
    }

    if (pending.ticket.expired) {
      // The wait was outlived rather than served. Ask for a new ticket and keep
      // the report: it is the user's, and they already decided to send it.
      await prepare();
      final fresh = _ticket;
      if (fresh == null) {
        _emit(const SendState.failed(RelayFailure.unreachable));
        return;
      }
      final log = await _outbox.readLog(pending);
      if (log == null) {
        _emit(const SendState.failed(RelayFailure.rejected));
        return;
      }
      await _outbox.put(
        id: pending.id,
        description: pending.description,
        header: pending.header,
        logSchema: pending.logSchema,
        ticket: fresh,
        log: log,
      );
      return await flush();
    }

    if (!pending.ticket.ready) {
      _emit(SendState.waiting(pending.ticket.notBefore));
      // One timer rather than polling: nothing else has to happen until then.
      _timer = Timer(pending.ticket.wait + const Duration(seconds: 1), flush);
      return;
    }

    _emit(const SendState.sending());
    final log = await _outbox.readLog(pending);
    if (log == null) {
      await _outbox.clear();
      _emit(const SendState.failed(RelayFailure.rejected));
      return;
    }

    try {
      final url = await _client.send(
        installId: await _installId(),
        ticket: pending.ticket,
        description: pending.description,
        header: pending.header,
        logSchema: pending.logSchema,
        log: log,
      );
      await _outbox.clear();
      _emit(SendState.sent(url));
    } on RelayException catch (error) {
      if (error.retryable) {
        final delay = error.retryAfter ?? const Duration(minutes: 1);
        _emit(SendState.waiting(DateTime.now().add(delay)));
        _timer = Timer(delay, flush);
        return;
      }
      // A dead end: keeping the report queued would retry it forever.
      await _outbox.clear();
      _emit(SendState.failed(error.failure));
    }
  }

  /// Drops a queued report the user changed their mind about.
  ///
  /// Everything that actually stops the send happens **before the first await**,
  /// so it is done the moment this is called, whether or not the caller waits:
  /// the timer is what would have fired, and it is dead. The returned future only
  /// covers deleting the queued copy.
  ///
  /// The UI deliberately does not await it — a discard that blocks on storage is
  /// a discard that can sit there spinning — but tests can, and so can anyone who
  /// needs the slot provably gone.
  ///
  /// The residual risk, named rather than hidden: if the delete fails or the app
  /// dies first, the slot survives and the next start will send it.
  Future<void> cancel() async {
    _timer?.cancel();
    _timer = null;
    _emit(const SendState.idle());
    try {
      await _outbox.clear();
    } on Object {
      // Nothing useful to do here, and the timer is already dead.
    }
  }

  void dispose() {
    _timer?.cancel();
    _states.close();
  }

  void _emit(SendState state) {
    if (!_states.isClosed) _states.add(state);
  }
}
