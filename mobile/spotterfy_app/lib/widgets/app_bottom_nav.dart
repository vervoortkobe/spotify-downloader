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

  /// Posts "user tapped tab [index]" to whichever navigator owns that tab.
  ///
  /// Tabs live in per-tab [Navigator]s, and that navigator is not the one under
  /// the navbar when a sub-page is open, so a pushed screen cannot reach it
  /// directly. MainScreen registers them here on first build.
  final Map<int, NavigatorState> _navigators = {};

  void registerNavigator(int index, NavigatorState? state) {
    if (state == null) {
      _navigators.remove(index);
      return;
    }
    _navigators[index] = state;
  }

  /// Tapping the nav destination for the tab you are already on pops that tab
  /// back to its root, the same way tapping a folder in a file manager does.
  ///
  /// A no-op when the tab is already at its root, so re-tapping the current
  /// destination does nothing rather than rebuilding the page.
  void onDestinationTapped(int index) {
    final nav = _navigators[index];
    if (nav == null || !nav.canPop()) return;
    HapticFeedback.selectionClick();
    nav.popUntil((route) => route.isFirst);
  }
}

final tabNavController = TabNavController();

/// The app's bottom navigation bar. Extracted so every screen that wants the
/// persistent footer renders exactly the same bar.
class AppBottomNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;

  /// Called when the destination for the already-active tab is tapped.
  final ValueChanged<int>? onReselect;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    this.onReselect,
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
        data: NavigationBarThemeData(height: 80),
        child: NavigationBar(
          backgroundColor: Color(0xFF121212),
          indicatorColor: SpotterfyTheme.primary.withValues(alpha: 0.15),
          selectedIndex: widget.currentIndex.clamp(0, 3),
          // Reselecting the tab you are already on pops that tab back to its
          // root, so a pushed sub-page is never a dead end.
          onDestinationSelected: (i) {
            if (i == widget.currentIndex) {
              widget.onReselect?.call(i);
            } else {
              widget.onSelect(i);
            }
          },
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            NavigationDestination(
              icon: Icon(Icons.explore_outlined, color: SpotterfyTheme.text),
              selectedIcon: Icon(Icons.explore, color: SpotterfyTheme.text),
              label: 'Discover',
            ),
            NavigationDestination(
              icon: Icon(Icons.search, color: SpotterfyTheme.text),
              selectedIcon: Icon(Icons.search, color: SpotterfyTheme.text),
              label: 'Search',
            ),
            NavigationDestination(
              icon: Icon(
                Icons.library_music_outlined,
                color: SpotterfyTheme.text,
              ),
              selectedIcon: Icon(
                Icons.library_music,
                color: SpotterfyTheme.text,
              ),
              label: 'Library',
            ),
            NavigationDestination(
              icon: Icon(Icons.forum_outlined, color: SpotterfyTheme.text),
              selectedIcon: Icon(Icons.forum, color: SpotterfyTheme.text),
              label: 'Chat',
            ),
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
