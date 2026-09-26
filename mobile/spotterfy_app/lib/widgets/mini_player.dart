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
    final progress = dur.inMilliseconds > 0 ? pos.inMilliseconds / dur.inMilliseconds : 0.0;
    final bufferedFrac = dur.inMilliseconds > 0 ? player.buffered.inMilliseconds / dur.inMilliseconds : 0.0;
    final queueLen = player.queue.length;
    final idx = player.queue.indexOf(track);
    final queuePos = queueLen > 0 && idx >= 0 ? '${idx + 1}/$queueLen' : '';

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
        onTap: () => navigatorKey.currentState?.push(swipeRoute(const PlayerScreen())),
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) < -500) {
            HapticFeedback.mediumImpact();
            navigatorKey.currentState?.push(swipeRoute(const PlayerScreen()));
          }
        },
        onDoubleTap: () {
          HapticFeedback.lightImpact();
          player.togglePlayPause();
        },
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          decoration: BoxDecoration(
            color: SpotterfyTheme.card,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, -4)),
          ],
          border: Border.all(color: SpotterfyTheme.primary.withValues(alpha: 0.15), width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // drag handle
            Container(
              margin: const EdgeInsets.only(top: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: SpotterfyTheme.muted.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 6),
              child: Row(
                children: [
                  Hero(
                    tag: 'mini-cover-${track.id}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 52,
                        height: 52,
                        color: SpotterfyTheme.surface,
                        child: _MiniCover(track: track),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(track.title, style: TextStyle(color: SpotterfyTheme.text, fontSize: 14, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 1),
                        Text(track.artists, style: TextStyle(color: SpotterfyTheme.muted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (queuePos.isNotEmpty)
                          GestureDetector(
                            onTap: showQueueButton ? () {
                              HapticFeedback.lightImpact();
                              _showQueueDialog(context, player);
                            } : null,
                            child: Text(queuePos, style: TextStyle(color: SpotterfyTheme.primary, fontSize: 10, fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                  ),
                  // progress time
                  Text('${_fmtDuration(pos.inMilliseconds)} / ${_fmtDuration(dur.inMilliseconds)}', style: TextStyle(color: SpotterfyTheme.muted, fontSize: 10)),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onLongPress: () => HapticFeedback.lightImpact(),
                    child: Container(
                      decoration: BoxDecoration(color: SpotterfyTheme.primary, shape: BoxShape.circle),
                      child: IconButton(onPressed: () => player.togglePlayPause(), icon: Icon(player.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.black, size: 20), padding: const EdgeInsets.all(5), constraints: const BoxConstraints()),
                    ),
                  ),
                  if (showQueueButton && player.queue.length > 1)
                    GestureDetector(
                      onTap: () => _showQueueDialog(context, player),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(color: SpotterfyTheme.primary.withAlpha(15), shape: BoxShape.circle),
                        child: Icon(Icons.queue_music, color: SpotterfyTheme.primary, size: 16),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: SizedBox(
                  height: 3,
                  child: Stack(children: [
                    Container(color: SpotterfyTheme.muted.withValues(alpha: 0.2)),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: bufferedFrac.clamp(0.0, 1.0),
                      child: Container(color: Colors.white.withValues(alpha: 0.3), height: 3),
                    ),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress.clamp(0.0, 1.0),
                      child: Container(color: SpotterfyTheme.primary, height: 3),
                    ),
                  ]),
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
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
              Text('Up Next', style: TextStyle(color: SpotterfyTheme.text, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              if (player.queue.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text('No tracks in queue', style: TextStyle(color: SpotterfyTheme.muted)),
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
                        color: isCurrent ? SpotterfyTheme.card : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          isCurrent && player.isPlaying
                              ? const AnimatedEqualizer(size: 18, color: SpotterfyTheme.primary)
                              : Icon(
                                  isCurrent ? Icons.music_note : Icons.play_arrow,
                                  color: isCurrent ? SpotterfyTheme.primary : Colors.white,
                                  size: 20,
                                ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(track.title, style: TextStyle(
                                  color: isCurrent ? SpotterfyTheme.text : SpotterfyTheme.muted,
                                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                                ), maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text(track.artists, style: TextStyle(
                                  color: isCurrent ? SpotterfyTheme.muted : SpotterfyTheme.mutedDark,
                                  fontSize: 12,
                                ), maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          if (index != player.currentIndex)
                            IconButton(
                              icon: Icon(Icons.close, color: Colors.white, size: 18),
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
                  child: Text('Close', style: TextStyle(color: SpotterfyTheme.muted)),
                ),
              ),
            ],
          ),
        );
      },
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
        border: Border.all(color: SpotterfyTheme.primary.withValues(alpha: 0.25)),
      ),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: SpotterfyTheme.primary, size: 22),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: SpotterfyTheme.primary, fontSize: 12, fontWeight: FontWeight.w700)),
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
      return Image.network(track.cover as String, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (context, error, stackTrace) => const Icon(Icons.music_note, color: SpotterfyTheme.muted, size: 24));
    }
    final String src = track.sourceUrl as String? ?? '';
    final bool isStorage = (track.id as String).startsWith('storage_') || src.startsWith('/') || src.startsWith('file://');
    if (isStorage && src.isNotEmpty) {
      return StorageCover(path: src.replaceFirst('file://', ''), size: 52, iconSize: 24, radius: 12);
    }
    return const Icon(Icons.music_note, color: SpotterfyTheme.muted, size: 24);
  }
}
