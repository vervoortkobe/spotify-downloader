import 'package:flutter/material.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

/// Circular play/pause button used on playlist rows (Imported + Storage tabs).
///
/// Reads as part of the row rather than a bare icon: a translucent chip by
/// default, Spotify-green while held, green-tinted when the row is the thing
/// currently playing, and a pause glyph in that state. The press scale is what
/// makes it feel tappable next to the static chevron.
class PlaylistPlayButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final double size;

  /// Row is the source of the currently playing track - tints the chip green
  /// and shows a pause glyph.
  final bool isPlaying;

  /// Row is the source but playback is paused.
  final bool isActive;

  final String tooltip;

  const PlaylistPlayButton({
    super.key,
    required this.onPressed,
    this.size = 40,
    this.isPlaying = false,
    this.isActive = false,
    this.tooltip = 'Play',
  });

  @override
  State<PlaylistPlayButton> createState() => _PlaylistPlayButtonState();
}

class _PlaylistPlayButtonState extends State<PlaylistPlayButton> {
  bool _held = false;

  bool get _enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final active = widget.isActive || widget.isPlaying;
    final Color background;
    final Color foreground;
    final Color border;

    if (!_enabled) {
      background = Colors.white.withValues(alpha: 0.04);
      foreground = SpotterfyTheme.mutedDark;
      border = Colors.white.withValues(alpha: 0.06);
    } else if (_held) {
      // Solid green on press, matching the now-playing transport button.
      background = SpotterfyTheme.primary;
      foreground = Colors.black;
      border = Colors.transparent;
    } else if (active) {
      background = SpotterfyTheme.primary.withValues(alpha: 0.18);
      foreground = SpotterfyTheme.primary;
      border = SpotterfyTheme.primary.withValues(alpha: 0.5);
    } else {
      background = Colors.white.withValues(alpha: 0.10);
      foreground = Colors.white;
      border = Colors.white.withValues(alpha: 0.14);
    }

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: _enabled,
        label: widget.tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled ? (_) => setState(() => _held = true) : null,
          onTapUp: _enabled ? (_) => setState(() => _held = false) : null,
          onTapCancel: _enabled ? () => setState(() => _held = false) : null,
          onTap: widget.onPressed,
          child: AnimatedScale(
            // Small press-in, so the button visibly acknowledges the tap
            // instead of only changing colour.
            scale: _held ? 0.9 : 1.0,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: background,
                shape: BoxShape.circle,
                border: Border.all(color: border),
                boxShadow: [
                  BoxShadow(
                    color: SpotterfyTheme.primary.withValues(
                      alpha: !_enabled
                          ? 0
                          : _held
                          ? 0.45
                          : active
                          ? 0.25
                          : 0,
                    ),
                    blurRadius: _held ? 16 : 10,
                  ),
                ],
              ),
              child: Icon(
                widget.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: foreground,
                size: widget.size * 0.55,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
