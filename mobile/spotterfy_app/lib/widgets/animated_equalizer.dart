import 'package:flutter/material.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

class AnimatedEqualizer extends StatefulWidget {
  const AnimatedEqualizer({super.key, this.color, this.size = 18, this.barWidth = 3});
  final Color? color;
  final double size;
  final double barWidth;

  @override
  State<AnimatedEqualizer> createState() => _AnimatedEqualizerState();
}

class _AnimatedEqualizerState extends State<AnimatedEqualizer> with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat();
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
          final heights = <double>[];
          for (int i = 0; i < 3; i++) {
            final phase = (_c.value + i * 0.33) % 1.0;
            final tri = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
            heights.add(0.3 + 0.7 * tri);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) {
              return Container(
                width: widget.barWidth,
                height: widget.size * heights[i],
                margin: const EdgeInsets.symmetric(horizontal: 1.2),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(99)),
              );
            }),
          );
        },
      ),
    );
  }
}