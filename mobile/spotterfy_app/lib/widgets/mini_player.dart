import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/widgets/queue_sheet.dart';
import 'package:spotterfy_app/widgets/storage_cover.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/screens/player_screen.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/main.dart';
import 'package:spotterfy_app/utils/duration_format.dart';
import 'package:spotterfy_app/widgets/playlist_play_button.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, this.showQueueButton = true});

  final bool showQueueButton;

  /// Cover edge, and the row height it forces.
  ///
  /// 56 rather than 48: the artwork was the one element of the footer that
  /// never got a chance to be recognised at a glance, and it costs 8px of
  /// footer height to make the currently-playing track identifiable at a glance
  /// from the lock screen.
  static const double _coverSize = 56;

  /// Height the footer occupies above the bottom of the tab body: the card's
  /// own padding, its 56px cover row and the 6px gap beneath it.
  ///
  /// Pages whose content scrolls under the footer add this to their bottom
  /// padding, and floating buttons are lifted by it so the player never covers
  /// them.
  static const double footerHeight = 88;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final track = player.currentTrack;
    if (track == null) return const _EmptyMiniPlayer();

    // Progress and elapsed time live in [_MiniProgressRow], which listens to the
    // position notifier on its own. Reading them here rebuilt the whole mini
    // player - cover, title, two buttons - several times a second.
    // Prefer the player's live duration, but fall back to the length stored on
    // the track. Live radio reports no duration, and a track can be rendered
    // before just_audio has reported one - without this the mini player showed
    // 0:00.
    final durMs = player.duration.inMilliseconds > 0
        ? player.duration.inMilliseconds
        : track.durationMs;
    // Queue position lives on the now-playing screen; the mini player keeps
    // only title / artist / progress / controls so it stays readable.

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: _MiniSwipeShell(
        dismissKey: ValueKey('mini-${track.id}'),
        // Swipe right -> previous, swipe left -> next. Returning false snaps the
        // card back so the mini player never leaves the footer.
        confirmDismiss: (dir) async {
          HapticFeedback.lightImpact();
          if (dir == DismissDirection.startToEnd) {
            await player.previous();
          } else {
            await player.next();
          }
          return false;
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: GestureDetector(
            onTap: _openPlayer,
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) < -500) {
                HapticFeedback.mediumImpact();
                _openPlayer();
              }
            },
            // No onDoubleTap here on purpose. A double-tap recogniser shares the
            // gesture arena with the play/pause button's own tap and deliberately
            // holds it open for the ~300ms double-tap timeout, so every press had a
            // visible lag before it registered. Play/pause is a button right there,
            // so the gesture was redundant as well as slow.
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // One row so the text, progress and time share a single baseline
                  // instead of the time squeezing the title on narrow screens.
                  // Padding is symmetric: an earlier "drag handle" strip sat above
                  // the cover with nothing below it to match, which made the card
                  // look top-heavy. It was also misleading - this card only
                  // swipes horizontally, and swipes *up* to open the player.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    child: Row(
                      children: [
                        Hero(
                          tag: 'mini-cover-${track.id}',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              width: _coverSize,
                              height: _coverSize,
                              color: SpotterfyTheme.surface,
                              child: _MiniCover(track: track),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                track.title,
                                style: TextStyle(
                                  color: SpotterfyTheme.text,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  height: 1.15,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                track.artists,
                                style: TextStyle(
                                  color: SpotterfyTheme.muted,
                                  fontSize: 13,
                                  height: 1.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              _MiniProgressRow(durationMs: durMs),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Roomier tap targets with real spacing so they are easy to
                        // hit without crowding each other. Play/pause is the only
                        // filled control, so it still reads as the primary one.
                        _MiniPlayPauseButton(player: player),
                        if (showQueueButton && player.queue.length > 1) ...[
                          const SizedBox(width: 6),
                          // Same translucent chip as the queue button on the
                          // now-playing page (_CircleControlButton), so the two read
                          // as one control rather than two different ones.
                          _MiniIconButton(
                            icon: Icons.queue_music_rounded,
                            tooltip: 'Queue',
                            size: 40,
                            iconSize: 19,
                            background: SpotterfyTheme.overlay(0.12),
                            borderColor: SpotterfyTheme.overlay(0.2),
                            foreground: SpotterfyTheme.text,
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              showQueueSheet(context, player);
                            },
                          ),
                        ],
                      ],
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

  void _openPlayer() {
    HapticFeedback.selectionClick();
    navigatorKey.currentState?.push(nowPlayingRoute(const PlayerScreen()));
  }
}

/// The footer before anything has been played.
///
/// A fresh install still gets the same card, so the layout doesn't jump the
/// first time a song starts. It shows a neutral cover and copy, and no controls
/// because there is nothing to control.
class _EmptyMiniPlayer extends StatelessWidget {
  const _EmptyMiniPlayer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Container(
              width: MiniPlayer._coverSize,
              height: MiniPlayer._coverSize,
              decoration: BoxDecoration(
                color: SpotterfyTheme.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.music_note_rounded,
                color: SpotterfyTheme.mutedDark,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Nothing playing',
                    style: TextStyle(
                      color: SpotterfyTheme.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Pick a song to start listening',
                    style: TextStyle(
                      color: SpotterfyTheme.muted,
                      fontSize: 12.5,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps the card in a Dismissible but draws the prev/next reveal layer
/// itself. Dismissible's own `background` is clipped to the rectangle the
/// card has uncovered, so the card's rounded corners would show the screen
/// behind. This layer sits under the card unclipped, so it shows through
/// the corners.
class _MiniSwipeShell extends StatefulWidget {
  final Key dismissKey;
  final Future<bool?> Function(DismissDirection) confirmDismiss;
  final Widget child;

  const _MiniSwipeShell({
    required this.dismissKey,
    required this.confirmDismiss,
    required this.child,
  });

  @override
  State<_MiniSwipeShell> createState() => _MiniSwipeShellState();
}

class _MiniSwipeShellState extends State<_MiniSwipeShell> {
  DismissDirection _dir = DismissDirection.startToEnd;
  // The reveal layer has a visible green rim, so it is only shown while the
  // card is actually displaced. At rest it stays hidden and the card's
  // anti-aliased corners can't leak a green hairline.
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final toRight = _dir == DismissDirection.startToEnd;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: _active ? 1 : 0,
              child: _SwipeRevealBackground(
                alignment: toRight
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                icon: toRight
                    ? Icons.skip_previous_rounded
                    : Icons.skip_next_rounded,
                label: toRight ? 'Previous' : 'Next',
              ),
            ),
          ),
          Dismissible(
            key: widget.dismissKey,
            direction: DismissDirection.horizontal,
            dismissThresholds: const {
              DismissDirection.startToEnd: 0.5,
              DismissDirection.endToStart: 0.5,
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
      ),
    );
  }
}

/// Progress bar plus elapsed/total time.
///
/// Split out of [MiniPlayer] and driven by `PlayerProvider`'s position and
/// buffered [ValueNotifier]s rather than by `context.watch`. The position
/// notifier ticks ~5x/second; subscribing the whole mini player to it meant the
/// cover image, two text lines and two buttons were rebuilt on every tick, on
/// every screen in the app. Only this row now repaints that often.
/// Elapsed/total time sitting directly above the progress bar.
///
/// Driven by the position and buffered notifiers rather than `context.watch`,
/// so only this widget repaints on each position tick.
class _MiniProgressRow extends StatelessWidget {
  final int durationMs;

  const _MiniProgressRow({required this.durationMs});

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerProvider>();
    final durMs = durationMs;
    final timeStyle = TextStyle(
      color: SpotterfyTheme.muted,
      fontSize: 12,
      height: 1.2,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return ValueListenableBuilder<Duration>(
      valueListenable: player.positionNotifier,
      builder: (context, pos, _) {
        return ValueListenableBuilder<Duration>(
          valueListenable: player.bufferedNotifier,
          builder: (context, buffered, _) {
            final progress = durMs > 0 ? pos.inMilliseconds / durMs : 0.0;
            final bufferedFrac = durMs > 0
                ? buffered.inMilliseconds / durMs
                : 0.0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formatDurationMs(pos.inMilliseconds),
                      style: timeStyle,
                    ),
                    Text(formatDurationMs(durMs), style: timeStyle),
                  ],
                ),
                const SizedBox(height: 2),
                _MiniProgressBar(
                  progress: progress.clamp(0.0, 1.0),
                  buffered: bufferedFrac.clamp(0.0, 1.0),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Buffered/progress bar used inside the mini player's text column.
class _MiniProgressBar extends StatelessWidget {
  final double progress;
  final double buffered;

  const _MiniProgressBar({required this.progress, required this.buffered});

  static const double _height = 5;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: _height,
        child: Stack(
          children: [
            Container(color: SpotterfyTheme.muted.withValues(alpha: 0.22)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: buffered.clamp(0.0, 1.0),
              child: Container(
                color: SpotterfyTheme.overlay(0.28),
                height: _height,
              ),
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(color: SpotterfyTheme.primary, height: _height),
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular mini player control with a guaranteed 40px+ tap target.
/// Play/pause control for the mini player.
///
/// Isolated behind a [Selector] so it rebuilds **only** when the playing state
/// flips. The rest of the mini player rebuilds on every position tick, and
/// rebuilding the button underneath an in-flight press animation is what made
/// the tap feel laggy and stuttery.
class _MiniPlayPauseButton extends StatelessWidget {
  final PlayerProvider player;

  const _MiniPlayPauseButton({required this.player});

  @override
  Widget build(BuildContext context) {
    return Selector<PlayerProvider, ({bool playing, bool loading})>(
      selector: (_, p) => (playing: p.isPlaying, loading: p.isLoading),
      builder: (context, state, _) => PlaylistPlayButton(
        size: 40,
        isPlaying: state.playing,
        isActive: state.playing,
        alwaysGreen: true,
        isLoading: state.loading,
        tooltip: state.loading ? 'Loading' : (state.playing ? 'Pause' : 'Play'),
        onPressed: () {
          HapticFeedback.lightImpact();
          player.togglePlayPause();
        },
      ),
    );
  }
}

class _MiniIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;
  final Color background;
  final Color foreground;

  /// Hairline rim, matching the circular controls on the now-playing page.
  final Color? borderColor;

  const _MiniIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.size,
    required this.iconSize,
    required this.background,
    required this.foreground,
    this.borderColor,
  });

  @override
  State<_MiniIconButton> createState() => _MiniIconButtonState();
}

class _MiniIconButtonState extends State<_MiniIconButton> {
  bool _held = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _held = true),
          onTapUp: (_) => setState(() => _held = false),
          onTapCancel: () => setState(() => _held = false),
          onTap: widget.onPressed,
          child: AnimatedScale(
            // Press-in, so the tap is acknowledged before the state changes.
            scale: _held ? 0.88 : 1.0,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: _held
                    ? Color.lerp(widget.background, SpotterfyTheme.text, 0.18)
                    : widget.background,
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.borderColor ?? Colors.transparent,
                ),
              ),
              // Cached so the press animation doesn't repaint the glyph, and so
              // the play <-> pause swap animates instead of popping.
              child: RepaintBoundary(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 170),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: Tween<double>(begin: 0.6, end: 1).animate(anim),
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: Icon(
                    widget.icon,
                    // Keying on the glyph is what tells the switcher to run the
                    // transition when play/pause changes.
                    key: ValueKey(widget.icon),
                    color: widget.foreground,
                    size: widget.iconSize,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Revealed underneath the mini player while dragging it sideways.
/// Revealed underneath the mini player while dragging it sideways.
class _SwipeRevealBackground extends StatelessWidget {
  final Alignment alignment;
  final IconData icon;
  final String label;
  const _SwipeRevealBackground({
    required this.alignment,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    // Lighter than the card (0xFF121212) so the card's rounded corners read
    // against it, with a green rim. The rim follows the same 20px radius as
    // the card, so it traces the revealed area cleanly.
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (alignment == Alignment.centerRight) ...[
            Text(
              label,
              style: TextStyle(
                color: SpotterfyTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Icon(icon, color: SpotterfyTheme.primary, size: 24),
          if (alignment == Alignment.centerLeft) ...[
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: SpotterfyTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniCover extends StatelessWidget {
  final dynamic track;
  const _MiniCover({required this.track});

  @override
  Widget build(BuildContext context) {
    final TrackModel t = track as TrackModel;
    // `artwork` supplies YouTube's own thumbnail for songs the backend returned
    // without one, so the mini player matches the row the song was played from.
    if (t.artwork.isNotEmpty) {
      // Use the same on-disk cache as the now-playing page. A plain Image.network
      // only survives in memory, which is why the large cover came back offline
      // while this one fell back to the note icon.
      return CachedNetworkImage(
        imageUrl: t.artwork,
        fit: BoxFit.cover,
        memCacheWidth: (MiniPlayer._coverSize * 3).round(),
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, _) => Container(color: SpotterfyTheme.surface),
        errorWidget: (_, _, _) =>
            Icon(Icons.music_note, color: SpotterfyTheme.muted, size: 24),
      );
    }
    final String src = t.sourceUrl;
    final bool isStorage =
        t.id.startsWith('storage_') ||
        src.startsWith('/') ||
        src.startsWith('file://');
    if (isStorage && src.isNotEmpty) {
      return StorageCover(
        path: src.replaceFirst('file://', ''),
        size: 54,
        iconSize: 26,
        radius: 14,
      );
    }
    return Icon(Icons.music_note, color: SpotterfyTheme.muted, size: 24);
  }
}
