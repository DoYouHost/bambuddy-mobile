import 'dart:io';

import 'package:bambuddy_mobile/core/diagnostics/relay_client.dart';
import 'package:bambuddy_mobile/core/diagnostics/relay_pow.dart';
import 'package:bambuddy_mobile/core/diagnostics/report_envelope.dart';
import 'package:bambuddy_mobile/core/diagnostics/report_outbox.dart';
import 'package:bambuddy_mobile/core/diagnostics/report_sender.dart';
import 'package:bambuddy_mobile/core/diagnostics/session_facts.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

RelayTicket ticket({Duration wait = Duration.zero, Duration life = const Duration(minutes: 30)}) {
  final now = DateTime.now();
  return RelayTicket(
    ticket: 'signed.$wait',
    notBefore: now.add(wait),
    expiresAt: now.add(wait + life),
    challenge: const PowChallenge(seed: 'seed', bits: 0),
  );
}

/// Stands in for the relay. The real one is exercised by the worker's own suite;
/// what matters here is how the app behaves around the wait it imposes.
class FakeRelay extends RelayClient {
  FakeRelay({this.issued, this.onSend}) : super(Dio());

  RelayTicket? issued;
  Future<String> Function()? onSend;

  int challenges = 0;
  int sends = 0;

  /// What the sender actually handed over, in order. Kept rather than counted
  /// because a request has to be recognisable as one: the kind it claims and
  /// the absence of a log are the whole difference on the wire.
  final List<Map<String, Object?>> reports = [];

  @override
  Future<RelayTicket> challenge(String installId) async {
    challenges++;
    final next = issued;
    if (next == null) throw const RelayException(RelayFailure.unreachable);
    return next;
  }

  @override
  Future<String> send({
    required String installId,
    required RelayTicket ticket,
    required ReportKind kind,
    required String description,
    required Map<String, Object> header,
    int? logSchema,
    String? log,
  }) async {
    sends++;
    reports.add({
      'kind': kind,
      'description': description,
      'header': header,
      'logSchema': logSchema,
      'log': log,
    });
    final handler = onSend;
    if (handler != null) return await handler();
    return 'https://github.example/issues/1';
  }
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('outbox'));
  tearDown(() => root.deleteSync(recursive: true));

  ReportSender senderWith(FakeRelay relay, {bool demo = false}) => ReportSender(
        client: relay,
        outbox: ReportOutbox(root: root),
        installId: () async => 'install-1',
        demoMode: () => demo,
      );

  Future<void> submit(ReportSender sender, {String description = 'it broke'}) =>
      sender.submit(
        description: description,
        // Header line first, as a real recording has it: the sender reads the
        // envelope off it rather than being told what is in the log.
        log: '{"v":1,"app":"0.11.7"}\n{"t":1,"msg":"hello"}\n',
      );

  group('outbox', () {
    test('a queued report survives the app being closed', () async {
      const outbox = ReportOutbox();
      final withRoot = ReportOutbox(root: root);
      expect(outbox, isNotNull);

      await withRoot.put(
        id: 'r1',
        kind: ReportKind.bug,
        description: 'it broke',
        header: const {'app': '0.11.7'},
        logSchema: 1,
        ticket: ticket(),
        log: 'line\n',
      );

      // A different instance, as after a restart: nothing is held in memory.
      final reopened = await ReportOutbox(root: root).peek();
      expect(reopened, isNotNull);
      expect(reopened!.description, 'it broke');
      expect(await ReportOutbox(root: root).readLog(reopened), 'line\n');
    });

    test('drops a slot whose log is gone rather than retrying it forever', () async {
      final outbox = ReportOutbox(root: root);
      final report = await outbox.put(
        id: 'r2',
        kind: ReportKind.bug,
        description: 'it broke',
        header: const {},
        logSchema: 1,
        ticket: ticket(),
        log: 'line\n',
      );
      File(report.logPath!).deleteSync();

      expect(await outbox.peek(), isNull);
    });
  });

  group('sending', () {
    test('sends straight away when the wait is already over', () async {
      final relay = FakeRelay(issued: ticket());
      final sender = senderWith(relay);
      addTearDown(sender.dispose);

      await sender.prepare();
      await submit(sender);

      expect(relay.sends, 1);
      // Nothing left queued: the report actually went.
      expect(await ReportOutbox(root: root).peek(), isNull);
    });

    test('queues rather than sends while the ticket is not yet valid', () async {
      final relay = FakeRelay(issued: ticket(wait: const Duration(minutes: 5)));
      final sender = senderWith(relay);
      addTearDown(sender.dispose);

      await sender.prepare();
      await submit(sender);

      expect(relay.sends, 0);
      // The user tapped send, so the report is theirs now — it has to outlive
      // the screen, the app being backgrounded and the app being killed.
      final queued = await ReportOutbox(root: root).peek();
      expect(queued, isNotNull);
      expect(queued!.description, 'it broke');
    });

    test('picks a report queued in an earlier run back up', () async {
      await ReportOutbox(root: root).put(
        id: 'r3',
        kind: ReportKind.bug,
        description: 'from yesterday',
        header: const {'app': '0.11.7'},
        logSchema: 1,
        ticket: ticket(),
        log: 'line\n',
      );

      final relay = FakeRelay(issued: ticket());
      final sender = senderWith(relay);
      addTearDown(sender.dispose);

      await sender.flush();

      expect(relay.sends, 1);
      expect(await ReportOutbox(root: root).peek(), isNull);
    });

    test('asks for a new ticket when the old one expired unused', () async {
      await ReportOutbox(root: root).put(
        id: 'r4',
        kind: ReportKind.bug,
        description: 'stale',
        header: const {},
        logSchema: 1,
        ticket: RelayTicket(
          ticket: 'old',
          notBefore: DateTime.now().subtract(const Duration(hours: 2)),
          expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
          challenge: const PowChallenge(seed: 'seed', bits: 0),
        ),
        log: 'line\n',
      );

      final relay = FakeRelay(issued: ticket());
      final sender = senderWith(relay);
      addTearDown(sender.dispose);

      await sender.flush();

      // The report is the user's; outliving the wait must not throw it away.
      expect(relay.challenges, 1);
      expect(relay.sends, 1);
    });

    test('keeps nothing queued once the relay says the report is a duplicate', () async {
      final relay = FakeRelay(
        issued: ticket(),
        onSend: () async => throw const RelayException(RelayFailure.duplicate),
      );
      final sender = senderWith(relay);
      addTearDown(sender.dispose);

      await sender.prepare();
      await submit(sender);

      // A dead end: retrying it forever would be worse than dropping it.
      expect(await ReportOutbox(root: root).peek(), isNull);
    });

    test('holds on to the report when the relay is only temporarily unhappy', () async {
      final relay = FakeRelay(
        issued: ticket(),
        onSend: () async => throw const RelayException(
          RelayFailure.notYet,
          retryAfter: Duration(minutes: 30),
        ),
      );
      final sender = senderWith(relay);
      addTearDown(sender.dispose);

      await sender.prepare();
      await submit(sender);

      expect(await ReportOutbox(root: root).peek(), isNotNull);
    });

    test('a cancelled report leaves nothing behind on disk', () async {
      final relay = FakeRelay(issued: ticket(wait: const Duration(minutes: 5)));
      final sender = senderWith(relay);
      addTearDown(sender.dispose);

      await sender.prepare();
      await submit(sender);
      // Awaited here, unlike in the UI: the point of this test is the files, and
      // the future is what says the delete finished.
      await sender.cancel();

      expect(await ReportOutbox(root: root).peek(), isNull);
      expect(root.listSync(recursive: true).whereType<File>(), isEmpty);
    });

    test('a bug report still says so on the wire', () async {
      final relay = FakeRelay(issued: ticket());
      final sender = senderWith(relay);
      addTearDown(sender.dispose);

      await sender.prepare();
      await submit(sender);

      expect(relay.reports.single['kind'], ReportKind.bug);
      expect(relay.reports.single['logSchema'], 1);
    });
  });

  group('change and feature requests', () {
    Future<void> submitRequest(
      ReportSender sender, {
      ReportKind kind = ReportKind.feature,
      String description = 'let it do the other thing',
    }) =>
        sender.submitRequest(
          kind: kind,
          description: description,
          envelope: requestEnvelope(
            const SessionFacts(
              app: '0.11.7+1107000',
              flavor: 'mobile',
              server: '0.2.5b3',
              locale: 'pl-PL',
            ),
          ),
        );

    test('a request goes out with no log at all', () async {
      final relay = FakeRelay(issued: ticket());
      final sender = senderWith(relay);
      addTearDown(sender.dispose);

      await sender.prepare();
      await submitRequest(sender);

      final report = relay.reports.single;
      expect(report['kind'], ReportKind.feature);
      // Absent, not empty: the relay has to be able to tell a request from a
      // bug report whose recording came out blank, and only the second is a
      // broken client worth knowing about.
      expect(report['log'], isNull);
      expect(report['logSchema'], isNull);
      // Nothing is left on disk either — a request writes no log file to clean
      // up after.
      expect(root.listSync(recursive: true).whereType<File>(), isEmpty);
    });

    test('the header names the versions and nothing about the setup', () async {
      final relay = FakeRelay(issued: ticket());
      final sender = senderWith(relay);
      addTearDown(sender.dispose);

      await sender.prepare();
      await submitRequest(sender, kind: ReportKind.change);

      final header = relay.reports.single['header']! as Map<String, Object>;
      expect(header['app'], '0.11.7+1107000');
      expect(header['server'], '0.2.5b3');
      expect(header['locale'], 'pl-PL');
      // The bug facts stay out: a public issue is no place for a person's
      // server address, their auth mode or which flavor they run.
      expect(header.keys, isNot(contains('serverUrl')));
      expect(header.keys, isNot(contains('auth')));
      expect(header.keys, isNot(contains('flavor')));
    });

    test('a queued request survives the app without growing a log', () async {
      final relay = FakeRelay(issued: ticket(wait: const Duration(minutes: 5)));
      final sender = senderWith(relay);
      addTearDown(sender.dispose);

      await sender.prepare();
      await submitRequest(sender, kind: ReportKind.change);

      // Read back through a fresh outbox, as after a restart: the kind has to
      // come off disk, or a request would be flushed as a bug with no log.
      final queued = await ReportOutbox(root: root).peek();
      expect(queued, isNotNull);
      expect(queued!.kind, ReportKind.change);
      expect(queued.hasLog, isFalse);
      expect(await ReportOutbox(root: root).readLog(queued), isNull);
    });

    test('what the screen is told names the report that is queued', () async {
      final relay = FakeRelay(issued: ticket(wait: const Duration(minutes: 5)));
      final sender = senderWith(relay);
      addTearDown(sender.dispose);
      final seen = <SendState>[];
      sender.states.listen(seen.add);

      await sender.prepare();
      await submitRequest(sender, kind: ReportKind.change);
      await pumpEventQueue();

      // The kind cannot be read off whichever tab the user happens to be on:
      // switching tabs does not call a queued report off, and the countdown,
      // the cancel and the failure advice all describe *this* report.
      expect(seen.last.phase, SendPhase.waiting);
      expect(seen.last.kind, ReportKind.change);
    });

    test('a slot from a build that only filed bugs is read as a bug', () async {
      // Written by hand in the old shape: no `kind`, which is exactly what an
      // install upgrading mid-wait has sitting in its outbox.
      final outbox = ReportOutbox(root: root);
      final report = await outbox.put(
        id: 'r10',
        kind: ReportKind.bug,
        description: 'queued before the update',
        header: const {'app': '0.11.7'},
        logSchema: 1,
        ticket: ticket(),
        log: 'line\n',
      );
      final slot = File('${root.path}/outbox/pending.json');
      slot.writeAsStringSync(
        slot.readAsStringSync().replaceFirst('"kind":"bug",', ''),
      );

      final reopened = await ReportOutbox(root: root).peek();
      expect(reopened!.kind, ReportKind.bug);
      expect(reopened.logPath, report.logPath);
    });
  });

  group('demo mode', () {
    test('never reaches the relay, and queues nothing on the way', () async {
      final relay = FakeRelay(issued: ticket());
      final sender = senderWith(relay, demo: true);
      addTearDown(sender.dispose);
      final seen = <SendState>[];
      sender.states.listen(seen.add);

      await sender.prepare();
      await submit(sender);
      // Whatever the sender does next, it does with nothing queued.
      await sender.flush();

      // Not one challenge either: they are metered per installation, so asking
      // for one that can never be spent costs the real user their next report.
      expect(relay.challenges, 0);
      expect(relay.sends, 0);
      expect(await ReportOutbox(root: root).peek(), isNull);
      // And the user is told why, rather than watching a send that never lands.
      await pumpEventQueue();
      expect(
        seen.map((s) => s.failure),
        contains(RelayFailure.demo),
      );
    });

    test('holds a report queued before demo instead of publishing it', () async {
      await ReportOutbox(root: root).put(
        id: 'r9',
        kind: ReportKind.bug,
        description: 'from the real server',
        header: const {'app': '0.11.7'},
        logSchema: 1,
        ticket: ticket(),
        log: 'line\n',
      );

      final relay = FakeRelay(issued: ticket());
      final sender = senderWith(relay, demo: true);
      addTearDown(sender.dispose);

      await sender.flush();

      expect(relay.sends, 0);
      // Kept, not dropped: the user asked for it, and leaving demo lets it go.
      expect(await ReportOutbox(root: root).peek(), isNotNull);
    });
  });

  group('proof of work', () {
    test('finds a nonce the relay would accept', () async {
      // Small on purpose: the shipped difficulty is a second of hashing, which
      // has no place in a unit test. The relay keeps it flat either way.
      final nonce = await solvePow(const PowChallenge(seed: 'abc', bits: 8));
      expect(int.tryParse(nonce), isNotNull);
    });
  });
}
