import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:spotterfy_app/widgets/storage_cover.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:spotterfy_app/widgets/queue_sheet.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with SingleTickerProviderStateMixin {
  /// Downward drag distance accumulated by the swipe-down-to-close gesture.
  double _dragDy = 0;

  /// 0..1 of [dismissDistance] reached. Drives only the scale feedback - the
  /// page is never translated or made transparent, so it can never look like
  /// it is stuck halfway open.
  final ValueNotifier<double> _dragProgress = ValueNotifier(0);

  /// Eases the scale back to rest when the swipe falls short of the threshold.
  late final AnimationController _springCtrl;

  bool _thresholdHapticDone = false;
  bool _dismissing = false;

  static const double _dismissDistance = 110;

  @override
  void initState() {
    super.initState();
    _springCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void dispose() {
    _springCtrl.dispose();
    _dragProgress.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _springCtrl.stop();
    if (d.delta.dy > 0) _dragDy += d.delta.dy;
    if (_dragDy < 0) _dragDy = 0;
    final p = (_dragDy / _dismissDistance).clamp(0.0, 1.0);
    _dragProgress.value = p;
    // Tell the user the moment the gesture becomes a dismiss, so releasing
    // early doesn't feel broken.
    if (!_thresholdHapticDone && p >= 0.8) {
      _thresholdHapticDone = true;
      HapticFeedback.selectionClick();
    }
  }

  void _onDragEnd(DragEndDetails d) {
    final flung = (d.primaryVelocity ?? 0) > 500;
    if (_dragDy > _dismissDistance * 0.8 || flung) {
      _dismiss();
    } else {
      _springBack();
    }
  }

  Future<void> _springBack() async {
    _dragDy = 0;
    _thresholdHapticDone = false;
    if (_springCtrl.isAnimating) return;
    final from = _dragProgress.value;
    if (from <= 0.001) {
      _dragProgress.value = 0;
      return;
    }
    final tween = Tween<double>(
      begin: from,
      end: 0,
    ).animate(CurvedAnimation(parent: _springCtrl, curve: Curves.easeOutCubic));
    void tick() => _dragProgress.value = tween.value;
    _springCtrl.addListener(tick);
    try {
      await _springCtrl.forward(from: 0);
    } finally {
      _springCtrl.removeListener(tick);
      _dragProgress.value = 0;
    }
  }

  /// Closes the page. All of the motion is the route's own transition, which is
  /// configured to match the queue's bottom sheet.
  void _dismiss() {
    if (_dismissing) return;
    _dismissing = true;
    _springCtrl.stop();
    HapticFeedback.lightImpact();
    Navigator.pop(context);
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
    // `pos` and `sliderVal` are intentionally NOT read here. The seek bar and
    // the elapsed time are wrapped in [_SeekSection], which subscribes to the
    // position notifier itself - reading position at the top of this build made
    // the whole now-playing page (backdrop, carousel, controls) rebuild on every
    // tick of a playing track.
    final dur = isRadio
        ? (player.radioMaxListened.inMilliseconds > 0
              ? player.radioMaxListened
              : const Duration(seconds: 1))
        : player.duration;
    final queue = player.queue;
    final currentIndex = player.currentIndex.clamp(
      0,
      queue.isEmpty ? 0 : queue.length - 1,
    );

    return Scaffold(
      // Fully opaque Spotify black. The page used to be a translucent "sheet"
      // that dissolved as it was dragged, which is what made it look like it
      // opened halfway and went see-through. It is now a plain full-screen page
      // whose only motion is the route transition.
      backgroundColor: const Color(0xFF000000),
      // No AppBar on purpose. The buttons are positioned in the body instead:
      // a transparent AppBar still sits *on top* of the body and swallows taps
      // across its whole 56px band, which is what made the offset queue button
      // unreachable (and visually clipped) before.
      body: Stack(
        children: [
          const Positioned.fill(child: _AnimatedGreenBackdrop()),
          // Swipe down anywhere to close. Feedback is a slight scale-down only:
          // no translation and no opacity change, so the page stays solid and
          // fully open while the gesture is in progress. Horizontal swipes are
          // untouched, so the cover carousel still works.
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragUpdate: _onDragUpdate,
            onVerticalDragEnd: _onDragEnd,
            onVerticalDragCancel: _springBack,
            child: ValueListenableBuilder<double>(
              valueListenable: _dragProgress,
              child: SafeArea(
                child: Padding(
                  // Top padding clears the arrow and the queue button sitting in
                  // the corners above.
                  padding: const EdgeInsets.fromLTRB(28, 74, 28, 20),
                  child: Column(
                    children: [
                      // Slightly less space above the cover than below the
                      // controls, so the whole block rides a little above the
                      // vertical centre of the page.
                      const Spacer(flex: 2),
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
                              style: TextStyle(
                                color: SpotterfyTheme.text,
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
                              style: TextStyle(
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
                      _SeekSection(duration: dur, isRadio: isRadio),
                      const SizedBox(height: 20),
                      // Controls: symmetric layout so play/pause is always dead
                      // centre regardless of whether the skip buttons are shown.
                      _PlayerControls(player: player, isRadio: isRadio),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 20,
                        child: Center(
                          child: !isRadio
                              ? Text(
                                  '${currentIndex + 1} / ${player.queue.length} in queue',
                                  style: TextStyle(
                                    color: SpotterfyTheme.muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
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
                                      style: TextStyle(
                                        color: SpotterfyTheme.muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Larger than the top spacer, which is what tips the
                      // content up above the centre line.
                      const Spacer(flex: 3),
                    ],
                  ),
                ),
              ),
              builder: (context, drag, content) => Transform.scale(
                // Slight shrink while swiping. Deliberately not a translation
                // or a fade, so the page never looks half-open or see-through.
                scale: 1 - drag * 0.04,
                child: content,
              ),
            ),
          ),
          // Layered last so the buttons win hit-testing over the content.
          _pageChrome(player, isRadio),
        ],
      ),
    );
  }

  /// Top-left minimise arrow + top-right queue button.
  ///
  /// Returned as a full-size [Stack] with [Positioned] children so it can be
  /// layered over the page content (and therefore take taps) without consuming
  /// any vertical space in the layout.
  Widget _pageChrome(PlayerProvider player, bool isRadio) {
    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned(
            top: MediaQuery.paddingOf(context).top + 2,
            left: 6,
            child: IconButton(
              // Plain arrow, no extra wrapper/padding chrome.
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: SpotterfyTheme.text,
                size: 30,
              ),
              tooltip: 'Minimise',
              onPressed: _dismiss,
            ),
          ),
          if (!isRadio)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 20,
              right: 10,
              child: _CircleControlButton(
                icon: Icons.queue_music_rounded,
                tooltip: 'Queue',
                // No size overrides: the shared defaults (48 circle / 26 glyph)
                // are exactly what the previous/next buttons use, so all three
                // stay visually identical. Overriding them here is what made
                // the queue icon look a different size.
                onTap: () => showQueueSheet(context, player),
              ),
            ),
        ],
      ),
    );
  }
}

/// Formats a duration as `m:ss`. Top level rather than a member so the seek
/// section can use it after the position read was moved out of the screen build.
String _fmtDuration(Duration d) {
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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
      duration: const Duration(seconds: 24),
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

          // One large, soft green spot. Kept as a helper because the page is
          // purely black apart from these - no overall green wash - so each
          // spot has to carry the colour on its own.
          Widget spot(
            Alignment center,
            double radius,
            Color color,
            double core,
            double mid,
          ) {
            return Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: center,
                    radius: radius,
                    colors: [
                      color.withValues(alpha: core),
                      color.withValues(alpha: mid),
                      color.withValues(alpha: 0),
                    ],
                    stops: const [0.0, 0.38, 1.0],
                  ),
                ),
              ),
            );
          }

          return Stack(
            children: [
              // Pure black base.
              const Positioned.fill(
                child: ColoredBox(color: Color(0xFF000000)),
              ),
              // Three slow-drifting greenish spots.
              //
              // Every term is an INTEGER multiple of [t]. That matters: [t] runs
              // 0..2*pi and the controller loops, so any fractional multiple
              // (t*0.8, t*0.6, ...) lands on a different value at the loop
              // boundary and makes the spots visibly jump every cycle. Integer
              // multiples repeat exactly, so the loop is seamless while the
              // three spots still move at different speeds.
              spot(
                Alignment(
                  -0.45 + 0.34 * math.sin(t),
                  -0.40 + 0.18 * math.cos(t),
                ),
                0.88,
                SpotterfyTheme.primary,
                0.40 + 0.08 * math.sin(t),
                0.12,
              ),
              spot(
                Alignment(0.60 + 0.28 * math.cos(t), 0.30 + 0.22 * math.sin(t)),
                0.80,
                SpotterfyTheme.primaryDark,
                0.30 + 0.07 * math.cos(t),
                0.09,
              ),
              spot(
                Alignment(
                  0.12 * math.cos(2 * t),
                  0.78 + 0.14 * math.sin(2 * t),
                ),
                0.72,
                SpotterfyTheme.primary,
                0.18 + 0.05 * math.sin(2 * t),
                0.05,
              ),
              // Radial vignette: darkens the edges so the art and text stay the
              // focus while the spots read as light sources.
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      radius: 1.05,
                      colors: [Color(0x00000000), Color(0x8C000000)],
                      stops: [0.5, 1.0],
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
  ///
  /// Kept small enough that the neighbours (which are further shrunk by
  /// [_inactiveScale]) still reach the screen edge and stay visible in the
  /// peek strip.
  static const double _viewportFraction = 0.72;

  /// Gap between a cover and the edges of its page, so neighbouring covers
  /// don't touch.
  static const double _pageInset = 8;

  /// How far a neighbour shrinks once it is a full page away.
  static const double _inactiveScale = 0.84;

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
        // No vertical offset: every cover stays on the same centre line, so the
        // neighbours line up horizontally with the middle (playing) cover
        // instead of sitting slightly lower than it.
        return Center(
          child: Transform.scale(
            scale: 1 - (1 - inactiveScale) * e,
            child: Opacity(
              opacity: 1 - 0.4 * e,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22 - 6 * e),
                child: ColoredBox(color: SpotterfyTheme.surface, child: cover),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Circular transport control used for previous / next / queue.
///
/// The dimensions are fixed constants rather than parameters: the queue button
/// used to override them and ended up a different size from the skip buttons,
/// and per-call overrides are exactly what let that drift back in.
class _CircleControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  /// Every circular control on the page shares these, so they always match.
  static const double _diameter = 48;
  static const double _glyph = 26;

  const _CircleControlButton({
    required this.icon,
    required this.onTap,
    this.tooltip = '',
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: SpotterfyTheme.overlay(0.12),
        shape: CircleBorder(
          side: BorderSide(color: SpotterfyTheme.overlay(0.2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: _diameter,
            height: _diameter,
            child: Icon(icon, color: SpotterfyTheme.text, size: _glyph),
          ),
        ),
      ),
    );
  }
}

/// Seek bar, elapsed/total labels, and nothing else.
///
/// Its own widget so the ~5x/second position ticks only repaint this strip
/// instead of the entire now-playing page - the animated backdrop, the cover
/// carousel and the control cluster were all rebuilding with it.
class _SeekSection extends StatelessWidget {
  final Duration duration;
  final bool isRadio;

  const _SeekSection({required this.duration, required this.isRadio});

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerProvider>();
    final dur = duration;
    return Column(
      children: [
        ValueListenableBuilder<Duration>(
          valueListenable: player.positionNotifier,
          builder: (context, pos, _) {
            return ValueListenableBuilder<Duration>(
              valueListenable: player.bufferedNotifier,
              builder: (context, buffered, _) {
                final progress = dur.inMilliseconds > 0
                    ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                    : 0.0;
                final bufferedFrac = dur.inMilliseconds > 0
                    ? (buffered.inMilliseconds / dur.inMilliseconds).clamp(
                        0.0,
                        1.0,
                      )
                    : 0.0;
                return _SeekBar(
                  progress: progress,
                  buffered: bufferedFrac,
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
                );
              },
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ValueListenableBuilder<Duration>(
                valueListenable: player.positionNotifier,
                builder: (context, pos, _) => Text(
                  _fmtDuration(pos),
                  style: TextStyle(
                    color: SpotterfyTheme.muted,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Text(
                _fmtDuration(dur),
                style: TextStyle(
                  color: SpotterfyTheme.muted,
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
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
                              color: SpotterfyTheme.overlay(0.35),
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
            Icon(Icons.music_note, color: SpotterfyTheme.muted, size: 64),
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
    return Icon(Icons.music_note, color: SpotterfyTheme.muted, size: 64);
  }
}
