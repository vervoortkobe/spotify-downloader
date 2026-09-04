import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final track = player.currentTrack;

    if (track == null) {
      return Scaffold(
        backgroundColor: SpotterfyTheme.background,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: Center(
          child: Text(
            'No track selected',
            style: TextStyle(color: SpotterfyTheme.muted),
          ),
        ),
      );
    }

    final pos = player.position;
    final dur = player.duration;
    final sliderVal = dur.inMilliseconds > 0
        ? pos.inMilliseconds / dur.inMilliseconds
        : 0.0;

    return SwipeBackWrapper(
      child: Scaffold(
        backgroundColor: SpotterfyTheme.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.keyboard_arrow_down, color: SpotterfyTheme.text),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.queue_music, color: SpotterfyTheme.text, size: 24),
              onPressed: () => _showQueueDialog(context, player, track),
            ),
          ],
        ),
      body: GestureDetector(
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 400) {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
          }
        },
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -600) { HapticFeedback.lightImpact(); player.next(); }
          else if (v > 600) { HapticFeedback.lightImpact(); player.previous(); }
        },
        onDoubleTap: () {
          HapticFeedback.mediumImpact();
          player.togglePlayPause();
        },
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: SpotterfyTheme.text.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2)))),
            const Spacer(flex: 1),
            Hero(
              tag: 'mini-cover-${track.id}',
              child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 280,
                height: 280,
                color: SpotterfyTheme.surface,
                child: track.cover.isNotEmpty
                    ? Image.network(
                        track.cover,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(
                          Icons.music_note,
                          color: SpotterfyTheme.muted,
                          size: 64,
                        ),
                      )
                    : Icon(
                        Icons.music_note,
                        color: SpotterfyTheme.muted,
                        size: 64,
                      ),
              ),
            )),
            const Spacer(flex: 1),
            Text(
              track.title,
              style: TextStyle(
                color: SpotterfyTheme.text,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              track.artists,
              style: TextStyle(color: SpotterfyTheme.muted, fontSize: 16),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                activeTrackColor: SpotterfyTheme.primary,
                inactiveTrackColor: SpotterfyTheme.card,
                thumbColor: SpotterfyTheme.primary,
              ),
              child: Slider(
                value: sliderVal.clamp(0.0, 1.0),
                onChanged: (v) {
                  final newPos = Duration(
                    milliseconds: (v * dur.inMilliseconds).round(),
                  );
                  player.seekTo(newPos);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _fmtDuration(pos),
                    style: TextStyle(
                      color: SpotterfyTheme.muted,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    _fmtDuration(dur),
                    style: TextStyle(
                      color: SpotterfyTheme.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () => player.previous(),
                  icon: Icon(
                    Icons.skip_previous,
                    color: SpotterfyTheme.text,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 28),
                GestureDetector(
                  onTap: () => player.togglePlayPause(),
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: SpotterfyTheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: SpotterfyTheme.primary.withValues(alpha: 0.3), blurRadius: 12)],
                    ),
                    child: Icon(
                      player.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.black,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(width: 28),
                IconButton(
                  onPressed: () => player.next(),
                  icon: Icon(
                    Icons.skip_next,
                    color: SpotterfyTheme.text,
                    size: 32,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${player.queue.indexOf(track) + 1} / ${player.queue.length} in queue',
              style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12, fontWeight: FontWeight.w500),
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
      ),
      ),
    );
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _showQueueDialog(BuildContext context, PlayerProvider player, TrackModel currentTrack) {
    showModalBottomSheet(
      context: context,
      backgroundColor: SpotterfyTheme.surface,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Up Next', style: TextStyle(color: SpotterfyTheme.text, fontSize: 18, fontWeight: FontWeight.bold)),
                  if (player.queue.length > 1)
                    TextButton(
                      onPressed: () => player.clearQueue(),
                      child: Text('Clear', style: TextStyle(color: SpotterfyTheme.primary, fontSize: 12)),
                    ),
                ],
              ),
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
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isCurrent ? SpotterfyTheme.card : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: SpotterfyTheme.card, width: isCurrent ? 0 : 0.5),
                      ),
                      child: Row(
                        children: [
                          if (isCurrent)
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: SpotterfyTheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.music_note, color: Colors.black, size: 14),
                            )
                          else
                            Icon(Icons.play_arrow, color: SpotterfyTheme.muted, size: 16),
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
                          if (!isCurrent)
                            IconButton(
                              icon: Icon(Icons.close, color: SpotterfyTheme.muted, size: 18),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                player.removeFromQueue(index);
                              },
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 12),
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
