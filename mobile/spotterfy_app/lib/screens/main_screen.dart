import 'package:flutter/material.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'library_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const SearchScreen(),
    const LibraryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: SpotterfyTheme.surface,
        selectedItemColor: SpotterfyTheme.primary,
        unselectedItemColor: SpotterfyTheme.muted,
        selectedLabelStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.normal,
        ),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home, size: 24),
            activeIcon: const Icon(Icons.home_filled, size: 24),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.search, size: 24),
            activeIcon: const Icon(Icons.search, size: 24),
            label: 'Search',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.library_music, size: 24),
            activeIcon: const Icon(Icons.library_music, size: 24),
            label: 'Library',
          ),
        ],
      ),
    );
  }
}
