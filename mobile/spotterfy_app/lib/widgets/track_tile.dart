import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/providers/player_provider.dart';

class TrackTile extends StatelessWidget {
  final TrackModel track;
  final VoidCallback? onPlay;
  final VoidCallback? onDownload;
  final bool isSelected;
  final bool isPlaying;
  final double progress;

  const TrackTile({
    super.key,
    required this.track,
    this.onPlay,
    this.onDownload,
    this.isSelected = false,
    this.isPlaying = false,
    this.progress = 0,
  });

  @override
  Widget build(BuildContext context) {
    final bool active = isPlaying;
    return Dismissible(
      key: ValueKey('track-${track.id}'),
      direction: DismissDirection.horizontal,
      background: Container(
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(color: Color(0xFF10b981), borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.only(left: 24),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.queue_music, color: Colors.white, size: 18), SizedBox(width: 6), Text('Queue', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))]),
      ),
      secondaryBackground: Container(
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(color: Color(0xFF0f766e), borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 24),
        child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end, children: [Text('Play', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)), SizedBox(width: 6), Icon(Icons.play_arrow, color: Colors.white, size: 18)]),
      ),
      confirmDismiss: (dir) async {
        HapticFeedback.lightImpact();
        final player = context.read<PlayerProvider>();
        if (dir == DismissDirection.startToEnd) {
          final q = [...player.queue, track];
          player.setQueue(q, startIndex: player.queue.indexOf(player.currentTrack ?? track));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added "${track.title}" to queue'), duration: Duration(milliseconds: 900), backgroundColor: Color(0xFF0f1d17)));
        } else {
          player.play(track, queue: [track, ...player.queue.where((t) => t.id != track.id)]);
        }
        return false;
      },
      child: Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? Color(0xFF10b981).withValues(alpha: 0.15)
            : isSelected
                ? Color(0xFF10b981).withValues(alpha: 0.1)
                : Color(0xFF0f1d17),
        borderRadius: BorderRadius.circular(12),
        border: active
            ? Border.all(color: Color(0xFF10b981).withValues(alpha: 0.5))
            : isSelected
                ? Border.all(color: Color(0xFF10b981).withValues(alpha: 0.3))
                : Border.all(color: Color(0xFF1a3a2a).withValues(alpha: 0.3)),
        boxShadow: active ? [BoxShadow(color: Color(0xFF10b981).withValues(alpha: 0.25), blurRadius: 12)] : null,
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: track.cover.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: track.cover,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    color: Color(0xFF1a1a2e),
                    child: Icon(Icons.music_note, color: Colors.grey[600]),
                  ),
                  errorWidget: (_, _, _) => Container(
                    color: Color(0xFF1a1a2e),
                    child: Icon(Icons.music_note, color: Colors.grey[600]),
                  ),
                )
              : Container(
                  width: 48,
                  height: 48,
                  color: Color(0xFF1a1a2e),
                  child: Icon(Icons.music_note, color: Colors.grey[600]),
                ),
        ),
        title: Text(
          track.title,
          style: TextStyle(
            color: active ? Color(0xFF6ee7b7) : Colors.white,
            fontSize: 14,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          track.artists,
          style: TextStyle(color: Color(0xFFa1a1aa), fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (progress > 0 && progress < 100)
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  value: progress / 100,
                  strokeWidth: 2,
                  color: Color(0xFF10b981),
                ),
              ),
            if (progress >= 100) Icon(Icons.check_circle, color: Color(0xFF10b981), size: 20),
            if (onDownload != null && progress == 0)
              IconButton(icon: Icon(Icons.download, color: Color(0xFFa1a1aa), size: 20), onPressed: onDownload, padding: EdgeInsets.zero, constraints: BoxConstraints()),
            if (onPlay != null)
              IconButton(
                icon: Icon(active ? Icons.pause_circle_filled : Icons.play_circle_filled, color: active ? Color(0xFF10b981) : isSelected ? Color(0xFF10b981) : Color(0xFFa1a1aa), size: 28),
                onPressed: onPlay,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
              ),
          ],
        ),
      ),
      ),
    );
  }
}
