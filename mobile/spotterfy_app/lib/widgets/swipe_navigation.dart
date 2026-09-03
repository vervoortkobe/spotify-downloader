import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SwipeBackWrapper extends StatefulWidget {
  final Widget child;
  final bool enabled;
  const SwipeBackWrapper({super.key, required this.child, this.enabled = true});

  @override
  State<SwipeBackWrapper> createState() => _SwipeBackWrapperState();
}

class _SwipeBackWrapperState extends State<SwipeBackWrapper> {
  double _dragDx = 0;
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
          setState(() => _dragging = true);
        }
      },
      onHorizontalDragUpdate: (details) {
        if (!_dragging) return;
        setState(() => _dragDx = (details.globalPosition.dx).clamp(0, MediaQuery.of(context).size.width));
      },
      onHorizontalDragEnd: (details) {
        if (!_dragging) return;
        final velocity = details.primaryVelocity ?? 0;
        final shouldPop = _dragDx > 110 || velocity > 600;
        if (shouldPop) {
          HapticFeedback.lightImpact();
          Navigator.of(context).pop();
        }
        setState(() {
          _dragging = false;
          _dragDx = 0;
        });
      },
      onHorizontalDragCancel: () => setState(() { _dragging = false; _dragDx = 0; }),
      child: Stack(
        children: [
          widget.child,
          if (_dragging)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.only(left: (_dragDx / 5).clamp(0, 24)),
                  color: Colors.black.withValues(alpha: (_dragDx / 350).clamp(0, 0.18)),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: const Color(0xFF10b981), shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFF10b981).withValues(alpha: 0.4), blurRadius: 12)]),
                    child: Icon(Icons.arrow_back, color: Colors.white, size: 20, grade: 200),
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
  SlidePageRoute({required this.child})
      : super(
          transitionDuration: const Duration(milliseconds: 280),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, _, _) => child,
          transitionsBuilder: (_, anim, _, c) {
            final tween = Tween(begin: const Offset(0.12, 0), end: Offset.zero).chain(CurveTween(curve: Curves.easeOutCubic));
            final fade = Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut));
            return SlideTransition(
              position: anim.drive(tween),
              child: FadeTransition(opacity: anim.drive(fade), child: c),
            );
          },
        );
}

Route<T> swipeRoute<T>(Widget page) => SlidePageRoute(child: page) as Route<T>;
