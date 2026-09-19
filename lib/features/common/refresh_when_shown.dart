import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';

/// Fetches again when the user comes back to a screen that has been sitting
/// out of sight, and when the server has announced that its data changed.
///
/// The tabs live in an `IndexedStack`, so a screen the user left is still
/// mounted with whatever it read the first time: a print queued from the web,
/// a spool edited on another phone, an archive row someone deleted — none of
/// it reached the tab until the user thought to pull it down. The dashboard
/// was the exception, because it polls.
///
/// Visibility comes from [TickerMode], which `StatefulShellRoute.indexedStack`
/// switches per branch (`go_router`, `_IndexedStackedRouteBranchContainer`):
/// the tab on screen has its tickers enabled and the others do not. The same
/// widget therefore says "I am the tab being looked at" without a screen
/// having to know its own index.
///
/// [staleAfter] keeps tab-flipping from becoming a request each: a screen that
/// was away for less than that is still what the user last saw. An
/// [announced] change skips the wait — the server said so, whenever it was.
class RefreshWhenShown extends StatefulWidget {
  const RefreshWhenShown({
    super.key,
    required this.onRefresh,
    required this.child,
    this.announced = 0,
    this.staleAfter = const Duration(seconds: 30),
  });

  final VoidCallback onRefresh;
  final Widget child;

  /// A counter the server's own announcements bump — a changed value means
  /// "this screen's data is known to be out of date". Hidden screens wait
  /// until they are looked at.
  final int announced;

  final Duration staleAfter;

  @override
  State<RefreshWhenShown> createState() => _RefreshWhenShownState();
}

class _RefreshWhenShownState extends State<RefreshWhenShown>
    with WidgetsBindingObserver {
  bool _shown = true;
  bool _announcedWhileAway = false;
  DateTime? _awaySince;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sawVisibility(TickerMode.valuesOf(context).enabled);
  }

  @override
  void didUpdateWidget(RefreshWhenShown old) {
    super.didUpdateWidget(old);
    if (widget.announced == old.announced) return;
    if (_shown) {
      _refresh();
    } else {
      _announcedWhileAway = true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The phone in a pocket is the same thing as another tab on top.
    _sawVisibility(
      state == AppLifecycleState.resumed &&
          TickerMode.valuesOf(context).enabled,
    );
  }

  void _sawVisibility(bool shown) {
    if (shown == _shown) return;
    _shown = shown;
    if (!shown) {
      _awaySince = clock.now();
      return;
    }
    // Always set: the only way here is through the branch above.
    final away = _awaySince!;
    _awaySince = null;
    if (_announcedWhileAway ||
        clock.now().difference(away) >= widget.staleAfter) {
      _refresh();
    }
  }

  void _refresh() {
    _announcedWhileAway = false;
    // After the frame: a fetch writes to a provider, and this can run while
    // the tree is building (a dependency change, a rebuild from the parent).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onRefresh();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
