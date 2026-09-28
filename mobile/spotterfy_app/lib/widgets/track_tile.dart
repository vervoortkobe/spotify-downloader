import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/widgets/storage_cover.dart';

class TrackTile extends StatelessWidget {
  final TrackModel track;
  final VoidCallback? onPlay;
  final VoidCallback? onDownload;

  /// Saves the track to the library (e.g. a song found via search). Shows a
  /// bookmark button when provided.
  final VoidCallback? onSave;
  final bool isSaved;
  final bool isSelected;
  final bool isPlaying;
  final double progress;

  /// Long-press to start a multi-select. Supplied by the playlist screen.
  final VoidCallback? onLongPress;

  /// Multi-select state. In selection mode a tap toggles the row instead of
  /// playing, and a leading checkbox replaces the artwork.
  final bool selectionMode;
  final bool selected;

  /// Shows the round "downloaded" check.
  final bool isDownloaded;

  /// This track is currently being fetched, so the row shows a spinner in place
  /// of its inline actions.
  final bool isDownloading;

  /// Local file path for embedded cover art (storage tracks with empty [track.cover]).
  final String? coverPath;

  const TrackTile({
    super.key,
    required this.track,
    this.onPlay,
    this.onDownload,
    this.onSave,
    this.isSaved = false,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
    this.isDownloaded = false,
    this.isDownloading = false,
    this.isSelected = false,
    this.isPlaying = false,
    this.progress = 0,
    this.coverPath,
  });

  @override
  Widget build(BuildContext context) {
    final bool active = isPlaying;
    return Dismissible(
      key: ValueKey('track-${track.id}'),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.35,
        DismissDirection.endToStart: 0.35,
      },
      // startToEnd = swipe RIGHT (finger moves right) -> Play Now (immediate primary action)
      // endToStart = swipe LEFT (finger moves left) -> Add to Queue (secondary)
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF10b981),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_arrow, color: Colors.white, size: 18),
            SizedBox(width: 6),
            Text(
              'Play Now',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1a3a2a),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Add to Queue',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            SizedBox(width: 6),
            Icon(Icons.queue_music, color: Colors.white, size: 18),
          ],
        ),
      ),
      confirmDismiss: (dir) async {
        HapticFeedback.lightImpact();
        final player = context.read<PlayerProvider>();
        if (dir == DismissDirection.startToEnd) {
          // Swipe RIGHT -> play immediately (natural forward gesture)
          player.play(
            track,
            queue: [track, ...player.queue.where((t) => t.id != track.id)],
          );
        } else {
          // Swipe LEFT -> queue at end, keep current position
          final q = [...player.queue, track];
          final currentIdx = player.currentIndex.clamp(
            0,
            player.queue.isEmpty ? 0 : player.queue.length - 1,
          );
          player.setQueue(q, startIndex: player.queue.isEmpty ? 0 : currentIdx);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Added "${track.title}" to queue'),
                duration: const Duration(milliseconds: 900),
                backgroundColor: const Color(0xFF0f1d17),
              ),
            );
          }
        }
        return false;
      },
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? Color(0xFF10b981).withValues(alpha: 0.18)
              : active
              ? Color(0xFF10b981).withValues(alpha: 0.15)
              : isSelected
              ? Color(0xFF10b981).withValues(alpha: 0.1)
              : Color(0xFF0f1d17),
          borderRadius: BorderRadius.circular(12),
          border: selected || active
              ? Border.all(color: Color(0xFF10b981).withValues(alpha: 0.6))
              : isSelected
              ? Border.all(color: Color(0xFF10b981).withValues(alpha: 0.3))
              : Border.all(color: Color(0xFF1a3a2a).withValues(alpha: 0.3)),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Color(0xFF10b981).withValues(alpha: 0.25),
                    blurRadius: 12,
                  ),
                ]
              : null,
        ),
        child: ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          onTap: onPlay,
          onLongPress: onLongPress,
          // In selection mode the artwork is replaced by a checkbox so the
          // selected state is obvious without reading the highlight colour.
          leading: selectionMode
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected
                        ? const Color(0xFF10b981)
                        : const Color(0xFF4a4a4a),
                    size: 26,
                  ),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: track.cover.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: track.cover,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          // Decode at 2x the 48px box instead of the source's
                          // full resolution (often 640px). Without this every
                          // row in a long list decodes ~180x more pixels than it
                          // displays, which is a large chunk of scroll jank and
                          // image-cache memory.
                          memCacheWidth: 96,
                          maxWidthDiskCache: 240,
                          placeholder: (_, _) => Container(
                            color: Color(0xFF1a1a2e),
                            child: Icon(
                              Icons.music_note,
                              color: Colors.grey[600],
                            ),
                          ),
                          errorWidget: (_, _, _) => Container(
                            color: Color(0xFF1a1a2e),
                            child: Icon(
                              Icons.music_note,
                              color: Colors.grey[600],
                            ),
                          ),
                        )
                      : (coverPath != null
                            ? StorageCover(
                                path: coverPath!,
                                size: 48,
                                iconSize: 24,
                                radius: 6,
                              )
                            : Container(
                                width: 48,
                                height: 48,
                                color: Color(0xFF1a1a2e),
                                child: Icon(
                                  Icons.music_note,
                                  color: Colors.grey[600],
                                ),
                              )),
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
          subtitle: Row(
            children: [
              Flexible(
                child: Text(
                  track.artists,
                  style: TextStyle(color: Color(0xFFa1a1aa), fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Round check marking the track as available offline.
              if (isDownloaded) ...[
                const SizedBox(width: 6),
                const Tooltip(
                  message: 'Downloaded',
                  child: Icon(
                    Icons.check_circle,
                    color: Color(0xFF10b981),
                    size: 14,
                  ),
                ),
              ],
            ],
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
              if (track.durationMs > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    _fmtDuration(Duration(milliseconds: track.durationMs)),
                    style: TextStyle(
                      color: Color(0xFFa1a1aa),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              if (onDownload != null && progress == 0 && !isDownloading)
                IconButton(
                  icon: Icon(
                    isDownloaded ? Icons.download_done : Icons.download,
                    color: isDownloaded
                        ? const Color(0xFF10b981)
                        : Color(0xFFa1a1aa),
                    size: 20,
                  ),
                  tooltip: isDownloaded
                      ? 'Downloaded — tap to remove'
                      : 'Download',
                  onPressed: onDownload,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
              if (isDownloading)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF10b981),
                    ),
                  ),
                ),
              if (onSave != null)
                IconButton(
                  icon: Icon(
                    isSaved
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    color: isSaved
                        ? const Color(0xFF10b981)
                        : const Color(0xFFa1a1aa),
                    size: 20,
                  ),
                  tooltip: isSaved ? 'Saved to library' : 'Save to library',
                  onPressed: onSave,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
              // Queue button
              IconButton(
                icon: Icon(
                  Icons.queue_music,
                  color: isSelected ? Color(0xFF10b981) : Color(0xFFa1a1aa),
                  size: 20,
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  final player = context.read<PlayerProvider>();
                  final newQueue = [...player.queue, track];
                  player.setQueue(newQueue, startIndex: player.currentIndex);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Added "${track.title}" to queue'),
                      duration: Duration(milliseconds: 900),
                      backgroundColor: Color(0xFF0f1d17),
                    ),
                  );
                },
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
              ),
              if (onPlay != null)
                IconButton(
                  icon: Icon(
                    active
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    color: active
                        ? Color(0xFF10b981)
                        : isSelected
                        ? Color(0xFF10b981)
                        : Color(0xFFa1a1aa),
                    size: 28,
                  ),
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

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
