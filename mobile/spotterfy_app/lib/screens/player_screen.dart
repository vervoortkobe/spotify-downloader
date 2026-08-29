import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/player_provider.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final track = player.currentTrack;

    if (track == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF07110b),
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(
          child: Text(
            'No track selected',
            style: TextStyle(color: Color(0xFFa1a1aa)),
          ),
        ),
      );
    }

    final pos = player.position;
    final dur = player.duration;
    final sliderVal = dur.inMilliseconds > 0
        ? pos.inMilliseconds / dur.inMilliseconds
        : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF07110b),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const Spacer(flex: 1),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 280,
                height: 280,
                color: const Color(0xFF0f1d17),
                child: track.cover.isNotEmpty
                    ? Image.network(
                        track.cover,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.music_note,
                          color: Color(0xFF3f3f46),
                          size: 64,
                        ),
                      )
                    : const Icon(
                        Icons.music_note,
                        color: Color(0xFF3f3f46),
                        size: 64,
                      ),
              ),
            ),
            const Spacer(flex: 1),
            Text(
              track.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              track.artists,
              style: const TextStyle(color: Color(0xFFa1a1aa), fontSize: 16),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 32),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                activeTrackColor: const Color(0xFF10b981),
                inactiveTrackColor: const Color(0xFF1a3a2a),
                thumbColor: const Color(0xFF10b981),
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
                    style: const TextStyle(
                      color: Color(0xFFa1a1aa),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    _fmtDuration(dur),
                    style: const TextStyle(
                      color: Color(0xFFa1a1aa),
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
                  icon: const Icon(
                    Icons.skip_previous,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(width: 24),
                GestureDetector(
                  onTap: () => player.togglePlayPause(),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10b981),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      player.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                IconButton(
                  onPressed: () => player.next(),
                  icon: const Icon(
                    Icons.skip_next,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ],
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
