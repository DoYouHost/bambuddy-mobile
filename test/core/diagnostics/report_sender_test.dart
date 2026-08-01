import 'dart:io';

import 'package:bambuddy_mobile/core/diagnostics/relay_client.dart';
import 'package:bambuddy_mobile/core/diagnostics/relay_pow.dart';
import 'package:bambuddy_mobile/core/diagnostics/report_outbox.dart';
import 'package:bambuddy_mobile/core/diagnostics/report_sender.dart';
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
    required String description,
    required Map<String, Object> header,
    required int logSchema,
    required String log,
  }) async {
    sends++;
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
        description: 'it broke',
        header: const {},
        logSchema: 1,
        ticket: ticket(),
        log: 'line\n',
      );
      File(report.logPath).deleteSync();

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
