import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:spotifull_app/models/playlist_model.dart';

class PlaylistCard extends StatelessWidget {
  final PlaylistModel playlist;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final bool showDelete;
  final Widget? trailing;

  const PlaylistCard({
    super.key,
    required this.playlist,
    this.onTap,
    this.onDelete,
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
          color: Color(0xFF0f1d17),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Color(0xFF1a3a2a)),
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
                      placeholder: (_, __) => _placeholder(),
                      errorWidget: (_, __, ___) => _placeholder(),
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
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Text(
                    '${playlist.tracks.length} tracks • ${playlist.source}${playlist.isCustom ? ' • Custom' : ''}',
                    style: TextStyle(
                      color: Color(0xFFa1a1aa),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
            if (showDelete)
              IconButton(
                icon: Icon(Icons.delete_outline, color: Color(0xFFef4444), size: 20),
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
      color: Color(0xFF1a1a2e),
      child: Icon(Icons.library_music, color: Colors.grey[600], size: 28),
    );
  }
}
