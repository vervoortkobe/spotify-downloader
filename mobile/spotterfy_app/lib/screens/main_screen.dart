import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/services/network_stats_service.dart';
import 'package:spotterfy_app/widgets/app_bottom_nav.dart';
import 'package:spotterfy_app/widgets/mini_player.dart';
import 'package:spotterfy_app/widgets/tab_navigator.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import 'yt_search_screen.dart';
import 'jam_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 2;

  /// Tab we are animating *away* from, so both ends of the switch can be drawn
  /// during the transition.
  int _leavingIndex = 2;

  /// +1 when moving right, -1 when moving left.
  int _slideDir = 1;

  late final AnimationController _tabCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    // Start settled, otherwise the first frame would draw the initial tab
    // part-way through the enter transition (40% opacity, offset).
    value: 1.0,
  );
  late final Animation<double> _tabAnim = CurvedAnimation(
    parent: _tabCtrl,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    // Bind the signed-in user for background data-usage cloud sync
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final uid = context.read<AuthProvider>().user?.uid;
      context.read<NetworkStatsService>().setUserId(uid);
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  /// The four tab roots. These are `const`, so the widgets - and therefore the
  /// per-tab [TabNavigator]s and their route stacks - are created once and kept
  /// for the lifetime of this screen.
  final List<Widget> _tabs = const [
    SearchScreen(), // Home - Discover
    YtSearchScreen(), // Search - YT
    LibraryScreen(), // Library - playlists + storage
    JamScreen(), // Chat
  ];

  /// Nav destination tapped while that tab is already showing.
  ///
  /// Pops the tab's own stack to its root. The tab keeps its identity, so
  /// navigating away and back still lands on whatever sub-page it is showing.
  void _reselectTab(int i) {
    if (i < 0 || i >= _tabs.length) return;
    tabNavController.onDestinationTapped(i);
  }

  void _goToTab(int i) {
    if (i == _currentIndex || i < 0 || i >= _tabs.length) return;
    setState(() {
      _slideDir = i > _currentIndex ? 1 : -1;
      _leavingIndex = _currentIndex;
      _currentIndex = i;
    });
    _tabCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    // Publish the active tab so pushed screens (e.g. a playlist) can render the
    // same nav bar with the correct selection.
    tabNavController.currentIndex = _currentIndex;
    // Publish each tab's navigator so the nav bar can pop a tab back to its
    // root. Re-registered every build because a tab's state is only attached
    // once its layer has been built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) TabNavigator.registerAll();
    });
    // A pushed screen asked to switch tabs (e.g. tapped a nav destination).
    if (tabNavController.hasPendingRequest) {
      final target = tabNavController.takePendingRequest();
      if (target != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _goToTab(target);
        });
      }
    }

    return PopScope(
      // Never let the system close the app from here. The root navigator's
      // history only knows about MainScreen itself, so without this the back
      // button could not reach a sub-page pushed onto a tab's *own* stack and
      // simply did nothing. canPop:false forces every press through
      // [_handleSystemBack] below, which unwinds the active tab properly.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleSystemBack();
      },
      child: Scaffold(
        backgroundColor: SpotterfyTheme.background,
        // No swipe-to-switch here: content swipes belong to inner widgets
        // (track tiles, mini player, library tabs). Tab switching lives on the navbar.
        body: Stack(
          children: [
            AnimatedBuilder(
              animation: _tabAnim,
              builder: (context, _) {
                // Every tab is kept mounted in a plain Stack. Deliberately NOT an
                // IndexedStack/KeyedSubtree keyed on the current index: re-keying
                // it on every switch would dispose all four tab subtrees, taking
                // each tab's navigation stack (and any open sub-page's state) with
                // it. Tabs outside the transition are Offstage, which keeps their
                // state alive while skipping paint and ticks.
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    for (var i = 0; i < _tabs.length; i++) _tabLayer(i),
                  ],
                );
              },
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _MainMiniPlayerWrapper(),
            ),
          ],
        ),
        bottomNavigationBar: AppBottomNav(
          currentIndex: _currentIndex,
          onSelect: _goToTab,
          // Tapping the destination you are already on returns that tab to its
          // root instead of doing nothing, so a sub-page is never a dead end.
          onReselect: _reselectTab,
        ),
      ),
    );
  }

  /// Index of the Home / Discover tab.
  static const int _homeTab = 0;

  /// Android back button, resolved against the tab stacks rather than the root
  /// navigator.
  ///
  /// 1. A sub-page is open on the active tab -> pop that tab's stack. This is
  ///    what takes the discover chevron sub-pages ("Top Genres", "Radio
  ///    Stations", ...) back to the front discover page.
  /// 2. Otherwise, if another tab is showing -> return to Home, mirroring the
  ///    nav bar.
  /// 3. At the Home root -> do nothing. Closing the app from inside a tab would
  ///    make a sub-page feel like a dead end, and losing a download or a
  ///    half-finished import to a stray back press is worse than a no-op.
  void _handleSystemBack() {
    if (TabNavigator.canPopTab(_currentIndex)) {
      TabNavigator.navigatorFor(_currentIndex)?.pop();
      return;
    }
    if (_currentIndex != _homeTab) {
      _goToTab(_homeTab);
    }
  }

  /// Draws one tab, animating it in when it is the target of the current switch
  /// and out when it is the tab being left behind.
  Widget _tabLayer(int i) {
    final tab = TabNavigator(tabIndex: i, root: _tabs[i]);
    final entering = i == _currentIndex;
    final leaving = i == _leavingIndex;

    if (!entering && (!leaving || _tabCtrl.isCompleted)) {
      return Offstage(child: TickerMode(enabled: false, child: tab));
    }

    final t = _tabAnim.value;
    final double opacity;
    final double dx;
    final double scale;
    if (entering) {
      opacity = 0.4 + 0.6 * t;
      dx = _slideDir * 0.22 * (1 - t);
      scale = 0.985 + 0.015 * t;
    } else {
      opacity = 1.0 - t;
      dx = -_slideDir * 0.22 * t;
      scale = 1.0 - 0.015 * t;
    }

    return IgnorePointer(
      // The incoming tab shouldn't take taps while it's still sliding in.
      ignoring: !entering || t < 1,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(dx, 0),
          child: Transform.scale(
            scale: scale,
            // Clip so the sliding tab doesn't paint over its neighbour.
            child: ClipRect(child: tab),
          ),
        ),
      ),
    );
  }
}

class _MainMiniPlayerWrapper extends StatelessWidget {
  const _MainMiniPlayerWrapper();
  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    if (player.currentTrack == null) return const SizedBox.shrink();
    return const SafeArea(top: false, child: MiniPlayer());
  }
}
