import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

const pageTransitionDuration = Duration(milliseconds: 400);

class SwipeBackWrapper extends StatefulWidget {
  final Widget child;
  final bool enabled;
  const SwipeBackWrapper({super.key, required this.child, this.enabled = true});

  @override
  State<SwipeBackWrapper> createState() => _SwipeBackWrapperState();
}

class _SwipeBackWrapperState extends State<SwipeBackWrapper> {
  double _dragDx = 0;
  double _startDx = 0;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || !Navigator.canPop(context)) {
      return widget.child;
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (details) {
        if (details.globalPosition.dx < 36) {
          _startDx = details.globalPosition.dx;
          setState(() => _dragging = true);
        }
      },
      onHorizontalDragUpdate: (details) {
        if (!_dragging) return;
        final delta = details.globalPosition.dx - _startDx;
        // Only track rightward swipes; left swipe should cancel
        if (delta < 0) {
          setState(() => _dragDx = 0);
          return;
        }
        setState(
          () => _dragDx = delta.clamp(0, MediaQuery.of(context).size.width),
        );
      },
      onHorizontalDragEnd: (details) {
        if (!_dragging) return;
        final velocity = details.primaryVelocity ?? 0;
        // Only pop on rightward swipe: positive distance or positive velocity
        final shouldPop = (_dragDx > 90 && velocity >= 0) || velocity > 500;
        if (shouldPop && _dragDx > 0) {
          HapticFeedback.lightImpact();
          Navigator.of(context).pop();
        }
        setState(() {
          _dragging = false;
          _dragDx = 0;
          _startDx = 0;
        });
      },
      onHorizontalDragCancel: () => setState(() {
        _dragging = false;
        _dragDx = 0;
        _startDx = 0;
      }),
      child: Stack(
        children: [
          widget.child,
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.only(left: (_dragDx / 5).clamp(0, 24)),
                  color: Colors.black.withValues(
                    alpha: (_dragDx / 350).clamp(0, 0.18),
                  ),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: SpotterfyTheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: SpotterfyTheme.primary.withValues(alpha: 0.4),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.arrow_back,
                      color: SpotterfyTheme.text,
                      size: 20,
                      grade: 200,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SlidePageRoute extends PageRouteBuilder {
  final Widget child;
  SlidePageRoute({required this.child, super.settings})
    : super(
        transitionDuration: pageTransitionDuration,
        reverseTransitionDuration: pageTransitionDuration,
        pageBuilder: (_, _, _) => child,
        transitionsBuilder: (_, anim, _, c) {
          final tween = Tween(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic));
          final fade = Tween(
            begin: 0.0,
            end: 1.0,
          ).chain(CurveTween(curve: Curves.easeOut));
          return SlideTransition(
            position: anim.drive(tween),
            child: FadeTransition(opacity: anim.drive(fade), child: c),
          );
        },
      );
}

Route<T> swipeRoute<T>(Widget page, {RouteSettings? settings}) =>
    SlidePageRoute(child: page, settings: settings) as Route<T>;

class NowPlayingPageRoute extends PageRouteBuilder {
  NowPlayingPageRoute({required Widget child})
    : super(
        transitionDuration: pageTransitionDuration,
        reverseTransitionDuration: pageTransitionDuration,
        pageBuilder: (_, _, _) => child,
        transitionsBuilder: (_, animation, _, child) {
          // The cover travels on its own via the shared Hero, so the page
          // deliberately does NOT slide: sliding dragged the whole block of
          // buttons up/down with it, which read as everything moving at once.
          // Instead the page stays put and fades in only once the cover has
          // (mostly) landed - and fades out first on the way back, so all you
          // see then is the cover shrinking home to the mini player.
          final fade = CurvedAnimation(
            parent: animation,
            curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
          );
          return FadeTransition(opacity: fade, child: child);
        },
      );
}

/// Opens Now Playing from the bottom while keeping the shared 240 ms timing.
Route<T> nowPlayingRoute<T>(Widget page) =>
    NowPlayingPageRoute(child: page) as Route<T>;
