import 'package:flutter/material.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

/// Three staggered bouncing bars, matching the frontend's smooth-bounce
/// playing indicator.
class AnimatedEqualizer extends StatefulWidget {
  const AnimatedEqualizer({
    super.key,
    this.color,
    this.size = 18,
    this.barWidth = 3,
    this.animating = true,
  });
  final Color? color;
  final double size;
  final double barWidth;

  /// Whether the bars sway. Driven by playback state: a paused track keeps the
  /// same bars in the same place instead of animating as if it were playing.
  final bool animating;

  /// Heights and start delays match the frontend's three-bar bounce.
  static const List<double> _height = [0.72, 1.0, 0.58];
  static const List<double> _delay = [0.0, 0.167, 0.333];

  /// One full cycle. Deliberately slow: this is mood, not a progress spinner.
  static const Duration _cycle = Duration(milliseconds: 900);

  @override
  State<AnimatedEqualizer> createState() => _AnimatedEqualizerState();
}

class _AnimatedEqualizerState extends State<AnimatedEqualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: AnimatedEqualizer._cycle);
    if (widget.animating) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant AnimatedEqualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animating == oldWidget.animating) return;
    if (widget.animating) {
      _c.repeat();
    } else {
      // Freeze mid-sway rather than snapping to a fixed pose, so resuming
      // playback continues from where the bars were.
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? SpotterfyTheme.primary;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              final phase = (_c.value - AnimatedEqualizer._delay[i]) % 1.0;
              final bounce = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
              return Transform.translate(
                offset: Offset(
                  0,
                  -widget.size * 0.44 * Curves.easeInOut.transform(bounce),
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: widget.barWidth,
                    height: widget.size * AnimatedEqualizer._height[i],
                    margin: const EdgeInsets.symmetric(horizontal: 1.2),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
