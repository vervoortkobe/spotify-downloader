import 'package:flutter/material.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

/// Round, translucent chip for a secondary header/toolbar action.
///
/// Matches the mini player's controls and the playlist header's secondary
/// buttons - a faint overlay fill with a hairline rim - so it reads as part of
/// the bar rather than a standout button next to a green play chip.
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  /// Green tint for an active state (e.g. a non-default sort).
  final bool active;

  final double size;

  const RoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final Color background;
    final Color border;
    final Color foreground;
    if (active) {
      background = SpotterfyTheme.primary.withValues(alpha: 0.18);
      border = SpotterfyTheme.primary.withValues(alpha: 0.5);
      foreground = SpotterfyTheme.primary;
    } else if (!enabled) {
      background = SpotterfyTheme.overlay(0.04);
      border = SpotterfyTheme.overlay(0.06);
      foreground = SpotterfyTheme.mutedDark;
    } else {
      background = SpotterfyTheme.overlay(0.10);
      border = SpotterfyTheme.overlay(0.14);
      foreground = SpotterfyTheme.text;
    }
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: CircleBorder(side: BorderSide(color: border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: foreground, size: size * 0.46),
          ),
        ),
      ),
    );
  }
}
