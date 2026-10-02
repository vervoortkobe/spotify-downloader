import 'package:flutter/material.dart';
import 'package:spotterfy_app/widgets/app_bottom_nav.dart';

/// A separate [Navigator] for each bottom-tab.
///
/// This is what makes "sub-pages inside a tab" work properly. With a single
/// shared navigator, tapping a nav destination had to pop the pushed screen to
/// escape to another tab - which destroyed it, so returning to that tab lost
/// the page *and* its state (scroll offset, selection, loaded data).
///
/// One navigator per tab means each tab owns an independent stack. Switching
/// tabs only changes which stack is visible, so:
///  - a sub-page opened in a tab survives navigating away and back,
///  - its [State] is never disposed, so everything it loaded is still there,
///  - tapping a nav destination on a sub-page just changes tab and leaves the
///    sub-page sitting on its own stack.
///
/// The navigator is keyed per tab, which is what makes the stacks independent:
/// the same key across tabs would share one stack.
class TabNavigator extends StatelessWidget {
  final int tabIndex;

  /// The tab's own root page.
  final Widget root;

  const TabNavigator({super.key, required this.tabIndex, required this.root});

  @override
  @override
  Widget build(BuildContext context) {
    // A GlobalKey per tab (memoised on tabIndex) rather than a ValueKey, so the
    // controller can pop this specific stack when the nav destination is tapped.
    // The navigator under the navbar is not this one while a sub-page is pushed,
    // so MainScreen cannot reach it by lookup from a non-ancestor context.
    final navKey = _keys.putIfAbsent(
      tabIndex,
      () => GlobalKey<NavigatorState>(),
    );
    return Navigator(
      key: navKey,
      onGenerateRoute: (settings) =>
          MaterialPageRoute<dynamic>(settings: settings, builder: (_) => root),
    );
  }

  /// One key per tab index, kept for the lifetime of the app so the stacks stay
  /// addressable from the nav bar.
  static final Map<int, GlobalKey<NavigatorState>> _keys = {};

  /// The live state of [tabIndex]'s own stack, or null before that tab's layer
  /// has been built once.
  static NavigatorState? navigatorFor(int tabIndex) =>
      _keys[tabIndex]?.currentState;

  /// Whether [tabIndex] currently has a sub-page pushed on top of its root.
  static bool canPopTab(int tabIndex) =>
      _keys[tabIndex]?.currentState?.canPop() ?? false;

  /// Publishes each tab's navigator to the nav bar. Called from MainScreen
  /// after the tab layer is built.
  static void registerAll() {
    for (final entry in _keys.entries) {
      tabNavController.registerNavigator(entry.key, entry.value.currentState);
    }
  }
}
