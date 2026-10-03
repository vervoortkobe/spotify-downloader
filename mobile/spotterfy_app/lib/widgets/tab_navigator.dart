import 'package:flutter/material.dart';

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
///
/// The key itself is supplied by the [MainScreen] that owns this widget (one
/// per tab, kept for the lifetime of that screen). It must NOT be a static
/// per-tab key: a static key outlives the screen, so a screen that the auth
/// gate swaps out and back in within one frame would leave the old tab's
/// [Navigator] elements deactivated while still holding the key, and the new
/// screen's tabs would claim the same keys - which crashes the frame with
/// "Duplicate GlobalKeys detected in widget tree". Instance keys die with the
/// screen, so a replacement screen always mints fresh keys.
class TabNavigator extends StatelessWidget {
  final int tabIndex;

  /// The tab's own root page.
  final Widget root;

  /// The tab's navigator key, owned by the hosting [MainScreen].
  final GlobalKey<NavigatorState> navKey;

  const TabNavigator({
    super.key,
    required this.tabIndex,
    required this.root,
    required this.navKey,
  });

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navKey,
      onGenerateRoute: (settings) =>
          MaterialPageRoute<dynamic>(settings: settings, builder: (_) => root),
    );
  }
}
