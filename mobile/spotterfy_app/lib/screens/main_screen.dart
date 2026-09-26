import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/services/network_stats_service.dart';
import 'package:spotterfy_app/widgets/app_bottom_nav.dart';
import 'package:spotterfy_app/widgets/mini_player.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import 'yt_search_screen.dart';
import 'jam_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 2;
  int _slideDir = 1;

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

  final List<Widget> _screens = const [
    SearchScreen(), // Home - Discover
    YtSearchScreen(), // Search - YT
    LibraryScreen(), // Library - playlists + storage
    JamScreen(), // Chat
  ];

  void _goToTab(int i) {
    if (i == _currentIndex || i < 0 || i >= _screens.length) return;
    setState(() {
      _slideDir = i > _currentIndex ? 1 : -1;
      _currentIndex = i;
    });
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
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            reverseDuration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutQuint,
            switchOutCurve: Curves.easeInQuad,
            layoutBuilder: (currentChild, previousChildren) => Stack(
              children: [...previousChildren, ?currentChild],
            ),
            transitionBuilder: (child, animation) {
              final slide = Tween<Offset>(begin: Offset(0.22 * _slideDir, 0), end: Offset.zero).animate(animation);
              final fade = Tween<double>(begin: 0.4, end: 1.0).animate(animation);
              final scale = Tween<double>(begin: 0.985, end: 1.0).animate(animation);
              return ClipRect(
                child: SlideTransition(
                  position: slide,
                  child: FadeTransition(
                    opacity: fade,
                    child: ScaleTransition(scale: scale, child: child),
                  ),
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey<int>(_currentIndex),
              child: IndexedStack(index: _currentIndex, children: _screens),
            ),
          ),
          const Positioned(left: 0, right: 0, bottom: 0, child: _MainMiniPlayerWrapper()),
        ],
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: _currentIndex,
        onSelect: _goToTab,
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
