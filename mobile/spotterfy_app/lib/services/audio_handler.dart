import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart' show BehaviorSubject;
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:rxdart/rxdart.dart' show ValueStream;
import '../models/track_model.dart';
import 'auto_media_library.dart';

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

/// Broadcast channel backing `subscribeToChildren`.
///
/// Android Auto keeps the browse tree open and re-reads it whenever this emits,
/// so one subject is shared across every parent id rather than handing back a
/// fresh stream per subscription.
class _ChildrenSubscription {
  String? parent;

  final _subject = BehaviorSubject<Map<String, dynamic>>.seeded(const {
    'subscribed': true,
  });

  ValueStream<Map<String, dynamic>> get stream => _subject.stream;

  void notifyChanged() {
    if (_subject.isClosed) return;
    // A distinct map identity each time, so audio_service forwards it rather
    // than treating it as a duplicate of the seed value.
    _subject.add({
      'subscribed': true,
      'ts': DateTime.now().microsecondsSinceEpoch,
    });
  }

  Future<void> cancel() => _subject.close();
}

bool _initAttempted = false;

Future<void> ensureAudioHandler() async {
  if (audioHandler != null) return;
  if (_initCompleter != null) {
    await _initCompleter!.future;
    return;
  }
  // AudioService.init() can only be called once per process — a second call
  // always throws '_cacheManager == null'. So never retry in the same
  // process; just_audio playback already works without the notification.
  if (_initAttempted) {
    debugPrint('[AudioService] already attempted, skipping re-init');
    return;
  }
  _initAttempted = true;
  _initCompleter = Completer<SpotterfyAudioHandler?>();
  try {
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
  } catch (e, st) {
    debugPrint(
      '[AudioService] init failed (notification disabled, playback continues): $e\n$st',
    );
    _initCompleter!.complete(null);
    _initCompleter = null;
  }
}

class SpotterfyAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  List<TrackModel> _tracks = [];
  int _index = -1;
  // used by PlayerProvider seek bridging
  Future<void> Function(Duration)? onSeekRequested;

  late final _ChildrenSubscription _subscription = _ChildrenSubscription();

  // Noize-style throttled broadcast (avoid spam on position ticks)
  Timer? _throttleTimer;
  bool _stateDirty = false;
  Duration _position = Duration.zero;
  Duration _buffered = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;

  SpotterfyAudioHandler() {
    _initSession();
    // Push updates into an open Android Auto browse tree.
    AutoLibraryBridge.addLibraryListener(_onLibraryChanged);
    // Broadcast an initial idle state so Android's MediaSession is aware of this session
    playbackState.add(
      PlaybackState(
        controls: [MediaControl.play],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0],
        processingState: AudioProcessingState.idle,
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: 1.0,
      ),
    );
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

  MediaItem _toMediaItem(TrackModel t) =>
      AutoLibraryBridge.instance.trackItemSync(t);

  void setQueue(List<TrackModel> tracks, {int startIndex = 0}) {
    _tracks = List.from(tracks);
    _index = startIndex.clamp(0, _tracks.length - 1);
    queue.add(_tracks.map(_toMediaItem).toList());
    if (_tracks.isNotEmpty) {
      mediaItem.add(
        _toMediaItem(_tracks[_index]).copyWith(duration: _duration),
      );
    }
    AutoLibraryBridge.instance.updatePlaybackState(
      _tracks,
      _index >= 0 ? _tracks[_index] : null,
    );
    _markDirty();
    // Artwork/durations for storage tracks need disk reads; publish again once
    // resolved so Android Auto shows real lengths and covers.
    _enrichQueue();
    // Resolve the *playing* track's art on its own, without waiting for the
    // whole queue. Storage tracks have no cover URL, so the notification and the
    // Android Auto now-playing view get their picture from embedded ID3 art -
    // and reading that for a few hundred queued files before publishing the
    // current one left the cover blank for seconds.
    _publishCurrentArt();
  }

  /// Publishes the now-playing item again, this time with artwork resolved.
  ///
  /// Only ever touches `mediaItem`, never the queue, so it cannot clobber a
  /// newer queue, and it re-reads [_index] at call time so a track change that
  /// landed meanwhile wins.
  Future<void> _publishCurrentArt() async {
    if (_tracks.isEmpty) return;
    final generation = _queueGeneration;
    final idx = _index;
    if (idx < 0 || idx >= _tracks.length) return;
    final track = _tracks[idx];
    final art = await AutoLibraryBridge.resolveArtUri(track);
    // A newer setQueue() or track change happened while the art was being read.
    if (generation != _queueGeneration || _index != idx) return;
    if (art == null) return;
    final current = mediaItem.valueOrNull;
    if (current != null && current.artUri == art) return;
    mediaItem.add(
      _toMediaItem(track).copyWith(
        artUri: art,
        duration: _duration != Duration.zero
            ? _duration
            : (await AutoLibraryBridge.resolveDuration(track)),
      ),
    );
  }

  /// Bumped whenever the queue changes so a slow enrichment pass can detect that
  /// it is stale and bail out instead of clobbering a newer queue.
  int _queueGeneration = 0;

  Future<void> _enrichQueue() async {
    final generation = ++_queueGeneration;
    final tracks = List<TrackModel>.from(_tracks);
    if (tracks.isEmpty) return;
    final items = <MediaItem>[];
    for (final t in tracks) {
      items.add(
        AutoLibraryBridge.instance
            .trackItemSync(t)
            .copyWith(
              duration:
                  await AutoLibraryBridge.resolveDuration(t) ??
                  (t.durationMs > 0
                      ? Duration(milliseconds: t.durationMs)
                      : null),
              artUri: await AutoLibraryBridge.resolveArtUri(t),
            ),
      );
    }
    // The queue changed (or the screen went away) while we were reading files.
    if (generation != _queueGeneration) return;
    queue.add(items);
    if (_index >= 0 && _index < _tracks.length) {
      mediaItem.add(
        items[_index].copyWith(
          duration: _duration != Duration.zero
              ? _duration
              : items[_index].duration,
        ),
      );
    }
  }

  // --- Android Auto browse tree ------------------------------------------

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) => AutoLibraryBridge.instance.getChildren(parentMediaId);

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) => AutoLibraryBridge.instance.playFromMediaId(mediaId);

  @override
  Future<void> playFromSearch(String query, [Map<String, dynamic>? extras]) =>
      AutoLibraryBridge.instance.playFromSearch(query);

  @override
  ValueStream<Map<String, dynamic>> subscribeToChildren(String parentMediaId) {
    // Android Auto holds the browse tree open and expects to be told when its
    // contents change. Without this it keeps rendering whatever the first
    // response was - which, if the library was still loading at that moment,
    // is an empty list that never recovers.
    _subscription.parent = parentMediaId;
    return _subscription.stream;
  }

  void _onLibraryChanged() {
    _subscription.notifyChanged();
    // Re-publish the now-playing art too: a storage track that had no cover
    // when the car first connected can gain one once art extraction lands.
    _publishCurrentArt();
  }

  Future<void> updateTrack(
    TrackModel track, {
    List<TrackModel>? queue,
    required Duration position,
    Duration? duration,
    required bool isPlaying,
  }) async {
    _position = position;
    _isPlaying = isPlaying;
    if (duration != null) _duration = duration;
    if (queue != null) {
      _tracks = List.from(queue);
      _index = _tracks.indexWhere((e) => e.id == track.id);
      if (_index == -1) _index = 0;
      this.queue.add(_tracks.map(_toMediaItem).toList());
    }
    AutoLibraryBridge.instance.updatePlaybackState(_tracks, track);
    final item = _toMediaItem(track);
    mediaItem.add(
      item.copyWith(
        duration: _duration != Duration.zero ? _duration : item.duration,
      ),
    );
    _markDirty(force: true);
    // Storage tracks start with no artwork, so the first mediaItem has none.
    // Resolve it now; otherwise the cover only appears after some later
    // queue-wide enrichment pass happens to come back around.
    _publishCurrentArt();
  }

  void _markDirty({bool force = false}) {
    _stateDirty = true;
    if (force) _doBroadcast();
  }

  void _doBroadcast() {
    final isRadio =
        _tracks.isNotEmpty && _index >= 0 && _isRadioTrack(_tracks[_index]);
    // Radio: no next/prev, only play/pause and seek back (system seek)
    if (isRadio) {
      playbackState.add(
        PlaybackState(
          controls: [_isPlaying ? MediaControl.pause : MediaControl.play],
          systemActions: const {MediaAction.seek, MediaAction.seekBackward},
          androidCompactActionIndices: const [0],
          processingState: AudioProcessingState.ready,
          playing: _isPlaying,
          updatePosition: _position,
          bufferedPosition: _buffered,
          speed: 1.0,
          queueIndex: _index >= 0 ? _index : null,
        ),
      );
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
    final playIdx = controls.indexWhere(
      (c) => c == MediaControl.pause || c == MediaControl.play,
    );
    final nextIdx = controls.indexOf(MediaControl.skipToNext);
    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
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
      ),
    );
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
      mediaItem.add(
        _toMediaItem(_tracks[_index]).copyWith(duration: _duration),
      );
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
      mediaItem.add(
        _toMediaItem(_tracks[_index]).copyWith(duration: _duration),
      );
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
