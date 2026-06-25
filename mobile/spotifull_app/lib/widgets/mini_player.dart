import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotifull_app/providers/player_provider.dart';
import 'package:spotifull_app/screens/player_screen.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

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

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PlayerScreen()),
      ),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: const Color(0xFF0f1d17),
          border: Border(
            top: BorderSide(color: const Color(0xFF1a3a2a), width: 1),
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 44,
                      height: 44,
                      color: const Color(0xFF1a3a2a),
                      child: track.cover.isNotEmpty
                          ? Image.network(
                              track.cover,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.music_note,
                                color: Color(0xFF3f3f46),
                                size: 24,
                              ),
                            )
                          : const Icon(
                              Icons.music_note,
                              color: Color(0xFF3f3f46),
                              size: 24,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artists,
                          style: const TextStyle(
                            color: Color(0xFFa1a1aa),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => player.togglePlayPause(),
                    icon: Icon(
                      player.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: const Color(0xFF10b981),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            Container(
              height: 2,
              color: const Color(0xFF1a3a2a),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress.clamp(0.0, 1.0),
                child: Container(color: const Color(0xFF10b981)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
