import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:spotifull_app/models/track_model.dart';

class TrackTile extends StatelessWidget {
  final TrackModel track;
  final VoidCallback? onPlay;
  final VoidCallback? onDownload;
  final bool isSelected;
  final double progress;

  const TrackTile({
    super.key,
    required this.track,
    this.onPlay,
    this.onDownload,
    this.isSelected = false,
    this.progress = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? Color(0xFF10b981).withValues(alpha: 0.1)
            : Color(0xFF0f1d17),
        borderRadius: BorderRadius.circular(12),
        border: isSelected
            ? Border.all(color: Color(0xFF10b981).withValues(alpha: 0.3))
            : null,
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
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
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
            if (progress >= 100)
              Icon(Icons.check_circle, color: Color(0xFF10b981), size: 20),
            if (onDownload != null && progress == 0)
              IconButton(
                icon: Icon(Icons.download, color: Color(0xFFa1a1aa), size: 20),
                onPressed: onDownload,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
              ),
            if (onPlay != null)
              IconButton(
                icon: Icon(
                  isSelected
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  color: isSelected ? Color(0xFF10b981) : Color(0xFFa1a1aa),
                  size: 28,
                ),
                onPressed: onPlay,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
              ),
          ],
        ),
      ),
    );
  }
}
