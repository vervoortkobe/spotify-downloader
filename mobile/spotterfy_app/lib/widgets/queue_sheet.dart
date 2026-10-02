import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';

/// Opens the "Up Next" queue sheet.
///
/// Shared by the now-playing page and the mini player so both queue buttons
/// open the *same* page - they used to be two independent copies that had
/// drifted apart.
void showQueueSheet(BuildContext context, PlayerProvider player) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    // The sheet draws its own surface, so the route stays transparent and the
    // rounded corners + border are ours to control.
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    isScrollControlled: true,
    useSafeArea: true,
    // Explicit timing/curve instead of relying on the defaults, so opening the
    // queue and opening the player page feel like the same surface.
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 250),
      reverseDuration: Duration(milliseconds: 200),
      curve: Curves.decelerate,
      reverseCurve: Curves.decelerate,
    ),
    builder: (_) => const QueueSheet(),
  );
}

/// Queue sheet: swipe a row away to remove it, long-press to multi-select, and
/// reorder the selection with the up/down actions.
///
/// Reads the queue from the provider rather than a snapshot taken when the sheet
/// opened, so a track skipped or removed from elsewhere is reflected live.
class QueueSheet extends StatefulWidget {
  const QueueSheet({super.key});

  @override
  State<QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<QueueSheet> {
  /// Selected row indices, held as indices into the queue.
  final Set<int> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.remove(index)) _selected.add(index);
    });
  }

  void _clearSelection() => setState(_selected.clear);

  void _selectAll(int count) => setState(() {
    _selected
      ..clear()
      ..addAll(List.generate(count, (i) => i));
  });

  void _afterChange(String? message) {
    if (!mounted) return;
    setState(_selected.clear);
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: SpotterfyTheme.surface,
        ),
      );
    }
  }

  String _fmtDuration(int ms) {
    final total = (ms / 1000).round();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '$h hr ${m.toString().padLeft(2, '0')} min';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final queue = player.queue;
    final currentIndex = player.currentIndex;
    final totalMs = queue.fold<int>(0, (sum, t) => sum + t.durationMs);

    return Container(
      decoration: BoxDecoration(
        color: SpotterfyTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: SpotterfyTheme.overlay(0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 28,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      // Opens up to the top of the screen; the list scrolls inside it.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          // Grabber.
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: SpotterfyTheme.overlay(0.18),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (_selecting)
            _selectionBar(player)
          else
            _normalBar(player, totalMs),
          const Divider(height: 1, color: Color(0x14FFFFFF)),
          if (queue.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  'Nothing queued',
                  style: TextStyle(color: SpotterfyTheme.muted),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                itemCount: queue.length,
                itemBuilder: (_, index) {
                  final track = queue[index];
                  final isCurrent = index == currentIndex;
                  return _SwipeToRemove(
                    key: ValueKey('queue-${track.id}-$index'),
                    enabled: !_selecting,
                    onRemove: () {
                      HapticFeedback.lightImpact();
                      player.removeFromQueue(index);
                      _afterChange('Removed "${track.title}"');
                    },
                    child: _QueueRow(
                      track: track,
                      index: index,
                      isCurrent: isCurrent,
                      isPlaying: isCurrent && player.isPlaying,
                      selectionMode: _selecting,
                      selected: _selected.contains(index),
                      canMoveUp: _selected.isEmpty || index > 0,
                      canMoveDown:
                          _selected.isEmpty || index < queue.length - 1,
                      onTap: () {
                        if (_selecting) {
                          _toggle(index);
                          return;
                        }
                        player.playFromQueue(index);
                        Navigator.pop(context);
                      },
                      onLongPress: () => _toggle(index),
                      onRemove: _selecting
                          ? null
                          : () {
                              player.removeFromQueue(index);
                              _afterChange('Removed "${track.title}"');
                            },
                      onMoveUp: _selecting
                          ? null
                          : () => player.moveQueueUp(index),
                      onMoveDown: _selecting
                          ? null
                          : () => player.moveQueueDown(index),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  /// Header when nothing is selected: counts and total length.
  Widget _normalBar(PlayerProvider player, int totalMs) {
    final count = player.queue.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
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
              SizedBox(height: 2),
              Text(
                count == 0
                    ? 'Empty'
                    : '$count ${count == 1 ? 'song' : 'songs'} • ${_fmtDuration(totalMs)}',
                style: TextStyle(color: SpotterfyTheme.muted, fontSize: 12),
              ),
            ],
          ),
          Spacer(),
          if (count > 0)
            TextButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                player.clearQueue();
                _afterChange('Queue cleared');
              },
              icon: Icon(
                Icons.playlist_remove_rounded,
                size: 16,
                color: SpotterfyTheme.muted,
              ),
              label: Text(
                'Clear',
                style: TextStyle(
                  color: SpotterfyTheme.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          IconButton(
            icon: Icon(
              Icons.close_rounded,
              color: SpotterfyTheme.muted,
              size: 20,
            ),
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  /// Header in multi-select mode: count plus the bulk actions.
  Widget _selectionBar(PlayerProvider player) {
    final indices = _selected.toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.close, color: SpotterfyTheme.text),
            tooltip: 'Clear selection',
            onPressed: _clearSelection,
          ),
          Text(
            '${_selected.length} selected',
            style: TextStyle(
              color: SpotterfyTheme.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.done_all, color: SpotterfyTheme.text, size: 20),
            tooltip: 'Select all',
            onPressed: () => _selectAll(player.queue.length),
          ),
          IconButton(
            icon: Icon(
              Icons.arrow_upward,
              color: SpotterfyTheme.text,
              size: 20,
            ),
            tooltip: 'Move up',
            onPressed: () {
              player.moveQueueBlockUp(indices);
              // Keep the same tracks selected after they shift up a place.
              setState(() {
                _selected
                  ..clear()
                  ..addAll(indices.map((i) => i - 1).where((i) => i >= 0));
              });
            },
          ),
          IconButton(
            icon: Icon(
              Icons.arrow_downward,
              color: SpotterfyTheme.text,
              size: 20,
            ),
            tooltip: 'Move down',
            onPressed: () {
              final last = player.queue.length - 1;
              player.moveQueueBlockDown(indices);
              setState(() {
                _selected
                  ..clear()
                  ..addAll(indices.map((i) => i + 1).where((i) => i <= last));
              });
            },
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: SpotterfyTheme.text,
              size: 20,
            ),
            tooltip: 'Remove selected',
            onPressed: () {
              HapticFeedback.lightImpact();
              player.removeFromQueueMany(indices);
              _afterChange(
                'Removed ${indices.length} ${indices.length == 1 ? 'song' : 'songs'}',
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Reveals a red "Remove" affordance when swiped.
///
/// Suppressed while multi-selecting, where a stray horizontal swipe would
/// otherwise delete rows the user was trying to select.
class _SwipeToRemove extends StatelessWidget {
  final Widget child;
  final VoidCallback onRemove;
  final bool enabled;

  const _SwipeToRemove({
    super.key,
    required this.child,
    required this.onRemove,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Dismissible(
      key: key ?? const ValueKey('queue-row'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Remove',
              style: TextStyle(
                color: SpotterfyTheme.text,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            SizedBox(width: 6),
            Icon(Icons.delete_outline, color: SpotterfyTheme.text, size: 18),
          ],
        ),
      ),
      onDismissed: (_) => onRemove(),
      child: child,
    );
  }
}

class _QueueRow extends StatelessWidget {
  final TrackModel track;
  final int index;
  final bool isCurrent;
  final bool isPlaying;
  final bool selectionMode;
  final bool selected;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _QueueRow({
    required this.track,
    required this.index,
    required this.isCurrent,
    required this.isPlaying,
    required this.selectionMode,
    required this.selected,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onTap,
    required this.onLongPress,
    this.onRemove,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? SpotterfyTheme.primary.withValues(alpha: 0.16)
          : isCurrent
          ? SpotterfyTheme.overlay(0.04)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Row(
            children: [
              // In selection mode a checkbox replaces the artwork, so the
              // selected state reads without relying on the highlight colour.
              if (selectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected
                        ? SpotterfyTheme.primary
                        : const Color(0xFF4a4a4a),
                    size: 24,
                  ),
                )
              else
                SizedBox(
                  width: 22,
                  child: isCurrent
                      ? Icon(
                          isPlaying
                              ? Icons.graphic_eq_rounded
                              : Icons.pause_rounded,
                          color: SpotterfyTheme.primary,
                          size: 18,
                        )
                      : Text(
                          '${index + 1}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: SpotterfyTheme.mutedDark,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: track.cover.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: track.cover,
                          fit: BoxFit.cover,
                          // Decode at 2x the 44px box, not the source size.
                          memCacheWidth: 88,
                          maxWidthDiskCache: 240,
                          placeholder: (_, _) => _thumb(),
                          errorWidget: (_, _, _) => _thumb(),
                        )
                      : _thumb(),
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
                      style: TextStyle(
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
                  _fmt(track.durationMs),
                  style: TextStyle(
                    color: SpotterfyTheme.mutedDark,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              if (!selectionMode)
                _RowMenu(
                  onRemove: onRemove,
                  onMoveUp: canMoveUp ? onMoveUp : null,
                  onMoveDown: canMoveDown ? onMoveDown : null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumb() => Container(
    color: SpotterfyTheme.card,
    child: Icon(
      Icons.music_note_rounded,
      color: SpotterfyTheme.muted,
      size: 20,
    ),
  );

  static String _fmt(int ms) {
    final total = (ms / 1000).round();
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// Per-row overflow menu: move up / move down / remove.
class _RowMenu extends StatelessWidget {
  final VoidCallback? onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _RowMenu({this.onRemove, this.onMoveUp, this.onMoveDown});

  @override
  Widget build(BuildContext context) {
    if (onRemove == null) return const SizedBox.shrink();
    return SizedBox(
      width: 34,
      height: 34,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        icon: Icon(Icons.more_vert, size: 18, color: SpotterfyTheme.muted),
        color: SpotterfyTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (v) {
          HapticFeedback.selectionClick();
          switch (v) {
            case 'up':
              onMoveUp?.call();
            case 'down':
              onMoveDown?.call();
            case 'remove':
              onRemove?.call();
          }
        },
        itemBuilder: (_) => [
          if (onMoveUp != null)
            PopupMenuItem(
              value: 'up',
              height: 40,
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_upward,
                    size: 16,
                    color: SpotterfyTheme.muted,
                  ),
                  SizedBox(width: 10),
                  Text('Move up', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
          if (onMoveDown != null)
            PopupMenuItem(
              value: 'down',
              height: 40,
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_downward,
                    size: 16,
                    color: SpotterfyTheme.muted,
                  ),
                  SizedBox(width: 10),
                  Text('Move down', style: TextStyle(fontSize: 13)),
                ],
              ),
            ),
          const PopupMenuItem(
            value: 'remove',
            height: 40,
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                SizedBox(width: 10),
                Text(
                  'Remove',
                  style: TextStyle(fontSize: 13, color: Colors.redAccent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
