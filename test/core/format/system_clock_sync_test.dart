import 'package:bambuddy_mobile/core/format/datetime_format.dart';
import 'package:bambuddy_mobile/core/format/system_clock_sync.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A PM time, so a 12-hour clock is visible in the output rather than implied.
final _at = DateTime(2026, 8, 22, 21, 20);

/// The channel [MainActivity] serves. Named here as a literal on purpose: the
/// two sides meet on this string and nothing else would fail if it drifted.
const _channel = MethodChannel('page.codeberg.morganmlgman.bambuddy/clock');

void main() {
  // Static by design — it is read from isolates that share nothing else — so it
  // has to be put back or it leaks into whatever runs next.
  tearDown(() => DateTimeFormats.rememberSystemClock(null));

  /// What the platform answers, and how often it was asked.
  late bool? platformSays;
  var asked = 0;

  setUp(() {
    platformSays = null;
    asked = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      expect(call.method, 'is24HourFormat');
      asked++;
      return platformSays;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  /// What the subtree reads out of `MediaQuery` — the value every screen formats
  /// its times with.
  bool? belowSays;

  Widget tree({
    required bool inTheTree,
    required void Function(bool) onChanged,
  }) =>
      MediaQuery(
        data: MediaQueryData(alwaysUse24HourFormat: inTheTree),
        child: SystemClockSync(
          onChanged: onChanged,
          child: Builder(builder: (context) {
            belowSays = MediaQuery.alwaysUse24HourFormatOf(context);
            return const SizedBox();
          }),
        ),
      );

  testWidgets('publishes what the tree says while nobody else answers',
      (tester) async {
    final seen = <bool>[];
    await tester.pumpWidget(tree(inTheTree: true, onChanged: seen.add));
    await tester.pumpAndSettle();

    expect(seen, [true], reason: 'the value has to reach preferences too');
    expect(DateTimeFormats.system().time(_at), '21:20');
  });

  testWidgets('the platform outranks a MediaQuery the engine left stale',
      (tester) async {
    // The engine sends the user settings once, when the view attaches. A switch
    // flipped afterwards never reaches the tree — on device the app went on
    // showing AM/PM until it was swiped out of recents.
    platformSays = true;
    final seen = <bool>[];
    await tester.pumpWidget(tree(inTheTree: false, onChanged: seen.add));
    await tester.pumpAndSettle();

    expect(seen, [false, true], reason: 'the tree first, then the correction');
    expect(belowSays, isTrue, reason: 'the screens read it out of MediaQuery');
    expect(DateTimeFormats.system().time(_at), '21:20');
  });

  testWidgets('asks again on every resume, which is when it can have changed',
      (tester) async {
    platformSays = false;
    final seen = <bool>[];
    await tester.pumpWidget(tree(inTheTree: false, onChanged: seen.add));
    await tester.pumpAndSettle();
    expect(asked, 1);

    // Out to Android's settings and back.
    platformSays = true;
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();

    expect(asked, 2, reason: 'only the resume is worth a round trip');
    expect(seen, [false, true]);
    expect(belowSays, isTrue);
  });

  testWidgets('a host with no answer leaves the tree in charge',
      (tester) async {
    // A test, another platform, an older host build: the fallback is whatever
    // the engine did manage to push, not a hardcoded clock.
    await tester.pumpWidget(tree(inTheTree: true, onChanged: (_) {}));
    await tester.pumpAndSettle();

    expect(belowSays, isTrue);
    expect(DateTimeFormats.system().time(_at), '21:20');
  });

  testWidgets('an unchanged switch is not republished on every rebuild',
      (tester) async {
    final seen = <bool>[];
    await tester.pumpWidget(tree(inTheTree: true, onChanged: seen.add));
    await tester.pumpWidget(tree(inTheTree: true, onChanged: seen.add));
    await tester.pumpAndSettle();

    // Each republish is a preferences write, and this rebuilds with every route.
    expect(seen, [true]);
  });

  testWidgets('a 12-hour phone is spelled as one, not left to the locale',
      (tester) async {
    // The locale under test is en_US, which reads 12-hour anyway — so this pins
    // that the published `false` is what decides, the same as it does on `pl`.
    platformSays = false;
    await tester.pumpWidget(tree(inTheTree: false, onChanged: (_) {}));
    await tester.pumpAndSettle();

    expect(DateTimeFormats.system().time(_at), '9:20 PM');
  });
}
