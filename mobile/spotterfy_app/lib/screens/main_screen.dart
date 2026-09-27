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
    duration: const Duration(milliseconds: 300),
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
    // A pushed screen asked to switch tabs (e.g. tapped a nav destination).
    if (tabNavController.hasPendingRequest) {
      final target = tabNavController.takePendingRequest();
      if (target != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _goToTab(target);
        });
      }
    }

    return Scaffold(
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
                children: [for (var i = 0; i < _tabs.length; i++) _tabLayer(i)],
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
      ),
    );
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
