import 'package:flutter/material.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

/// Three swaying bars that read as "this is the track playing now".
///
/// The centre bar is the long one and the outer two are short, so the shape is
/// recognisable at a glance even when the bars happen to be at the same height.
/// All three still change length as they move.
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

  /// Fractions of [size] each bar sits at, and how far it swings from there.
  ///
  /// The centre's *lowest* point (0.74 - 0.24 = 0.50) stays above the outer
  /// bars' *highest* (0.32 + 0.14 = 0.46), so the middle bar is always the long
  /// one no matter where the three are in their cycle.
  static const List<double> _base = [0.32, 0.74, 0.32];
  static const List<double> _swing = [0.14, 0.24, 0.14];

  /// Phase offsets, so the bars rise and fall out of step with each other
  /// instead of pulsing as one block.
  static const List<double> _phase = [0.0, 0.35, 0.7];

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
              final phase =
                  (_c.value + AnimatedEqualizer._phase[i]) % 1.0;
              // Triangle wave: up over the first half of the cycle, back down
              // over the second.
              final tri = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
              final h =
                  AnimatedEqualizer._base[i] +
                  AnimatedEqualizer._swing[i] * tri;
              return Container(
                width: widget.barWidth,
                height: widget.size * h,
                margin: const EdgeInsets.symmetric(horizontal: 1.2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(99),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
