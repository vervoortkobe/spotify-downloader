import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/widgets/playlist_play_button.dart';
import 'package:spotterfy_app/widgets/storage_cover.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

ButtonStyle _trackActionStyle({
  bool active = false,
  double size = 34,
  bool circle = false,
}) => IconButton.styleFrom(
  backgroundColor: active
      ? SpotterfyTheme.primary.withValues(alpha: 0.13)
      : SpotterfyTheme.overlay(0.06),
  padding: EdgeInsets.zero,
  minimumSize: Size(size, size),
  maximumSize: Size(size, size),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  visualDensity: VisualDensity.compact,
  shape: circle
      ? CircleBorder(side: BorderSide(color: SpotterfyTheme.overlay(0.1)))
      : RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(size / 3),
          side: BorderSide(color: SpotterfyTheme.overlay(0.1)),
        ),
);

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
  final bool emphasizeActions;

  /// Renders the play control as the round [PlaylistPlayButton] chip instead of
  /// a bare play icon. Used by the downloads page so it matches the rest of the
  /// app's transport controls.
  final bool roundPlayButton;

  /// Extra metadata appended to the subtitle after the artists, e.g. a file
  /// size on the downloads page. Rendered as "Artist  •  3.4 MB".
  final String? subtitleMeta;

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
    this.emphasizeActions = false,
    this.roundPlayButton = false,
    this.subtitleMeta,
  });

  @override
  Widget build(BuildContext context) {
    final bool active = isPlaying;
    final actionSize = emphasizeActions ? 38.0 : 34.0;
    final actionGap = emphasizeActions ? 7.0 : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: _TrackSwipeShell(
        dismissKey: ValueKey('track-${track.id}'),
        // startToEnd = swipe RIGHT (finger moves right) -> Play Now (immediate
        // primary action)
        // endToStart = swipe LEFT (finger moves left) -> Add to Queue (secondary)
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
            player.setQueue(
              q,
              startIndex: player.queue.isEmpty ? 0 : currentIdx,
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Added "${track.title}" to queue'),
                  duration: const Duration(milliseconds: 900),
                  backgroundColor: SpotterfyTheme.surface,
                ),
              );
            }
          }
          return false;
        },
        child: Container(
          decoration: BoxDecoration(
            color: selected
                ? SpotterfyTheme.primary.withValues(alpha: 0.18)
                : active
                ? SpotterfyTheme.primary.withValues(alpha: 0.15)
                : isSelected
                ? SpotterfyTheme.primary.withValues(alpha: 0.1)
                : SpotterfyTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: selected || active
                ? Border.all(
                    color: SpotterfyTheme.primary.withValues(alpha: 0.6),
                  )
                : isSelected
                ? Border.all(
                    color: SpotterfyTheme.primary.withValues(alpha: 0.3),
                  )
                : Border.all(
                    color: SpotterfyTheme.borderColor.withValues(alpha: 0.3),
                  ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: SpotterfyTheme.primary.withValues(alpha: 0.25),
                      blurRadius: 12,
                    ),
                  ]
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
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
                            ? SpotterfyTheme.primary
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
                  color: active ? Color(0xFF6ee7b7) : SpotterfyTheme.text,
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                _subtitle,
                style: TextStyle(color: SpotterfyTheme.mutedDark, fontSize: 12),
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
                        color: SpotterfyTheme.primary,
                      ),
                    ),
                  if (progress >= 100)
                    Icon(
                      Icons.check_circle,
                      color: SpotterfyTheme.primary,
                      size: 20,
                    ),
                  if (track.durationMs > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        _fmtDuration(Duration(milliseconds: track.durationMs)),
                        style: TextStyle(
                          color: SpotterfyTheme.mutedDark,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  if (onDownload != null &&
                      progress == 0 &&
                      !isDownloading) ...[
                    if (emphasizeActions) SizedBox(width: actionGap),
                    IconButton(
                      icon: Icon(
                        isDownloaded
                            ? Icons.check_rounded
                            : Icons.download_rounded,
                        color: isDownloaded
                            ? SpotterfyTheme.primary
                            : SpotterfyTheme.mutedDark,
                        size: emphasizeActions ? 23 : 20,
                      ),
                      tooltip: isDownloaded
                          ? 'Downloaded — tap to remove'
                          : 'Download',
                      onPressed: onDownload,
                      style: _trackActionStyle(
                        active: isDownloaded,
                        size: actionSize,
                        circle: true,
                      ),
                    ),
                  ],
                  if (isDownloading)
                    Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: SpotterfyTheme.primary,
                        ),
                      ),
                    ),
                  if (onSave != null) ...[
                    if (emphasizeActions) SizedBox(width: actionGap),
                    IconButton(
                      icon: Icon(
                        isSaved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        color: isSaved
                            ? SpotterfyTheme.primary
                            : SpotterfyTheme.mutedDark,
                        size: emphasizeActions ? 23 : 20,
                      ),
                      tooltip: isSaved ? 'Saved to library' : 'Save to library',
                      onPressed: onSave,
                      style: _trackActionStyle(
                        active: isSaved,
                        size: actionSize,
                      ),
                    ),
                  ],
                  // Queue button. Playlist rows drop it: their only inline
                  // control is the download/checkmark button (queueing is a swipe
                  // away, and tapping the row plays).
                  if (!emphasizeActions)
                    IconButton(
                      icon: Icon(
                        Icons.queue_music_rounded,
                        color: isSelected
                            ? SpotterfyTheme.primary
                            : SpotterfyTheme.mutedDark,
                        size: emphasizeActions ? 23 : 20,
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        final player = context.read<PlayerProvider>();
                        final newQueue = [...player.queue, track];
                        player.setQueue(
                          newQueue,
                          startIndex: player.currentIndex,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Added "${track.title}" to queue'),
                            duration: Duration(milliseconds: 900),
                            backgroundColor: SpotterfyTheme.surface,
                          ),
                        );
                      },
                      style: _trackActionStyle(
                        active: isSelected,
                        size: actionSize,
                      ),
                    ),
                  if (!emphasizeActions && onPlay != null)
                    roundPlayButton
                        ? PlaylistPlayButton(
                            onPressed: onPlay,
                            size: 34,
                            isPlaying: isPlaying,
                            isActive: isSelected && !isPlaying,
                            tooltip: isPlaying ? 'Pause' : 'Play',
                          )
                        : IconButton(
                            icon: Icon(
                              active
                                  ? Icons.pause_circle_filled
                                  : Icons.play_circle_filled,
                              color: active
                                  ? SpotterfyTheme.primary
                                  : isSelected
                                  ? SpotterfyTheme.primary
                                  : SpotterfyTheme.mutedDark,
                              size: 28,
                            ),
                            onPressed: onPlay,
                            style: IconButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(36, 36),
                              maximumSize: const Size(36, 36),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _subtitle {
    final artists = track.artists.trim();
    final meta = subtitleMeta?.trim() ?? '';
    if (meta.isEmpty) return artists;
    if (artists.isEmpty) return meta;
    return '$artists  •  $meta';
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

/// Wraps a track row in a [Dismissible] but draws the swipe reveal itself.
///
/// [Dismissible]'s own `background` is clipped to the rectangle the row has
/// uncovered, so the row's rounded corners expose the list behind them and the
/// reveal ends up partly hidden behind the card's border. Drawing the reveal
/// underneath the card, clipped to the same radius, keeps the cutout clean -
/// the same trick the mini player uses.
class _TrackSwipeShell extends StatefulWidget {
  final Key dismissKey;
  final Future<bool?> Function(DismissDirection) confirmDismiss;
  final Widget child;

  const _TrackSwipeShell({
    required this.dismissKey,
    required this.confirmDismiss,
    required this.child,
  });

  @override
  State<_TrackSwipeShell> createState() => _TrackSwipeShellState();
}

class _TrackSwipeShellState extends State<_TrackSwipeShell> {
  DismissDirection _dir = DismissDirection.startToEnd;
  // The reveal is only shown while the card is displaced. At rest it stays
  // hidden so the row's anti-aliased corners can't leak a hairline.
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final toRight = _dir == DismissDirection.startToEnd;
    return Stack(
      // Let the row's "now playing" glow spill past the shell instead of being
      // cut off at its bounds.
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: _active ? 1 : 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _TrackSwipeReveal(toRight: toRight),
            ),
          ),
        ),
        Dismissible(
          key: widget.dismissKey,
          direction: DismissDirection.horizontal,
          dismissThresholds: const {
            DismissDirection.startToEnd: 0.35,
            DismissDirection.endToStart: 0.35,
          },
          confirmDismiss: widget.confirmDismiss,
          onUpdate: (details) {
            final dir = details.direction;
            final active = details.progress > 0;
            final dirChanged =
                dir != _dir &&
                (dir == DismissDirection.startToEnd ||
                    dir == DismissDirection.endToStart);
            if (dirChanged || active != _active) {
              setState(() {
                if (dirChanged) _dir = dir;
                _active = active;
              });
            }
          },
          child: widget.child,
        ),
      ],
    );
  }
}

/// Revealed underneath a track row while it is being swiped.
///
/// Mirrors the mini player's reveal: a flat dark plate with a green glyph and
/// label, left-aligned for "Play Now" and right-aligned for "Add to Queue".
class _TrackSwipeReveal extends StatelessWidget {
  /// Swipe right (finger moves right) reveals Play Now; left reveals Add to
  /// Queue.
  final bool toRight;

  const _TrackSwipeReveal({required this.toRight});

  @override
  Widget build(BuildContext context) {
    // Play Now gets a green-tinted plate and Add to Queue a neutral one, both
    // blended against [surface] so they stay clearly visible against the page
    // instead of dissolving into the dark background (the mini player's flat
    // #151515 plate reads as an empty hole here).
    final background = toRight
        ? Color.alphaBlend(
            SpotterfyTheme.primary.withValues(alpha: 0.30),
            SpotterfyTheme.surface,
          )
        : Color.alphaBlend(
            SpotterfyTheme.overlay(0.06),
            SpotterfyTheme.surface,
          );
    final border = toRight
        ? SpotterfyTheme.primary.withValues(alpha: 0.5)
        : SpotterfyTheme.overlay(0.16);
    final foreground = SpotterfyTheme.text;
    final label = Text(
      toRight ? 'Play Now' : 'Add to Queue',
      style: TextStyle(
        color: foreground,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    );
    return Container(
      alignment: toRight ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!toRight) ...[label, const SizedBox(width: 8)],
          Icon(
            toRight ? Icons.play_arrow_rounded : Icons.queue_music_rounded,
            color: foreground,
            size: 24,
          ),
          if (toRight) ...[const SizedBox(width: 8), label],
        ],
      ),
    );
  }
}
