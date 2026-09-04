import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final track = player.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final pos = player.position;
    final dur = player.duration;
    final progress = dur.inMilliseconds > 0 ? pos.inMilliseconds / dur.inMilliseconds : 0.0;
    final queueLen = player.queue.length;
    final idx = player.queue.indexOf(track);
    final queuePos = queueLen > 0 && idx >= 0 ? '${idx + 1}/$queueLen' : '';

    return Dismissible(
      key: ValueKey('mini-${track.id}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (dir) async {
        HapticFeedback.lightImpact();
        if (dir == DismissDirection.startToEnd) {
          await player.previous();
        } else {
          await player.next();
        }
        return false;
      },
      background: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(color: SpotterfyTheme.surface, borderRadius: BorderRadius.circular(16)),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 28),
        child: Icon(Icons.skip_previous, color: SpotterfyTheme.primary, size: 20),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(color: SpotterfyTheme.surface, borderRadius: BorderRadius.circular(16)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 28),
        child: Icon(Icons.skip_next, color: SpotterfyTheme.primary, size: 20),
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
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: SpotterfyTheme.card,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, -4)),
            ],
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
                padding: const EdgeInsets.fromLTRB(10, 6, 8, 10),
                child: Row(
                  children: [
                    Hero(
                      tag: 'mini-cover-${track.id}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 52,
                          height: 52,
                          color: SpotterfyTheme.surface,
                          child: track.cover.isNotEmpty
                              ? Image.network(track.cover, fit: BoxFit.cover, errorBuilder: (_, _, _) => Icon(Icons.music_note, color: SpotterfyTheme.muted, size: 24))
                              : Icon(Icons.music_note, color: SpotterfyTheme.muted, size: 24),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(track.title, style: TextStyle(color: SpotterfyTheme.text, fontSize: 14, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(track.artists, style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (queuePos.isNotEmpty) 
                            GestureDetector(
                              onTap: showQueueButton ? () {
                                // Show queue popup or navigate to queue screen
                                HapticFeedback.lightImpact();
                                _showQueueDialog(context, player);
                              } : null,
                              child: Text(queuePos, style: TextStyle(color: SpotterfyTheme.primary, fontSize: 10, fontWeight: FontWeight.w600)),
                            ),
                        ],
                      ),
                    ),
                    IconButton(onPressed: () => player.previous(), icon: Icon(Icons.skip_previous, color: SpotterfyTheme.muted, size: 22), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                    const SizedBox(width: 2),
                    GestureDetector(
                      onLongPress: () => HapticFeedback.lightImpact(),
                      child: Container(
                        decoration: BoxDecoration(color: SpotterfyTheme.primary, shape: BoxShape.circle),
                        child: IconButton(onPressed: () => player.togglePlayPause(), icon: Icon(player.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.black, size: 22), padding: const EdgeInsets.all(6), constraints: const BoxConstraints()),
                      ),
                    ),
                    const SizedBox(width: 2),
                    IconButton(onPressed: () => player.next(), icon: Icon(Icons.skip_next, color: SpotterfyTheme.muted, size: 22), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                    const SizedBox(width: 4),
                    if (showQueueButton && player.queue.length > 1)
                      GestureDetector(
                        onTap: () => _showQueueDialog(context, player),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: SpotterfyTheme.primary.withAlpha(15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.queue_music, color: SpotterfyTheme.primary, size: 18),
                        ),
                      ),
                  ],
                ),
              ),
              ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                child: SizedBox(
                  height: 2,
                  child: Stack(children: [
                    Container(color: SpotterfyTheme.muted.withValues(alpha: 0.2)),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress.clamp(0.0, 1.0),
                      child: Container(color: SpotterfyTheme.primary, height: 2),
                    ),
                  ]),
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
                          Icon(
                            isCurrent ? Icons.music_note : Icons.play_arrow,
                            color: isCurrent ? SpotterfyTheme.primary : SpotterfyTheme.muted,
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
                              icon: Icon(Icons.close, color: SpotterfyTheme.muted, size: 18),
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
