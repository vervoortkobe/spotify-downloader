import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/widgets/mini_player.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import 'downloads_screen.dart';
import 'queue_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  late PageController _pageController;

  final List<Widget> _screens = const [
    HomeScreen(),
    SearchScreen(),
    LibraryScreen(),
    DownloadsScreen(),
    QueueScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTap(int i) {
    setState(() => _currentIndex = i);
    _pageController.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotterfyTheme.background,
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            children: _screens,
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: _MainMiniPlayerWrapper()),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF0f1d17).withValues(alpha: 0.95),
        indicatorColor: SpotterfyTheme.primary.withValues(alpha: 0.15),
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTap,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.search), selectedIcon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: 'Library'),
          NavigationDestination(icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: 'Downloads'),
          NavigationDestination(icon: Icon(Icons.queue_music_outlined), selectedIcon: Icon(Icons.queue_music), label: 'Queue'),
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
