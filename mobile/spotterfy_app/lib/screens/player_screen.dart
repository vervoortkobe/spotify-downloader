import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:spotterfy_app/widgets/storage_cover.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/providers/player_provider.dart';
import 'package:spotterfy_app/theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

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
      // Opaque here because the animated gradient paints the whole screen.
      backgroundColor: const Color(0xFF04120C),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Colors.white,
            size: 30,
          ),
          tooltip: 'Minimise',
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!isRadio)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: SpotterfyTheme.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: SpotterfyTheme.primary.withValues(alpha: 0.4),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(
                    Icons.queue_music_rounded,
                    color: Colors.black,
                    size: 20,
                  ),
                  tooltip: 'Queue',
                  onPressed: () => _showQueueDialog(context, player, track),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          // Slowly drifting green glows behind everything.
          const Positioned.fill(child: _AnimatedGreenBackdrop()),
          GestureDetector(
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) > 400) {
                HapticFeedback.lightImpact();
                Navigator.pop(context);
              }
            },
            onHorizontalDragEnd: (d) {
              if (isRadio) return;
              final v = d.primaryVelocity ?? 0;
              if (v < -500) {
                HapticFeedback.lightImpact();
                player.next();
              } else if (v > 500) {
                HapticFeedback.lightImpact();
                player.previous();
              }
            },
            onDoubleTap: () {
              HapticFeedback.mediumImpact();
              player.togglePlayPause();
            },
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 20),
                child: Column(
                  children: [
                    // drag handle
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const Spacer(flex: 3),
                    if (!isRadio && queue.length > 1)
                      _CoverCarousel(
                        key: ValueKey(
                          'carousel-${queue.length}-${queue.first.id}-${queue.last.id}',
                        ),
                        tracks: queue,
                        currentIndex: currentIndex,
                        onPageSelected: (i) {
                          if (i != player.currentIndex) player.playFromQueue(i);
                        },
                      )
                    else
                      _StaticCover(track: track),
                    const Spacer(flex: 3),
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
                            ? Text(
                                '${currentIndex + 1} / ${player.queue.length} in queue',
                                style: const TextStyle(
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
        ],
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

/// Slowly drifting green gradient glows. Loops forever but paints only three
/// radial gradients, and is wrapped in a RepaintBoundary so the animation
/// doesn't dirty the rest of the player UI each frame.
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
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(
                  -0.6 + 0.35 * math.sin(t),
                  -0.7 + 0.18 * math.cos(t),
                ),
                radius: 1.25,
                colors: [
                  SpotterfyTheme.primary.withValues(
                    alpha: 0.30 + 0.06 * math.sin(t),
                  ),
                  SpotterfyTheme.primary.withValues(alpha: 0.0),
                ],
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(
                    0.7 + 0.30 * math.cos(t * 0.8),
                    0.35 + 0.22 * math.sin(t * 0.7),
                  ),
                  radius: 1.15,
                  colors: [
                    SpotterfyTheme.primaryDark.withValues(
                      alpha: 0.22 + 0.05 * math.cos(t * 1.2),
                    ),
                    SpotterfyTheme.primaryDark.withValues(alpha: 0.0),
                  ],
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.45),
                      Colors.black.withValues(alpha: 0.0),
                      Colors.black.withValues(alpha: 0.35),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),
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

/// Single (non-carousel) cover, centred in a square.
class _StaticCover extends StatelessWidget {
  final TrackModel track;
  const _StaticCover({required this.track});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 280,
        height: 280,
        color: SpotterfyTheme.surface,
        child: _PlayerCover(track: track),
      ),
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

class _CoverCarouselState extends State<_CoverCarousel>
    with SingleTickerProviderStateMixin {
  late PageController _ctrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.currentIndex.clamp(0, widget.tracks.length - 1);
    _ctrl = PageController(viewportFraction: 0.76, initialPage: _current);
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
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      child: PageView.builder(
        controller: _ctrl,
        itemCount: widget.tracks.length,
        onPageChanged: (i) {
          if (i == _current) return;
          _current = i;
          HapticFeedback.selectionClick();
          widget.onPageSelected(i);
        },
        itemBuilder: (_, i) {
          final t = widget.tracks[i];
          return Padding(
            // Wider gap + slight inset so neighbouring covers never touch.
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                color: SpotterfyTheme.surface,
                child: _PlayerCover(track: t),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CircleControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
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
        color: Colors.white.withValues(alpha: 0.12),
        shape: CircleBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, color: Colors.white, size: 26),
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
      behavior: HitTestBehavior.opaque,
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
