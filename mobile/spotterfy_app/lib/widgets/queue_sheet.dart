import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

/// The "Up Next" queue sheet.
///
/// Shared by the now-playing page and the mini player so both queue buttons
/// open the *same* page - they used to be two independent copies that had
/// drifted apart.
void showQueueSheet(BuildContext context, PlayerProvider player) {
  final queue = List<TrackModel>.from(player.queue);
  final currentIndex = player.currentIndex;
  showModalBottomSheet(
    context: context,
    // The sheet draws its own surface, so the route stays transparent and the
    // rounded corners + border are ours to control.
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    isScrollControlled: true,
    useSafeArea: true,
    // Explicit timing/curve instead of relying on the defaults, so opening
    // the queue and opening the player page feel like the same surface.
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 250),
      reverseDuration: Duration(milliseconds: 200),
      curve: Curves.decelerate,
      reverseCurve: Curves.decelerate,
    ),
    builder: (sheetCtx) {
      return Container(
        decoration: BoxDecoration(
          color: SpotterfyTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 28,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        // Opens up to the top of the screen. A long queue scrolls inside the
        // sheet instead of growing past the screen - without a cap the Column
        // overflowed, which is what made the sheet look broken while opening.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grabber, matching the drag handle on the player page.
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 6),
              child: Row(
                children: [
                  Text(
                    'Up Next',
                    style: TextStyle(
                      color: SpotterfyTheme.text,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (queue.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${queue.length}',
                        style: TextStyle(
                          color: SpotterfyTheme.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const Spacer(),
                  if (queue.length > 1)
                    TextButton.icon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        player.clearQueue();
                      },
                      icon: const Icon(
                        Icons.playlist_remove_rounded,
                        size: 16,
                        color: SpotterfyTheme.muted,
                      ),
                      label: const Text(
                        'Clear',
                        style: TextStyle(
                          color: SpotterfyTheme.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: SpotterfyTheme.muted,
                      size: 20,
                    ),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(sheetCtx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0x14FFFFFF)),
            if (queue.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Text(
                  'Nothing queued',
                  style: TextStyle(color: SpotterfyTheme.muted),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  itemCount: queue.length,
                  shrinkWrap: true,
                  separatorBuilder: (_, _) => const SizedBox(height: 2),
                  itemBuilder: (_, index) {
                    final track = queue[index];
                    final isCurrent = index == currentIndex;
                    return _QueueRow(
                      track: track,
                      index: index,
                      isCurrent: isCurrent,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        player.playFromQueue(index);
                        Navigator.pop(sheetCtx);
                      },
                      onRemove: isCurrent
                          ? null
                          : () {
                              HapticFeedback.lightImpact();
                              player.removeFromQueue(index);
                            },
                    );
                  },
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// One row in the Up Next sheet: cover, title/artist, length, and a remove
/// action. The current track gets a green tint plus animated equaliser bars.
class _QueueRow extends StatelessWidget {
  final TrackModel track;
  final int index;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _QueueRow({
    required this.track,
    required this.index,
    required this.isCurrent,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isCurrent
          ? SpotterfyTheme.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: track.cover.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: track.cover,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => _thumbPlaceholder(),
                          errorWidget: (_, _, _) => _thumbPlaceholder(),
                        )
                      : _thumbPlaceholder(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: TextStyle(
                        color: isCurrent
                            ? SpotterfyTheme.primary
                            : SpotterfyTheme.text,
                        fontSize: 14,
                        fontWeight: isCurrent
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artists,
                      style: const TextStyle(
                        color: SpotterfyTheme.muted,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (track.durationMs > 0)
                Text(
                  _fmtMs(track.durationMs),
                  style: const TextStyle(
                    color: SpotterfyTheme.mutedDark,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              if (isCurrent)
                const Padding(
                  padding: EdgeInsets.only(left: 10, right: 6),
                  child: Icon(
                    Icons.graphic_eq_rounded,
                    color: SpotterfyTheme.primary,
                    size: 18,
                  ),
                )
              else
                IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 17,
                    color: SpotterfyTheme.mutedDark,
                  ),
                  tooltip: 'Remove from queue',
                  visualDensity: VisualDensity.compact,
                  onPressed: onRemove,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbPlaceholder() {
    return Container(
      color: SpotterfyTheme.card,
      child: const Icon(
        Icons.music_note_rounded,
        color: SpotterfyTheme.muted,
        size: 20,
      ),
    );
  }
}

String _fmtMs(int ms) {
  final total = (ms / 1000).round();
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
