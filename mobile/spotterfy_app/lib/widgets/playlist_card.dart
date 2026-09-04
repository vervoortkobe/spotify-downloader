import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:spotterfy_app/models/playlist_model.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

class PlaylistCard extends StatelessWidget {
  final PlaylistModel playlist;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onPlay;
  final bool showDelete;
  final Widget? trailing;

  const PlaylistCard({
    super.key,
    required this.playlist,
    this.onTap,
    this.onDelete,
    this.onPlay,
    this.showDelete = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SpotterfyTheme.card,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: playlist.coverUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: playlist.coverUrl,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => _placeholder(),
                      errorWidget: (_, _, _) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    style: TextStyle(
                      color: SpotterfyTheme.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Text(
                    '${playlist.tracks.length} tracks • ${playlist.source}',
                    style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // ignore: use_null_aware_elements
            if (trailing != null) trailing!,
            if (onPlay != null)
              Container(
                decoration: BoxDecoration(color: SpotterfyTheme.primary, shape: BoxShape.circle, boxShadow: [BoxShadow(color: SpotterfyTheme.primary.withValues(alpha: 0.4), blurRadius: 10)]),
                child: IconButton(
                  icon: Icon(Icons.play_arrow, color: Colors.black, size: 20),
                  onPressed: onPlay,
                  padding: EdgeInsets.all(6),
                  constraints: BoxConstraints(),
                ),
              ),
            if (showDelete)
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: SpotterfyTheme.muted,
                  size: 20,
                ),
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: 56,
      height: 56,
      color: SpotterfyTheme.surface,
      child: Icon(Icons.library_music, color: SpotterfyTheme.muted, size: 28),
    );
  }
}
