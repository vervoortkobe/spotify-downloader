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
class TabNavigator extends StatelessWidget {
  final int tabIndex;

  /// The tab's own root page.
  final Widget root;

  const TabNavigator({super.key, required this.tabIndex, required this.root});

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: ValueKey('tab-nav-$tabIndex'),
      // Only consulted for the initial route and named-route pushes; routes
      // handed to `Navigator.push` directly (everything in this app) bypass it
      // and land on this navigator because it is the nearest one.
      onGenerateRoute: (settings) =>
          MaterialPageRoute<dynamic>(settings: settings, builder: (_) => root),
    );
  }
}
