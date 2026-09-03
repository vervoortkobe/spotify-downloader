import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/screens/player_screen.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

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
        decoration: BoxDecoration(color: const Color(0xFF1a3a2a), borderRadius: BorderRadius.circular(16)),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 28),
        child: const Icon(Icons.skip_previous, color: Colors.white, size: 20),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(color: const Color(0xFF1a3a2a), borderRadius: BorderRadius.circular(16)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 28),
        child: const Icon(Icons.skip_next, color: Colors.white, size: 20),
      ),
      child: GestureDetector(
        onTap: () => Navigator.push(context, swipeRoute(const PlayerScreen())),
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) < -500) {
            HapticFeedback.mediumImpact();
            Navigator.push(context, swipeRoute(const PlayerScreen()));
          }
        },
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0f1d17), Color(0xFF0a1410)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1a3a2a)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 8)), BoxShadow(color: const Color(0xFF10b981).withValues(alpha: 0.15), blurRadius: 20)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // drag handle
              Container(
                margin: const EdgeInsets.only(top: 6),
                width: 28,
                height: 3,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2)),
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
                          color: const Color(0xFF1a3a2a),
                          child: track.cover.isNotEmpty
                              ? Image.network(track.cover, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.music_note, color: Color(0xFF3f3f46), size: 24))
                              : const Icon(Icons.music_note, color: Color(0xFF3f3f46), size: 24),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(track.title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(track.artists, style: const TextStyle(color: Color(0xFFa1a1aa), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (queuePos.isNotEmpty) Text(queuePos, style: const TextStyle(color: Color(0xFF10b981), fontSize: 10, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    IconButton(onPressed: () => player.previous(), icon: const Icon(Icons.skip_previous, color: Color(0xFFa1a1aa), size: 22), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                    const SizedBox(width: 2),
                    GestureDetector(
                      onLongPress: () => HapticFeedback.lightImpact(),
                      child: Container(
                        decoration: BoxDecoration(color: const Color(0xFF10b981), shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFF10b981).withValues(alpha: 0.4), blurRadius: 8)]),
                        child: IconButton(onPressed: () => player.togglePlayPause(), icon: Icon(player.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 22), padding: const EdgeInsets.all(6), constraints: const BoxConstraints()),
                      ),
                    ),
                    const SizedBox(width: 2),
                    IconButton(onPressed: () => player.next(), icon: const Icon(Icons.skip_next, color: Color(0xFFa1a1aa), size: 22), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
              ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                child: SizedBox(
                  height: 3,
                  child: Stack(children: [
                    Container(color: const Color(0xFF1a3a2a)),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress.clamp(0.0, 1.0),
                      child: Container(decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF10b981), Color(0xFF34d399)]), boxShadow: [BoxShadow(color: const Color(0xFF10b981).withValues(alpha: 0.6), blurRadius: 6)])),
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
}
