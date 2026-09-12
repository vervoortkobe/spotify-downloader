import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
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

  final List<Widget> _screens = const [
    SearchScreen(), // Home - Discover
    YtSearchScreen(), // Search - YT
    LibraryScreen(), // Library - playlists + storage
    JamScreen(), // Chat
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotterfyTheme.background,
      body: GestureDetector(
        // Swipe left/right to switch bottom-nav tabs (natural: swipe left -> next tab to the right)
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v < -400 && _currentIndex < _screens.length - 1) {
            setState(() => _currentIndex += 1);
          } else if (v > 400 && _currentIndex > 0) {
            setState(() => _currentIndex -= 1);
          }
        },
        child: Stack(
          children: [
            IndexedStack(index: _currentIndex, children: _screens),
            const Positioned(left: 0, right: 0, bottom: 0, child: _MainMiniPlayerWrapper()),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF121212),
        indicatorColor: SpotterfyTheme.primary.withValues(alpha: 0.15),
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.explore_outlined, color: Colors.white), selectedIcon: Icon(Icons.explore, color: Colors.white), label: 'Discover'),
          NavigationDestination(icon: Icon(Icons.search, color: Colors.white), selectedIcon: Icon(Icons.search, color: Colors.white), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.library_music_outlined, color: Colors.white), selectedIcon: Icon(Icons.library_music, color: Colors.white), label: 'Library'),
          NavigationDestination(icon: Icon(Icons.forum_outlined, color: Colors.white), selectedIcon: Icon(Icons.forum, color: Colors.white), label: 'Chat'),
        ],
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
