import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:spotterfy_app/widgets/storage_cover.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  /// Accumulated downward drag distance, used together with release velocity so
  /// a slow deliberate swipe-down also dismisses the page.
  double _dragDy = 0;

  /// 0..1 drag progress, drives the sheet-like offset + handle highlight.
  /// A ValueNotifier (not setState) so dragging only rebuilds this subtree
  /// instead of the whole page every frame.
  final ValueNotifier<double> _dragProgress = ValueNotifier(0);

  static const double _dismissDistance = 110;

  @override
  void dispose() {
    _dragProgress.dispose();
    super.dispose();
  }

  void _resetDrag() {
    _dragDy = 0;
    _dragProgress.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final track = player.currentTrack;

    if (track == null) {
      return Scaffold(
        backgroundColor: SpotterfyTheme.background,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: Center(
          child: Text(
            'No track selected',
            style: TextStyle(color: SpotterfyTheme.muted),
          ),
        ),
      );
    }

    final isRadio = player.isRadio;
    final pos = player.position;
    final dur = isRadio
        ? (player.radioMaxListened.inMilliseconds > 0
              ? player.radioMaxListened
              : const Duration(seconds: 1))
        : player.duration;
    final sliderVal = dur.inMilliseconds > 0
        ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final queue = player.queue;
    final currentIndex = player.currentIndex.clamp(
      0,
      queue.isEmpty ? 0 : queue.length - 1,
    );

    return Scaffold(
      // Transparent so the page underneath stays visible: the backdrop below
      // paints Spotify black at rest, but dissolves as the sheet is pulled
      // down, revealing the list behind it.
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // Plain arrow, no extra wrapper/padding chrome.
        leading: IconButton(
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Colors.white,
            size: 30,
          ),
          tooltip: 'Minimise',
          onPressed: () => Navigator.pop(context),
        ),
        // No app-bar actions: the queue button lives with the transport
        // controls lower down the page.
      ),
      body: ValueListenableBuilder<double>(
        valueListenable: _dragProgress,
        child: GestureDetector(
          // Swipe down anywhere to dismiss. Driven by accumulated drag
          // distance as well as release velocity so a slow, deliberate
          // downward drag works, not just a fast flick.
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: (d) {
            // Only track downward drags; upward is ignored.
            if (d.delta.dy > 0) _dragDy += d.delta.dy;
            _dragProgress.value = (_dragDy / _dismissDistance).clamp(0.0, 1.0);
          },
          onVerticalDragEnd: (d) {
            final flung = (d.primaryVelocity ?? 0) > 500;
            if (_dragDy > _dismissDistance * 0.8 || flung) {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            }
            _resetDrag();
          },
          onVerticalDragCancel: _resetDrag,
          child: SafeArea(
            child: ValueListenableBuilder<double>(
              valueListenable: _dragProgress,
              builder: (context, drag, child) {
                return Transform.translate(
                  // Tracks the finger 1:1 (drag * _dismissDistance == _dragDy)
                  // so the page can be pulled down and held at any point.
                  offset: Offset(0, drag * _dismissDistance),
                  child: Opacity(
                    // Slight fade only; the page must stay readable so the
                    // layout above the revealed area is still clear.
                    opacity: 1 - drag * 0.25,
                    child: child,
                  ),
                );
              },
              child: Padding(
                // Top padding clears the transparent app bar so the drag
                // handle is fully visible.
                padding: const EdgeInsets.fromLTRB(28, 52, 28, 20),
                child: Column(
                  children: [
                    // Drag handle at the very top - swipe down here (or
                    // anywhere on the page) to dismiss.
                    ValueListenableBuilder<double>(
                      valueListenable: _dragProgress,
                      builder: (context, drag, _) => Container(
                        width: 40 + drag * 14,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(
                            alpha: 0.22 + drag * 0.5,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // More room above the cover than below it, so the cover
                    // sits higher and the text/controls below ride up.
                    const Spacer(flex: 4),
                    if (!isRadio && queue.length > 1)
                      _CoverCarousel(
                        key: ValueKey(
                          'carousel-${queue.length}-${queue.first.id}-${queue.last.id}',
                        ),
                        tracks: queue,
                        currentIndex: currentIndex,
                        onPageSelected: (i) {
                          if (i != player.currentIndex) {
                            player.playFromQueue(i);
                          }
                        },
                      )
                    else
                      _StaticCover(track: track),
                    const Spacer(flex: 2),
                    // Title block in a fixed-width column so the text stays
                    // centred and never collides with the controls below.
                    SizedBox(
                      width: double.infinity,
                      child: Column(
                        children: [
                          Text(
                            track.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            track.artists,
                            style: const TextStyle(
                              color: SpotterfyTheme.muted,
                              fontSize: 15,
                              height: 1.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    _SeekBar(
                      progress: sliderVal.clamp(0.0, 1.0),
                      buffered: dur.inMilliseconds > 0
                          ? (player.buffered.inMilliseconds /
                                    dur.inMilliseconds)
                                .clamp(0.0, 1.0)
                          : 0.0,
                      onSeek: (v) {
                        final raw = Duration(
                          milliseconds: (v * dur.inMilliseconds).round(),
                        );
                        final newPos = isRadio
                            ? Duration(
                                milliseconds: raw.inMilliseconds.clamp(
                                  0,
                                  player.radioMaxListened.inMilliseconds,
                                ),
                              )
                            : raw;
                        player.seekTo(newPos);
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _fmtDuration(pos),
                            style: const TextStyle(
                              color: SpotterfyTheme.muted,
                              fontSize: 12,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          Text(
                            _fmtDuration(dur),
                            style: const TextStyle(
                              color: SpotterfyTheme.muted,
                              fontSize: 12,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Controls: symmetric layout so play/pause is always dead
                    // centre regardless of whether the skip buttons are shown.
                    _PlayerControls(player: player, isRadio: isRadio),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 20,
                      child: Center(
                        child: !isRadio
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${currentIndex + 1} / ${player.queue.length} in queue',
                                    style: const TextStyle(
                                      color: SpotterfyTheme.muted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  // Queue button now sits on the page, styled
                                  // like the other controls instead of the
                                  // solid app-bar circle.
                                  _CircleControlButton(
                                    icon: Icons.queue_music_rounded,
                                    tooltip: 'Queue',
                                    size: 30,
                                    iconSize: 16,
                                    onTap: () => _showQueueDialog(
                                      context,
                                      player,
                                      track,
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'LIVE',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Radio • can seek back ${player.radioMaxListened.inSeconds ~/ 60} min',
                                    style: const TextStyle(
                                      color: SpotterfyTheme.muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
        builder: (context, drag, content) {
          return ClipRRect(
            // Top corners round off as the sheet is pulled down, reinforcing
            // that it is a layer sitting above the page rather than that page.
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(30 * drag),
            ),
            child: Stack(
              children: [
                Opacity(
                  // The Spotify-black + green backdrop dissolves as the sheet
                  // drops, letting the page underneath show through. This is
                  // what makes the player look like it is floating above it.
                  opacity: 1 - drag * 0.88,
                  child: const SizedBox.expand(child: _AnimatedGreenBackdrop()),
                ),
                content!,
              ],
            ),
          );
        },
      ),
    );
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _showQueueDialog(
    BuildContext context,
    PlayerProvider player,
    TrackModel currentTrack,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: SpotterfyTheme.surface,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Up Next',
                    style: TextStyle(
                      color: SpotterfyTheme.text,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (player.queue.length > 1)
                    TextButton(
                      onPressed: () => player.clearQueue(),
                      child: Text(
                        'Clear',
                        style: TextStyle(
                          color: SpotterfyTheme.primary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (player.queue.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'No tracks in queue',
                    style: TextStyle(color: SpotterfyTheme.muted),
                  ),
                )
              else
                ...player.queue.asMap().entries.map((entry) {
                  final index = entry.key;
                  final track = entry.value;
                  final isCurrent = player.currentIndex == index;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      player.playFromQueue(index);
                      Navigator.pop(context);
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? SpotterfyTheme.card
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: SpotterfyTheme.card,
                          width: isCurrent ? 0 : 0.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          if (isCurrent)
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: SpotterfyTheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.music_note_rounded,
                                color: Colors.black,
                                size: 14,
                              ),
                            )
                          else
                            const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 16,
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
                                        ? SpotterfyTheme.text
                                        : SpotterfyTheme.muted,
                                    fontWeight: isCurrent
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  track.artists,
                                  style: TextStyle(
                                    color: isCurrent
                                        ? SpotterfyTheme.muted
                                        : SpotterfyTheme.mutedDark,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (!isCurrent)
                            IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                player.removeFromQueue(index);
                              },
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Close',
                    style: TextStyle(color: SpotterfyTheme.muted),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Slowly drifting green gradient glows plus a field of soft green particles
/// rising through them. Loops forever and is wrapped in a RepaintBoundary so
/// the animation never dirties the rest of the player UI each frame.
class _AnimatedGreenBackdrop extends StatefulWidget {
  const _AnimatedGreenBackdrop();

  @override
  State<_AnimatedGreenBackdrop> createState() => _AnimatedGreenBackdropState();
}

class _AnimatedGreenBackdropState extends State<_AnimatedGreenBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          // Full 0..1 cycle drives both the drift and a gentle opacity swell.
          final t = _ctrl.value * 2 * math.pi;
          return Stack(
            children: [
              // Base wash: deep green tint over Spotify black.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.55),
                      radius: 1.3,
                      colors: [
                        SpotterfyTheme.primary.withValues(alpha: 0.16),
                        const Color(0xFF000000),
                      ],
                    ),
                  ),
                ),
              ),
              // Two slow-moving soft spots.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(
                        -0.55 + 0.30 * math.sin(t),
                        -0.55 + 0.16 * math.cos(t),
                      ),
                      // Wide + soft so it reads as a glowing spot, not a dot.
                      radius: 0.95,
                      colors: [
                        SpotterfyTheme.primary.withValues(
                          alpha: 0.32 + 0.07 * math.sin(t),
                        ),
                        SpotterfyTheme.primary.withValues(
                          alpha: 0.10 + 0.03 * math.cos(t * 1.3),
                        ),
                        SpotterfyTheme.primary.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(
                        0.65 + 0.26 * math.cos(t * 0.8),
                        0.30 + 0.20 * math.sin(t * 0.7),
                      ),
                      radius: 0.85,
                      colors: [
                        SpotterfyTheme.primaryDark.withValues(
                          alpha: 0.26 + 0.06 * math.cos(t * 1.2),
                        ),
                        SpotterfyTheme.primaryDark.withValues(alpha: 0.08),
                        SpotterfyTheme.primaryDark.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
              // Vignette so the text/controls stay readable.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.45),
                        Colors.black.withValues(alpha: 0.10),
                        Colors.black.withValues(alpha: 0.45),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Play/pause flanked by the skip buttons, laid out symmetrically so the
/// primary control is always centred (including for radio, where the skip
/// buttons are replaced by equal-width spacers).
class _PlayerControls extends StatelessWidget {
  final PlayerProvider player;
  final bool isRadio;

  const _PlayerControls({required this.player, required this.isRadio});

  @override
  Widget build(BuildContext context) {
    const side = 48.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!isRadio)
          _CircleControlButton(
            icon: Icons.skip_previous_rounded,
            tooltip: 'Previous',
            onTap: () {
              HapticFeedback.lightImpact();
              player.previous();
            },
          )
        else
          const SizedBox(width: side),
        const SizedBox(width: 32),
        _PlayPauseButton(
          isPlaying: player.isPlaying,
          onTap: () {
            HapticFeedback.lightImpact();
            player.togglePlayPause();
          },
        ),
        const SizedBox(width: 32),
        if (!isRadio)
          _CircleControlButton(
            icon: Icons.skip_next_rounded,
            tooltip: 'Next',
            onTap: () {
              HapticFeedback.lightImpact();
              player.next();
            },
          )
        else
          const SizedBox(width: side),
      ],
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onTap;

  const _PlayPauseButton({required this.isPlaying, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SpotterfyTheme.primary,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 68,
          height: 68,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: SpotterfyTheme.primary.withValues(alpha: 0.35),
                blurRadius: 16,
              ),
            ],
          ),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.black,
            size: 34,
          ),
        ),
      ),
    );
  }
}

/// Single (non-carousel) square cover.
class _StaticCover extends StatelessWidget {
  final TrackModel track;
  const _StaticCover({required this.track});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Square that fits the available box without overflowing.
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        return Center(
          child: SizedBox(
            width: side,
            height: side,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                color: SpotterfyTheme.surface,
                child: _PlayerCover(track: track),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CoverCarousel extends StatefulWidget {
  final List<TrackModel> tracks;
  final int currentIndex;
  final ValueChanged<int> onPageSelected;
  const _CoverCarousel({
    super.key,
    required this.tracks,
    required this.currentIndex,
    required this.onPageSelected,
  });

  @override
  State<_CoverCarousel> createState() => _CoverCarouselState();
}

class _CoverCarouselState extends State<_CoverCarousel> {
  late PageController _ctrl;
  late int _current;

  /// Fraction of the available width a single page occupies. `PageView` centres
  /// the pages (via `padEnds`), so the leftover width is split evenly and is
  /// what makes the previous/next cover peek in - the neighbours are already
  /// partly visible before you swipe, instead of only appearing once a page has
  /// scrolled all the way over.
  static const double _viewportFraction = 0.76;

  /// Gap between a cover and the edges of its page, so neighbouring covers
  /// don't touch.
  static const double _pageInset = 8;

  /// How far a neighbour shrinks once it is a full page away. Kept close to 1
  /// so the shrunk cover still reaches the screen edge and stays visible in the
  /// peek strip; the page size difference already reads strongly.
  static const double _inactiveScale = 0.9;

  /// Fractional scroll position. Tracked continuously while dragging so covers
  /// grow/shrink in step with the finger rather than snapping on page change.
  final ValueNotifier<double> _position = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _current = widget.currentIndex.clamp(0, widget.tracks.length - 1);
    _position.value = _current.toDouble();
    _ctrl = PageController(
      viewportFraction: _viewportFraction,
      initialPage: _current,
    )..addListener(_onScroll);
  }

  void _onScroll() {
    final page = _ctrl.page;
    if (page == null) return;
    // Skip sub-pixel noise so we don't rebuild every frame when idle.
    if ((_position.value - page).abs() < 0.001) return;
    _position.value = page;
  }

  @override
  void didUpdateWidget(covariant _CoverCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newIdx = widget.currentIndex.clamp(0, widget.tracks.length - 1);
    if (newIdx != _current && _ctrl.hasClients) {
      _current = newIdx;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_ctrl.hasClients) return;
        _ctrl.animateToPage(
          _current,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onScroll);
    _ctrl.dispose();
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pageWidth = constraints.maxWidth * _viewportFraction;
        // Square cover: fills its page minus the inset, but never taller than
        // the space the column gave us (prevents overflow on short screens).
        final side = math.min(pageWidth - _pageInset, constraints.maxHeight);
        return SizedBox(
          height: side,
          child: PageView.builder(
            controller: _ctrl,
            itemCount: widget.tracks.length,
            onPageChanged: (i) {
              if (i == _current) return;
              _current = i;
              HapticFeedback.selectionClick();
              widget.onPageSelected(i);
            },
            itemBuilder: (_, i) => _CarouselPage(
              position: _position,
              index: i,
              inactiveScale: _inactiveScale,
              // Built once per page; only the transform around it changes.
              child: SizedBox(
                width: side,
                height: side,
                child: _PlayerCover(track: widget.tracks[i]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A single carousel page, scaled/dimmed continuously from how far it currently
/// sits from the centred page. Driving the transform from the live scroll
/// position (instead of an `isCurrent` flag) is what makes the covers ease
/// bigger/smaller while the finger is still moving.
class _CarouselPage extends StatelessWidget {
  final ValueListenable<double> position;
  final int index;
  final double inactiveScale;
  final Widget child;

  const _CarouselPage({
    required this.position,
    required this.index,
    required this.inactiveScale,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: position,
      child: child,
      builder: (context, pos, cover) {
        // 0 while centred, 1 once a full page away.
        final d = (pos - index).abs().clamp(0.0, 1.0);
        // Eased so the shrink settles rather than tracking the finger linearly.
        final e = Curves.easeOutCubic.transform(d);
        return Center(
          child: Transform.translate(
            // Neighbours sink slightly, which adds depth to the size change.
            offset: Offset(0, 8 * e),
            child: Transform.scale(
              scale: 1 - (1 - inactiveScale) * e,
              child: Opacity(
                opacity: 1 - 0.4 * e,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22 - 6 * e),
                  child: ColoredBox(
                    color: SpotterfyTheme.surface,
                    child: cover,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CircleControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final double size;
  final double iconSize;
  const _CircleControlButton({
    required this.icon,
    required this.onTap,
    this.tooltip = '',
    this.size = 48,
    this.iconSize = 26,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.12),
        shape: CircleBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: Colors.white, size: iconSize),
          ),
        ),
      ),
    );
  }
}

class _SeekBar extends StatelessWidget {
  final double progress;
  final double buffered;
  final ValueChanged<double> onSeek;
  const _SeekBar({
    required this.progress,
    required this.buffered,
    required this.onSeek,
  });

  void _seekByOffset(BuildContext context, Offset local, double width) {
    if (width <= 0) return;
    onSeek((local.dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    final b = buffered.clamp(0.0, 1.0);
    return GestureDetector(
      // Translucent (not opaque) so a vertical drag starting on the seek bar
      // still reaches the page-level swipe-down-to-dismiss handler.
      behavior: HitTestBehavior.translucent,
      onHorizontalDragDown: (d) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) {
          _seekByOffset(
            context,
            box.globalToLocal(d.globalPosition),
            box.size.width,
          );
        }
      },
      onHorizontalDragUpdate: (d) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) {
          _seekByOffset(
            context,
            box.globalToLocal(d.globalPosition),
            box.size.width,
          );
        }
      },
      child: SizedBox(
        height: 28,
        child: LayoutBuilder(
          builder: (_, constraints) {
            final w = constraints.maxWidth;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 12,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: SizedBox(
                      height: 4,
                      child: Stack(
                        children: [
                          Container(color: SpotterfyTheme.card),
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: b,
                            child: Container(
                              color: Colors.white.withValues(alpha: 0.35),
                            ),
                          ),
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: p,
                            child: Container(color: SpotterfyTheme.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (p > 0.005)
                  Positioned(
                    left: (w * p - 7).clamp(0.0, w - 14),
                    top: 7,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: SpotterfyTheme.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: SpotterfyTheme.primary.withValues(
                              alpha: 0.4,
                            ),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlayerCover extends StatelessWidget {
  final TrackModel track;
  const _PlayerCover({required this.track});

  @override
  Widget build(BuildContext context) {
    if (track.cover.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: track.cover,
        fit: BoxFit.cover,
        memCacheWidth: 560,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (_, _) => Container(color: SpotterfyTheme.surface),
        errorWidget: (_, _, _) =>
            const Icon(Icons.music_note, color: SpotterfyTheme.muted, size: 64),
      );
    }
    final src = track.sourceUrl;
    final isStorage =
        track.id.startsWith('storage_') ||
        src.startsWith('/') ||
        src.startsWith('file://');
    if (isStorage && src.isNotEmpty) {
      // StorageCover takes a fixed size, so derive it from the incoming box to
      // fill both the carousel and the single-cover layouts exactly.
      return LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.biggest.shortestSide;
          return StorageCover(
            path: src.replaceFirst('file://', ''),
            size: side.isFinite ? side : 280,
            iconSize: 64,
            radius: 16,
          );
        },
      );
    }
    return const Icon(Icons.music_note, color: SpotterfyTheme.muted, size: 64);
  }
}
