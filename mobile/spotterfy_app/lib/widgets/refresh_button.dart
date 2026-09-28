import 'dart:math';

import 'package:flutter/material.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

/// Icon-only refresh control with a caption underneath and a tooltip.
///
/// The caption sits *below* the glyph rather than inside the button, which
/// keeps the tap target a comfortable 44px while still labelling what the
/// icon does.
class RefreshTileButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final bool busy;
  final List<String> tooltips;
  final Color? color;

  const RefreshTileButton({
    super.key,
    required this.onPressed,
    this.label = 'Refresh',
    this.busy = false,
    this.tooltips = defaultTooltips,
    this.color,
  });

  /// Pool of tooltips; one is picked at random per instance.
  static const List<String> defaultTooltips = [
    'Still there? Tap to shake it loose.',
    'Nothing happening? Give it a poke.',
    'Reticulating splines... or trying again.',
    'A nudge, not a shove.',
    'If it is stuck, this unsticks it.',
    'One more go?',
    'Turn it off and on again, but classier.',
    'Percy, refresh yourself.',
  ];

  @override
  Widget build(BuildContext context) {
    final tint = color ?? SpotterfyTheme.muted;
    return Tooltip(
      // Randomised per mount, so the hint doesn't feel like boilerplate.
      message: tooltips[Random().nextInt(tooltips.length)],
      child: InkWell(
        onTap: busy ? null : onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 44px box keeps the tap target compliant even though the glyph
              // itself is small.
              SizedBox(
                width: 44,
                height: 44,
                child: busy
                    ? Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: tint,
                          ),
                        ),
                      )
                    : Icon(Icons.refresh_rounded, size: 26, color: tint),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: tint,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
