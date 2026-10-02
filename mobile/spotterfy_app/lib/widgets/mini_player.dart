import 'package:flutter/material.dart';
import 'package:spotterfy_app/widgets/queue_sheet.dart';
import 'package:spotterfy_app/widgets/storage_cover.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/screens/player_screen.dart';
import 'package:spotterfy_app/widgets/swipe_navigation.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/main.dart';

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

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final track = player.currentTrack;
    if (track == null) return const SizedBox.shrink();

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

    return Dismissible(
      key: ValueKey('mini-${track.id}'),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.4,
        DismissDirection.endToStart: 0.4,
      },
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
      background: _SwipeRevealBackground(
        alignment: Alignment.centerLeft,
        icon: Icons.skip_previous,
        label: 'Previous',
      ),
      secondaryBackground: _SwipeRevealBackground(
        alignment: Alignment.centerRight,
        icon: Icons.skip_next,
        label: 'Next',
      ),
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
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          decoration: BoxDecoration(
            color: SpotterfyTheme.card,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 22,
                offset: const Offset(0, -4),
              ),
            ],
            border: Border.all(
              color: SpotterfyTheme.primary.withValues(alpha: 0.18),
              width: 1,
            ),
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
                              fontSize: 15,
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
                              fontSize: 12,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 7),
                          _MiniProgressRow(durationMs: durMs),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Roomier tap targets: 42px buttons with real spacing so
                    // they are easy to hit without crowding each other. The
                    // play/pause is the only filled + glowing control, so it
                    // reads as the primary one.
                    _MiniPlayPauseButton(player: player),
                    if (showQueueButton && player.queue.length > 1) ...[
                      const SizedBox(width: 6),
                      // Same translucent white circle as the queue button on the
                      // now-playing page, so the two read as one control.
                      _MiniIconButton(
                        icon: Icons.queue_music_rounded,
                        tooltip: 'Queue',
                        size: 42,
                        iconSize: 21,
                        background: Colors.white.withValues(alpha: 0.10),
                        borderColor: Colors.white.withValues(alpha: 0.14),
                        foreground: Colors.white,
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
    );
  }

  void _openPlayer() {
    HapticFeedback.selectionClick();
    navigatorKey.currentState?.push(nowPlayingRoute(const PlayerScreen()));
  }
}

/// Progress bar plus elapsed/total time.
///
/// Split out of [MiniPlayer] and driven by `PlayerProvider`'s position and
/// buffered [ValueNotifier]s rather than by `context.watch`. The position
/// notifier ticks ~5x/second; subscribing the whole mini player to it meant the
/// cover image, two text lines and two buttons were rebuilt on every tick, on
/// every screen in the app. Only this row now repaints that often.
class _MiniProgressRow extends StatelessWidget {
  final int durationMs;

  const _MiniProgressRow({required this.durationMs});

  static String _fmtDuration(int ms) {
    final minutes = ms ~/ 60000;
    final seconds = (ms % 60000) ~/ 1000;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerProvider>();
    final durMs = durationMs;
    return Row(
      children: [
        Expanded(
          child: ValueListenableBuilder<Duration>(
            valueListenable: player.positionNotifier,
            builder: (context, pos, _) {
              return ValueListenableBuilder<Duration>(
                valueListenable: player.bufferedNotifier,
                builder: (context, buffered, _) {
                  final progress = durMs > 0 ? pos.inMilliseconds / durMs : 0.0;
                  final bufferedFrac = durMs > 0
                      ? buffered.inMilliseconds / durMs
                      : 0.0;
                  return _MiniProgressBar(
                    progress: progress.clamp(0.0, 1.0),
                    buffered: bufferedFrac.clamp(0.0, 1.0),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        ValueListenableBuilder<Duration>(
          valueListenable: player.positionNotifier,
          builder: (context, pos, _) => Text(
            '${_fmtDuration(pos.inMilliseconds)} / ${_fmtDuration(durMs)}',
            style: TextStyle(
              color: SpotterfyTheme.muted,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// Thin buffered/progress bar used inside the mini player's text column.
class _MiniProgressBar extends StatelessWidget {
  final double progress;
  final double buffered;

  const _MiniProgressBar({required this.progress, required this.buffered});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 3,
        child: Stack(
          children: [
            Container(color: SpotterfyTheme.muted.withValues(alpha: 0.22)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: buffered.clamp(0.0, 1.0),
              child: Container(
                color: Colors.white.withValues(alpha: 0.28),
                height: 3,
              ),
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(color: SpotterfyTheme.primary, height: 3),
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
    return Selector<PlayerProvider, bool>(
      selector: (_, p) => p.isPlaying,
      builder: (context, isPlaying, _) => _MiniIconButton(
        icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
        tooltip: isPlaying ? 'Pause' : 'Play',
        size: 42,
        iconSize: 24,
        background: SpotterfyTheme.primary,
        glow: SpotterfyTheme.primary,
        foreground: Colors.black,
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

  /// Soft coloured halo. Only the primary (play/pause) control uses it, so the
  /// eye lands there first.
  final Color? glow;

  const _MiniIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.size,
    required this.iconSize,
    required this.background,
    required this.foreground,
    this.borderColor,
    this.glow,
  });

  @override
  State<_MiniIconButton> createState() => _MiniIconButtonState();
}

class _MiniIconButtonState extends State<_MiniIconButton> {
  bool _held = false;

  @override
  Widget build(BuildContext context) {
    final glow = widget.glow;
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
                color: _held && glow != null
                    ? Color.lerp(widget.background, Colors.white, 0.18)
                    : widget.background,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _held && glow != null
                      ? Colors.transparent
                      : (widget.borderColor ?? Colors.transparent),
                ),
                boxShadow: [
                  if (glow != null)
                    BoxShadow(
                      color: glow.withValues(alpha: _held ? 0.55 : 0.35),
                      blurRadius: _held ? 18 : 12,
                      spreadRadius: _held ? 1 : 0,
                    ),
                ],
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
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      decoration: BoxDecoration(
        color: SpotterfyTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: SpotterfyTheme.primary.withValues(alpha: 0.25),
        ),
      ),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: SpotterfyTheme.primary, size: 22),
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
      ),
    );
  }
}

class _MiniCover extends StatelessWidget {
  final dynamic track;
  const _MiniCover({required this.track});

  @override
  Widget build(BuildContext context) {
    if (track.cover != null && (track.cover as String).isNotEmpty) {
      return Image.network(
        track.cover as String,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) =>
            Icon(Icons.music_note, color: SpotterfyTheme.muted, size: 24),
      );
    }
    final String src = track.sourceUrl as String? ?? '';
    final bool isStorage =
        (track.id as String).startsWith('storage_') ||
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
