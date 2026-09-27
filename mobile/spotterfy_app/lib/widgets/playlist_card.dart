import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:spotterfy_app/models/playlist_model.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/playlist_play_button.dart';

class PlaylistCard extends StatelessWidget {
  final PlaylistModel playlist;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onPlay;
  final bool showDelete;
  final Widget? trailing;

  /// Marks the card as the source of the currently playing track.
  final bool isPlaying;
  final bool isActive;

  const PlaylistCard({
    super.key,
    required this.playlist,
    this.onTap,
    this.onDelete,
    this.onPlay,
    this.showDelete = false,
    this.trailing,
    this.isPlaying = false,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final active = isActive || isPlaying;
    final hasPlay = onPlay != null && playlist.tracks.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          // Subtle top-to-bottom lift so the row reads as a raised surface
          // instead of a flat block of grey.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: active
                ? [
                    SpotterfyTheme.primary.withValues(alpha: 0.16),
                    SpotterfyTheme.card,
                  ]
                : [SpotterfyTheme.card, SpotterfyTheme.surface],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? SpotterfyTheme.primary.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.06),
            width: active ? 1.2 : 1,
          ),
        ),
        child: Row(
          children: [
            _Cover(url: playlist.coverUrl, radius: 12, active: active),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (active) ...[
                        Icon(
                          Icons.graphic_eq_rounded,
                          color: SpotterfyTheme.primary,
                          size: 15,
                        ),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          playlist.name,
                          style: TextStyle(
                            color: active
                                ? SpotterfyTheme.primary
                                : SpotterfyTheme.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    // `sourceLabel` renders the stored slug as a proper name
                    // (Spotify / YouTube / SoundCloud).
                    playlist.owner.isNotEmpty
                        ? '${playlist.tracks.length} tracks • ${playlist.sourceLabel} • by ${playlist.owner}'
                        : '${playlist.tracks.length} tracks • ${playlist.sourceLabel}',
                    style: TextStyle(
                      color: SpotterfyTheme.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (playlist.tracks.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          color: SpotterfyTheme.mutedDark,
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _totalDuration(playlist),
                          style: TextStyle(
                            color: SpotterfyTheme.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
            if (hasPlay)
              PlaylistPlayButton(
                onPressed: onPlay,
                isPlaying: isPlaying,
                isActive: active,
                tooltip: isPlaying ? 'Pause' : 'Play',
              ),
            if (showDelete)
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: SpotterfyTheme.muted,
                  size: 20,
                ),
                tooltip: 'Delete',
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }

  String _totalDuration(PlaylistModel playlist) {
    final total = playlist.tracks.fold<int>(0, (sum, t) => sum + t.durationMs);
    final hours = total ~/ 3600000;
    final minutes = (total % 3600000) ~/ 60000;
    final seconds = (total % 60000) ~/ 1000;
    if (hours > 0) {
      return '${hours}h ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _Cover extends StatelessWidget {
  final String url;
  final double radius;
  final bool active;

  const _Cover({required this.url, required this.radius, required this.active});

  @override
  Widget build(BuildContext context) {
    const size = 58.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        // Faint green rim picks up the active state on the artwork too.
        border: Border.all(
          color: active
              ? SpotterfyTheme.primary.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1),
        child: url.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: (_, _) => _placeholder(),
                errorWidget: (_, _, _) => _placeholder(),
              )
            : _placeholder(),
      ),
    );
  }
}

Widget _placeholder() {
  return Container(
    width: 58,
    height: 58,
    color: SpotterfyTheme.surface,
    child: const Icon(
      Icons.library_music,
      color: SpotterfyTheme.muted,
      size: 26,
    ),
  );
}
