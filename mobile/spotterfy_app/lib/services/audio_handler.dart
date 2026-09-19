import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import '../models/track_model.dart';

SpotterfyAudioHandler? audioHandler;
Completer<SpotterfyAudioHandler?>? _initCompleter;

// Callbacks wired from PlayerProvider so notification buttons actually control playback
Future<void> Function()? _onPlay;
Future<void> Function()? _onPause;
Future<void> Function()? _onSkipNext;
Future<void> Function()? _onSkipPrev;
Future<void> Function(Duration)? _onSeek;

void bindAudioHandlerCallbacks({
  Future<void> Function()? onPlay,
  Future<void> Function()? onPause,
  Future<void> Function()? onSkipNext,
  Future<void> Function()? onSkipPrev,
  Future<void> Function(Duration)? onSeek,
}) {
  _onPlay = onPlay;
  _onPause = onPause;
  _onSkipNext = onSkipNext;
  _onSkipPrev = onSkipPrev;
  _onSeek = onSeek;
}

bool _isRadioTrack(TrackModel t) {
  final u = t.sourceUrl.toLowerCase();
  return t.id.startsWith('radio_') ||
      u.contains('icecast.vrtcdn.be') ||
      u.contains('qmusic.be') ||
      u.contains('joe.be') ||
      u.contains('streamtheworld.com');
}

Future<void> ensureAudioHandler() async {
  if (audioHandler != null) return;
  if (_initCompleter != null) {
    await _initCompleter!.future;
    if (audioHandler != null) return;
    // Previous attempt failed — fall through to retry
  }
  _initCompleter = Completer<SpotterfyAudioHandler?>();
  // Retry up to 3 times with increasing delay — the Activity may not be ready
  // on the first attempt (e.g., when PlayerProvider constructor fires early)
  for (int attempt = 0; attempt < 3; attempt++) {
    try {
      if (attempt > 0) {
        debugPrint('[AudioService] retry attempt $attempt...');
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
      debugPrint('[AudioService] init start...');
      final handler = await AudioService.init(
        builder: () => SpotterfyAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.scooby.spotterfy.channel.audio',
          androidNotificationChannelName: 'Spotterfy Playback',
          androidNotificationChannelDescription: 'Music playback controls',
          androidStopForegroundOnPause: false,
          androidShowNotificationBadge: true,
          androidNotificationOngoing: false,
          // MUST be monochrome drawable with alpha - mipmap adaptive icon fails on Android 13+/16
          androidNotificationIcon: 'drawable/ic_notification',
        ),
      );
      audioHandler = handler;
      _initCompleter!.complete(handler);
      debugPrint('[AudioService] init ok handler=$audioHandler');
      return;
    } catch (e, st) {
      debugPrint('[AudioService] init attempt $attempt failed: $e\n$st');
    }
  }
  // All retries failed — reset so future calls can try again
  _initCompleter!.complete(null);
  _initCompleter = null;
  debugPrint('[AudioService] all init attempts failed');
}

class SpotterfyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  List<TrackModel> _tracks = [];
  int _index = -1;
  // used by PlayerProvider seek bridging
  Future<void> Function(Duration)? onSeekRequested;

  // Noize-style throttled broadcast (avoid spam on position ticks)
  Timer? _throttleTimer;
  bool _stateDirty = false;
  Duration _position = Duration.zero;
  Duration _buffered = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;

  SpotterfyAudioHandler() {
    _initSession();
    // Broadcast an initial idle state so Android's MediaSession is aware of this session
    playbackState.add(PlaybackState(
      controls: [MediaControl.play],
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
      androidCompactActionIndices: const [0],
      processingState: AudioProcessingState.idle,
      playing: false,
      updatePosition: Duration.zero,
      bufferedPosition: Duration.zero,
      speed: 1.0,
    ));
    _throttleTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (_stateDirty) {
        _stateDirty = false;
        _doBroadcast();
      }
    });
  }

  Future<void> _initSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {}
  }

  MediaItem _toMediaItem(TrackModel t) => MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artists,
        album: t.album.isNotEmpty ? t.album : 'Spotterfy',
        artUri: t.cover.isNotEmpty ? Uri.tryParse(t.cover) : null,
        duration: t.durationMs > 0 ? Duration(milliseconds: t.durationMs) : null,
      );

  void setQueue(List<TrackModel> tracks, {int startIndex = 0}) {
    _tracks = List.from(tracks);
    _index = startIndex.clamp(0, _tracks.length - 1);
    queue.add(_tracks.map(_toMediaItem).toList());
    if (_tracks.isNotEmpty) {
      mediaItem.add(_toMediaItem(_tracks[_index]).copyWith(duration: _duration));
    }
    _markDirty();
  }

  Future<void> updateTrack(TrackModel track, {List<TrackModel>? queue, required Duration position, Duration? duration, required bool isPlaying}) async {
    _position = position;
    _isPlaying = isPlaying;
    if (duration != null) _duration = duration;
    if (queue != null) {
      _tracks = List.from(queue);
      _index = _tracks.indexWhere((e) => e.id == track.id);
      if (_index == -1) _index = 0;
      this.queue.add(_tracks.map(_toMediaItem).toList());
    }
    final item = _toMediaItem(track);
    mediaItem.add(item.copyWith(duration: _duration != Duration.zero ? _duration : item.duration));
    _markDirty(force: true);
  }

  void _markDirty({bool force = false}) {
    _stateDirty = true;
    if (force) _doBroadcast();
  }

  void _doBroadcast() {
    final isRadio = _tracks.isNotEmpty && _index >= 0 && _isRadioTrack(_tracks[_index]);
    // Radio: no next/prev, only play/pause and seek back (system seek)
    if (isRadio) {
      playbackState.add(PlaybackState(
        controls: [_isPlaying ? MediaControl.pause : MediaControl.play],
        systemActions: const {MediaAction.seek, MediaAction.seekBackward},
        androidCompactActionIndices: const [0],
        processingState: AudioProcessingState.ready,
        playing: _isPlaying,
        updatePosition: _position,
        bufferedPosition: _buffered,
        speed: 1.0,
        queueIndex: _index >= 0 ? _index : null,
      ));
      return;
    }
    final hasPrev = _index > 0;
    final hasNext = _index + 1 < _tracks.length;
    final controls = <MediaControl>[
      if (hasPrev) MediaControl.skipToPrevious,
      _isPlaying ? MediaControl.pause : MediaControl.play,
      if (hasNext) MediaControl.skipToNext,
    ];
    final prevIdx = controls.indexOf(MediaControl.skipToPrevious);
    final playIdx = controls.indexWhere((c) => c == MediaControl.pause || c == MediaControl.play);
    final nextIdx = controls.indexOf(MediaControl.skipToNext);
    playbackState.add(PlaybackState(
      controls: controls,
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
      androidCompactActionIndices: [
        if (prevIdx != -1) prevIdx,
        if (playIdx != -1) playIdx,
        if (nextIdx != -1) nextIdx,
      ],
      processingState: AudioProcessingState.ready,
      playing: _isPlaying,
      updatePosition: _position,
      bufferedPosition: _buffered,
      speed: 1.0,
      queueIndex: _index >= 0 ? _index : null,
    ));
  }

  void updatePosition(Duration pos, Duration dur, bool isPlaying) {
    _position = pos;
    _isPlaying = isPlaying;
    if (dur != Duration.zero) _duration = dur;
    final item = mediaItem.value;
    if (item != null && dur != Duration.zero && item.duration != dur) {
      mediaItem.add(item.copyWith(duration: dur));
    }
    _markDirty();
  }

  void updateBuffered(Duration buffered) {
    _buffered = buffered;
    _markDirty();
  }

  @override
  Future<void> seek(Duration position) async {
    // Noize bridges seek → PlayerProvider via callback
    if (_onSeek != null) {
      await _onSeek!(position);
    } else if (onSeekRequested != null) {
      await onSeekRequested!(position);
    }
    _position = position;
    _markDirty(force: true);
  }

  @override
  Future<void> play() async {
    if (_onPlay != null) await _onPlay!();
    _isPlaying = true;
    _markDirty(force: true);
  }

  @override
  Future<void> pause() async {
    if (_onPause != null) await _onPause!();
    _isPlaying = false;
    _markDirty(force: true);
  }

  @override
  Future<void> stop() async {
    _isPlaying = false;
    _markDirty(force: true);
  }

  @override
  Future<void> skipToNext() async {
    if (_onSkipNext != null) {
      await _onSkipNext!();
      return;
    }
    if (_index + 1 < _tracks.length) {
      _index++;
      mediaItem.add(_toMediaItem(_tracks[_index]).copyWith(duration: _duration));
      _markDirty(force: true);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_onSkipPrev != null) {
      await _onSkipPrev!();
      return;
    }
    if (_index > 0) {
      _index--;
      mediaItem.add(_toMediaItem(_tracks[_index]).copyWith(duration: _duration));
      _markDirty(force: true);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    _index = index;
    mediaItem.add(_toMediaItem(_tracks[_index]).copyWith(duration: _duration));
    _markDirty(force: true);
    // actual playback started via PlayerProvider.playFromQueue bridge if bound
  }

  void disposeHandler() {
    _throttleTimer?.cancel();
  }
}
