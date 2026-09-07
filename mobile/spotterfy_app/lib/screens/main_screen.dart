import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/providers/auth_provider.dart';
import 'package:spotterfy_app/providers/playlist_provider.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/widgets/mini_player.dart';
import 'search_screen.dart';
import 'library_screen.dart';
import 'storage_screen.dart';
import 'queue_screen.dart';
import 'jam_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  late PageController _pageController;

  final List<Widget> _screens = const [
    SearchScreen(), // Discover
    LibraryScreen(), // Playlists
    StorageScreen(), // Storage
    QueueScreen(), // Queue
    JamScreen(), // Chat
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this, initialIndex: 1);
    _pageController = PageController(initialPage: 1);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _pageController.animateToPage(_tabController.index, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
      }
    });

    // Load playlists on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.user != null) {
        context.read<PlaylistProvider>().loadPlaylists(auth.user!.uid);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpotterfyTheme.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: SafeArea(
          child: Container(
            color: SpotterfyTheme.background,
            child: TabBar(
              controller: _tabController,
              onTap: (i) => _pageController.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic),
              isScrollable: true,
              tabAlignment: TabAlignment.center,
              labelColor: Colors.white,
              unselectedLabelColor: SpotterfyTheme.muted,
              indicatorColor: SpotterfyTheme.primary,
              indicatorWeight: 2.5,
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.2),
              unselectedLabelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              tabs: const [
                Tab(text: 'Discover'),
                Tab(text: 'Playlists'),
                Tab(text: 'Storage'),
                Tab(text: 'Queue'),
                Tab(text: 'Chat'),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            onPageChanged: (i) {
              _tabController.animateTo(i, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
            },
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            children: _screens,
          ),
          const Positioned(left: 0, right: 0, bottom: 0, child: _MainMiniPlayerWrapper()),
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
