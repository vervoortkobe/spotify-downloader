import 'package:flutter/material.dart';
import 'package:spotterfy_app/widgets/storage_cover.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/screens/player_screen.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/animated_equalizer.dart';
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
    final dur = player.duration;
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
                    // they are easy to hit without crowding each other.
                    _MiniIconButton(
                      icon: player.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      tooltip: player.isPlaying ? 'Pause' : 'Play',
                      size: 42,
                      iconSize: 22,
                      background: SpotterfyTheme.primary,
                      foreground: Colors.black,
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        player.togglePlayPause();
                      },
                    ),
                    if (showQueueButton && player.queue.length > 1) ...[
                      const SizedBox(width: 6),
                      _MiniIconButton(
                        icon: Icons.queue_music_rounded,
                        tooltip: 'Queue',
                        size: 40,
                        iconSize: 19,
                        background: SpotterfyTheme.primary.withValues(
                          alpha: 0.14,
                        ),
                        foreground: SpotterfyTheme.primary,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _showQueueDialog(context, player);
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

  void _showQueueDialog(BuildContext context, PlayerProvider player) {
    showModalBottomSheet(
      context: context,
      backgroundColor: SpotterfyTheme.surface,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Up Next',
                style: TextStyle(
                  color: SpotterfyTheme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              if (player.queue.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'No tracks in queue',
                    style: TextStyle(color: SpotterfyTheme.muted),
                  ),
                )
              else
                ...player.queue.asMap().entries.map((entry) {
                  final index = entry.key;
                  final track = entry.value;
                  final isCurrent = player.currentIndex == index;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      player.playFromQueue(index);
                      Navigator.pop(context);
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? SpotterfyTheme.card
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          isCurrent && player.isPlaying
                              ? const AnimatedEqualizer(
                                  size: 18,
                                  color: SpotterfyTheme.primary,
                                )
                              : Icon(
                                  isCurrent
                                      ? Icons.music_note
                                      : Icons.play_arrow,
                                  color: isCurrent
                                      ? SpotterfyTheme.primary
                                      : Colors.white,
                                  size: 20,
                                ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  style: TextStyle(
                                    color: isCurrent
                                        ? SpotterfyTheme.text
                                        : SpotterfyTheme.muted,
                                    fontWeight: isCurrent
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  track.artists,
                                  style: TextStyle(
                                    color: isCurrent
                                        ? SpotterfyTheme.muted
                                        : SpotterfyTheme.mutedDark,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (index != player.currentIndex)
                            IconButton(
                              icon: Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 18,
                              ),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                player.removeFromQueue(index);
                                Navigator.pop(context);
                              },
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Close',
                    style: TextStyle(color: SpotterfyTheme.muted),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
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
class _MiniIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;
  final Color background;
  final Color foreground;

  const _MiniIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.size,
    required this.iconSize,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: foreground, size: iconSize),
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
