import 'package:flutter/material.dart';
import 'package:spotterfy_app/widgets/queue_sheet.dart';
import 'package:spotterfy_app/widgets/storage_cover.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/screens/player_screen.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/main.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, this.showQueueButton = true});

  final bool showQueueButton;

  String _fmtDuration(int ms) {
    final minutes = ms ~/ 60000;
    final seconds = (ms % 60000) ~/ 1000;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final track = player.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final pos = player.position;
    // Prefer the player's live duration, but fall back to the length stored on
    // the track. Live radio reports no duration, and a track can be rendered
    // before just_audio has reported one - without this the mini player showed
    // 0:00.
    final durMs = player.duration.inMilliseconds > 0
        ? player.duration.inMilliseconds
        : track.durationMs;
    final dur = Duration(milliseconds: durMs);
    final progress = dur.inMilliseconds > 0
        ? pos.inMilliseconds / dur.inMilliseconds
        : 0.0;
    final bufferedFrac = dur.inMilliseconds > 0
        ? player.buffered.inMilliseconds / dur.inMilliseconds
        : 0.0;
    // Queue position lives on the now-playing screen; the mini player keeps
    // only title / artist / progress / controls so it stays readable.

    return Dismissible(
      key: ValueKey('mini-${track.id}'),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.4,
        DismissDirection.endToStart: 0.4,
      },
      // Swipe right -> previous, swipe left -> next. Returning false snaps the
      // card back so the mini player never leaves the footer.
      confirmDismiss: (dir) async {
        HapticFeedback.lightImpact();
        if (dir == DismissDirection.startToEnd) {
          await player.previous();
        } else {
          await player.next();
        }
        return false;
      },
      background: _SwipeRevealBackground(
        alignment: Alignment.centerLeft,
        icon: Icons.skip_previous,
        label: 'Previous',
      ),
      secondaryBackground: _SwipeRevealBackground(
        alignment: Alignment.centerRight,
        icon: Icons.skip_next,
        label: 'Next',
      ),
      child: GestureDetector(
        onTap: _openPlayer,
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) < -500) {
            HapticFeedback.mediumImpact();
            _openPlayer();
          }
        },
        onDoubleTap: () {
          HapticFeedback.lightImpact();
          player.togglePlayPause();
        },
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          decoration: BoxDecoration(
            color: SpotterfyTheme.card,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 22,
                offset: const Offset(0, -4),
              ),
            ],
            border: Border.all(
              color: SpotterfyTheme.primary.withValues(alpha: 0.18),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // drag handle
              Container(
                margin: const EdgeInsets.only(top: 7),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: SpotterfyTheme.muted.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // One row so the text, progress and time share a single baseline
              // instead of the time squeezing the title on narrow screens.
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
                child: Row(
                  children: [
                    Hero(
                      tag: 'mini-cover-${track.id}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 48,
                          height: 48,
                          color: SpotterfyTheme.surface,
                          child: _MiniCover(track: track),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            track.title,
                            style: const TextStyle(
                              color: SpotterfyTheme.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.artists,
                            style: const TextStyle(
                              color: SpotterfyTheme.muted,
                              fontSize: 12,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 7),
                          Row(
                            children: [
                              Expanded(
                                child: _MiniProgressBar(
                                  progress: progress,
                                  buffered: bufferedFrac,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${_fmtDuration(pos.inMilliseconds)} / ${_fmtDuration(dur.inMilliseconds)}',
                                style: const TextStyle(
                                  color: SpotterfyTheme.muted,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Roomier tap targets: 44px buttons with real spacing so
                    // they are easy to hit without crowding each other. The
                    // play/pause is the only filled + glowing control, so it
                    // reads as the primary one.
                    _MiniIconButton(
                      icon: player.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      tooltip: player.isPlaying ? 'Pause' : 'Play',
                      size: 42,
                      iconSize: 24,
                      background: SpotterfyTheme.primary,
                      glow: SpotterfyTheme.primary,
                      foreground: Colors.black,
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        player.togglePlayPause();
                      },
                    ),
                    if (showQueueButton && player.queue.length > 1) ...[
                      const SizedBox(width: 6),
                      // Same translucent white circle as the queue button on the
                      // now-playing page, so the two read as one control.
                      _MiniIconButton(
                        icon: Icons.queue_music_rounded,
                        tooltip: 'Queue',
                        size: 42,
                        iconSize: 21,
                        background: Colors.white.withValues(alpha: 0.10),
                        borderColor: Colors.white.withValues(alpha: 0.14),
                        foreground: Colors.white,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          showQueueSheet(context, player);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPlayer() {
    HapticFeedback.selectionClick();
    navigatorKey.currentState?.push(nowPlayingRoute(const PlayerScreen()));
  }
}

/// Thin buffered/progress bar used inside the mini player's text column.
class _MiniProgressBar extends StatelessWidget {
  final double progress;
  final double buffered;

  const _MiniProgressBar({required this.progress, required this.buffered});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 3,
        child: Stack(
          children: [
            Container(color: SpotterfyTheme.muted.withValues(alpha: 0.22)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: buffered.clamp(0.0, 1.0),
              child: Container(
                color: Colors.white.withValues(alpha: 0.28),
                height: 3,
              ),
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(color: SpotterfyTheme.primary, height: 3),
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular mini player control with a guaranteed 40px+ tap target.
class _MiniIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;
  final Color background;
  final Color foreground;

  /// Hairline rim, matching the circular controls on the now-playing page.
  final Color? borderColor;

  /// Soft coloured halo. Only the primary (play/pause) control uses it, so the
  /// eye lands there first.
  final Color? glow;

  const _MiniIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.size,
    required this.iconSize,
    required this.background,
    required this.foreground,
    this.borderColor,
    this.glow,
  });

  @override
  State<_MiniIconButton> createState() => _MiniIconButtonState();
}

class _MiniIconButtonState extends State<_MiniIconButton> {
  bool _held = false;

  @override
  Widget build(BuildContext context) {
    final glow = widget.glow;
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _held = true),
          onTapUp: (_) => setState(() => _held = false),
          onTapCancel: () => setState(() => _held = false),
          onTap: widget.onPressed,
          child: AnimatedScale(
            // Press-in, so the tap is acknowledged before the state changes.
            scale: _held ? 0.88 : 1.0,
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: _held && glow != null
                    ? Color.lerp(widget.background, Colors.white, 0.18)
                    : widget.background,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _held && glow != null
                      ? Colors.transparent
                      : (widget.borderColor ?? Colors.transparent),
                ),
                boxShadow: [
                  if (glow != null)
                    BoxShadow(
                      color: glow.withValues(alpha: _held ? 0.55 : 0.35),
                      blurRadius: _held ? 18 : 12,
                      spreadRadius: _held ? 1 : 0,
                    ),
                ],
              ),
              child: Icon(
                widget.icon,
                color: widget.foreground,
                size: widget.iconSize,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Revealed underneath the mini player while dragging it sideways.
class _SwipeRevealBackground extends StatelessWidget {
  final Alignment alignment;
  final IconData icon;
  final String label;

  const _SwipeRevealBackground({
    required this.alignment,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      decoration: BoxDecoration(
        color: SpotterfyTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: SpotterfyTheme.primary.withValues(alpha: 0.25),
        ),
      ),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: SpotterfyTheme.primary, size: 22),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: SpotterfyTheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniCover extends StatelessWidget {
  final dynamic track;
  const _MiniCover({required this.track});

  @override
  Widget build(BuildContext context) {
    if (track.cover != null && (track.cover as String).isNotEmpty) {
      return Image.network(
        track.cover as String,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.music_note, color: SpotterfyTheme.muted, size: 24),
      );
    }
    final String src = track.sourceUrl as String? ?? '';
    final bool isStorage =
        (track.id as String).startsWith('storage_') ||
        src.startsWith('/') ||
        src.startsWith('file://');
    if (isStorage && src.isNotEmpty) {
      return StorageCover(
        path: src.replaceFirst('file://', ''),
        size: 52,
        iconSize: 24,
        radius: 12,
      );
    }
    return const Icon(Icons.music_note, color: SpotterfyTheme.muted, size: 24);
  }
}
