import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

/// Bridges the bottom nav to [MainScreen] so pushed screens (e.g. a playlist)
/// can show the same nav bar and hand a tab switch back to it.
class TabNavController extends ChangeNotifier {
  int _currentIndex = 0;
  int? _pendingRequest;

  /// Index of the tab MainScreen is currently showing.
  int get currentIndex => _currentIndex;

  set currentIndex(int value) {
    if (_currentIndex == value) return;
    _currentIndex = value;
    notifyListeners();
  }

  /// Ask MainScreen to switch tabs (e.g. after popping back to it).
  void request(int index) {
    _pendingRequest = index;
    notifyListeners();
  }

  bool get hasPendingRequest => _pendingRequest != null;

  /// Returns and clears the pending tab request, if any.
  int? takePendingRequest() {
    final value = _pendingRequest;
    _pendingRequest = null;
    return value;
  }
}

final tabNavController = TabNavController();

/// The app's bottom navigation bar. Extracted so every screen that wants the
/// persistent footer renders exactly the same bar.
class AppBottomNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelect,
  });

  @override
  State<AppBottomNav> createState() => _AppBottomNavState();
}

class _AppBottomNavState extends State<AppBottomNav> {
  double _dragDx = 0;

  void _handleSwipe(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    if (v < -400 || _dragDx < -72) {
      HapticFeedback.lightImpact();
      widget.onSelect(widget.currentIndex + 1);
    } else if (v > 400 || _dragDx > 72) {
      HapticFeedback.lightImpact();
      widget.onSelect(widget.currentIndex - 1);
    }
    _dragDx = 0;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Swipe left/right on the navbar to switch tabs (swipe left -> next tab).
      // Tracks drag distance too, so slow deliberate swipes work, not just flicks.
      onHorizontalDragStart: (_) => _dragDx = 0,
      onHorizontalDragUpdate: (details) => _dragDx += details.delta.dx,
      onHorizontalDragEnd: _handleSwipe,
      child: NavigationBarTheme(
        data: const NavigationBarThemeData(height: 80),
        child: NavigationBar(
          backgroundColor: const Color(0xFF121212),
          indicatorColor: SpotterfyTheme.primary.withValues(alpha: 0.15),
          selectedIndex: widget.currentIndex.clamp(0, 3),
          onDestinationSelected: widget.onSelect,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.explore_outlined, color: Colors.white), selectedIcon: Icon(Icons.explore, color: Colors.white), label: 'Discover'),
            NavigationDestination(icon: Icon(Icons.search, color: Colors.white), selectedIcon: Icon(Icons.search, color: Colors.white), label: 'Search'),
            NavigationDestination(icon: Icon(Icons.library_music_outlined, color: Colors.white), selectedIcon: Icon(Icons.library_music, color: Colors.white), label: 'Library'),
            NavigationDestination(icon: Icon(Icons.forum_outlined, color: Colors.white), selectedIcon: Icon(Icons.forum, color: Colors.white), label: 'Chat'),
          ],
        ),
      ),
    );
  }
}

/// Mini player + bottom nav stacked, for screens pushed on top of MainScreen
/// that should keep the persistent footer visible.
class PersistentBottomArea extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final Widget miniPlayer;

  const PersistentBottomArea({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.miniPlayer,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        miniPlayer,
        AppBottomNav(currentIndex: currentIndex, onSelect: onSelect),
      ],
    );
  }
}
