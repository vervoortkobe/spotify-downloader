import 'package:flutter/widgets.dart';

/// Controls whether the mini player and nav bar drawn by `MainScreen` are shown.
///
/// `MainScreen` keeps the mini player in its own `Stack` and the nav bar as the
/// outer `Scaffold`'s `bottomNavigationBar`, while each tab owns a nested
/// `Navigator`. A sub-page pushed into a tab therefore renders *underneath* that
/// chrome instead of covering it, which is right for a playlist but wrong for a
/// settings page - the player sits on top of the rows you are trying to read.
///
/// Pages opt out by wrapping their content in [HideAppChrome]. Membership is a
/// set rather than a bool so nested pushes behave: pushing a sub-page from
/// Settings registers a second owner, and popping it leaves Settings' own
/// registration in place, so the chrome stays hidden until the last of them goes.
class AppChrome {
  AppChrome._();

  static final AppChrome instance = AppChrome._();

  final Set<Object> _miniPlayerHidden = <Object>{};

  /// Bumped whenever visibility changes, so listeners can rebuild.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  bool get miniPlayerVisible => _miniPlayerHidden.isEmpty;

  void hideMiniPlayer(Object owner) {
    if (_miniPlayerHidden.add(owner)) revision.value++;
  }

  void showMiniPlayer(Object owner) {
    if (_miniPlayerHidden.remove(owner)) revision.value++;
  }
}

/// Hides the mini player for as long as it is mounted.
///
/// Deliberately a wrapper rather than a mixin on the page's own `State`: several
/// of the pages that need this are `StatelessWidget`s, and converting them purely
/// to register in `initState` would be churn for no benefit.
class HideAppChrome extends StatefulWidget {
  const HideAppChrome({super.key, required this.child});

  final Widget child;

  @override
  State<HideAppChrome> createState() => _HideAppChromeState();
}

class _HideAppChromeState extends State<HideAppChrome> {
  @override
  void initState() {
    super.initState();
    // `this` is the State, which is a valid identity for the set and outlives
    // rebuilds of the child.
    AppChrome.instance.hideMiniPlayer(this);
  }

  @override
  void dispose() {
    AppChrome.instance.showMiniPlayer(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
