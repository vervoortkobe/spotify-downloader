import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:spotterfy_app/models/playlist_model.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

/// Compact playlist row used on profiles and the "all playlists" page.
///
/// A rounded card with real artwork rather than a bare ListTile: the rows sit
/// directly on the page background, so grouping them gives the section an edge
/// and makes the artwork read as the thing you are picking.
class ProfilePlaylistTile extends StatelessWidget {
  final PlaylistModel playlist;
  final VoidCallback onTap;

  const ProfilePlaylistTile({
    super.key,
    required this.playlist,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: SpotterfyTheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: playlist.coverUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: playlist.coverUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, _) =>
                                Container(color: SpotterfyTheme.card),
                            errorWidget: (_, _, _) => Container(
                              color: SpotterfyTheme.card,
                              child: Icon(
                                Icons.music_note,
                                color: SpotterfyTheme.muted,
                                size: 22,
                              ),
                            ),
                          )
                        : Container(
                            color: SpotterfyTheme.card,
                            child: Icon(
                              Icons.music_note,
                              color: SpotterfyTheme.muted,
                              size: 22,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: SpotterfyTheme.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${playlist.tracks.length} tracks  •  ${playlist.sourceLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: SpotterfyTheme.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: SpotterfyTheme.mutedDark),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
