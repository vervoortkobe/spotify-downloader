import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart' as perm;
import 'package:spotterfy_app/models/track_model.dart';
import 'package:spotterfy_app/services/api_service.dart';
import 'package:spotterfy_app/services/audio_handler.dart';
import 'package:spotterfy_app/services/auto_media_library.dart';
import 'package:spotterfy_app/services/download_service.dart';
import 'package:spotterfy_app/providers/equalizer_provider.dart';
import 'package:spotterfy_app/providers/playback_settings_controller.dart';

class PlayerProvider extends ChangeNotifier {
  // just_audio player with the shared EQ pipeline (equalizer + loudness).
  // Audio focus/session config lives in SpotterfyAudioHandler._initSession.
  // Not final: a crossfade swaps in a secondary player once the incoming
  // track has fully faded in (see [_finishCrossfade]).
  late AudioPlayer _player;
  TrackModel? _currentTrack;
  List<TrackModel> _queue = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  bool _completed = false;
  Duration _position = Duration.zero;

  /// Whether playback was running when the app last exited. Only used to decide
  /// whether restoring into the media session is worth a resume hint - never to
  /// start audio by itself.
  bool _wasPlayingBeforeRestart = false;

  /// The in-flight restore of the persisted session. [_restoreForAuto] awaits
  /// it so the queue/track are on disk-backed state before they are published
  /// to the media session.
  Future<void>? _stateLoadFuture;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;

  TrackModel? get currentTrack => _currentTrack;
  List<TrackModel> get queue => _queue;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;

  /// Playhead, ticking several times a second while playing.
  ///
  /// Deliberately a separate Listenable rather than part of [notifyListeners].
  /// Position was by far the loudest source of rebuilds in the app: every
  /// `watch<PlayerProvider>()` in a long list re-ran its itemBuilder on every
  /// tick, so a playing track rebuilt whole screens ~5x/second for the sake of
  /// two progress bars. Only the bars listen to this now.
  final ValueNotifier<Duration> positionNotifier = ValueNotifier(Duration.zero);

  /// Buffered position, same deal as [positionNotifier].
  final ValueNotifier<Duration> bufferedNotifier = ValueNotifier(Duration.zero);

  /// Track length. Changes about once per song rather than per tick, so it stays
  /// on the main notifier - but is separate so the progress bars can rebuild on
  /// a length change without a position tick.
  final ValueNotifier<Duration> durationNotifier = ValueNotifier(Duration.zero);

  Duration get position => _position;
  Duration get duration => _duration;
  Duration get buffered => _buffered;
  bool get hasQueue => _queue.isNotEmpty;
  bool get hasNext => _queue.isNotEmpty && _currentIndex < _queue.length - 1;
  bool get hasPrevious => _queue.isNotEmpty && _currentIndex > 0;

  bool _isRadioUrl(String url) {
    final u = url.toLowerCase();
    return u.contains('icecast.vrtcdn.be') ||
        u.contains('qmusic.be') ||
        u.contains('joe.be') ||
        u.contains('streamtheworld.com');
  }

  bool get isRadio =>
      _currentTrack != null &&
      (_currentTrack!.id.startsWith('radio_') ||
          _isRadioUrl(_currentTrack!.sourceUrl));
  Duration _radioMaxListened = Duration.zero;
  Timer? _radioDriftTimer;

  Duration get radioMaxListened => _radioMaxListened;

  // Single unified queue: library, radio and on-device storage tracks share one queue,
  // so storage songs can be queued/mixed with anything else.
  bool _isLocalPath(String p) => p.startsWith('/') || p.startsWith('file://');

  PlayerProvider() {
    _player = AudioPlayer(
      audioPipeline: AudioPipeline(
        androidAudioEffects: [androidEqualizer, androidLoudnessEnhancer],
      ),
    );
    _stateLoadFuture = _loadPlayerState();
    _requestNotificationPermission();
    // Android Auto connects to the media browser service without ever opening
    // the app, so nothing else would restore the previous session into the
    // media session and the car would show an empty player.
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreForAuto());
    // Let Android Auto start playback from rows it browses.
    AutoLibraryBridge.instance.bindPlayback((tracks, index) async {
      setQueue(tracks, startIndex: index);
      await play(tracks[index], queue: tracks);
    });
    // NOTE: do NOT init AudioService here. The constructor runs before
    // MainActivity is attached, which burns our single AudioService.init()
    // attempt (it can only be called once per process). Init lazily on
    // first play() instead, when the Activity is guaranteed ready.
    _bindPlayerStreams(_player);
  }

  // Stream subscriptions for the current primary player. Held so they can be
  // cancelled and re-pointed when a crossfade swaps the primary player.
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<Duration>? _bufSub;
  StreamSubscription<PlayerState>? _stateSub;

  /// Subscribes the provider's streams to [player].
  ///
  /// Called once in the constructor and again after a crossfade swaps the
  /// primary player, so position/duration/state events always follow
  /// whichever player [_player] currently owns. Re-binding cancels the
  /// previous subscriptions, which also detaches the outgoing player's
  /// listeners so its late "completed" event can't double-skip.
  void _bindPlayerStreams(AudioPlayer player) {
    _posSub?.cancel();
    _durSub?.cancel();
    _bufSub?.cancel();
    _stateSub?.cancel();
    _posSub = player.positionStream.listen((pos) {
      _position = pos;
      if (isRadio && _isPlaying) {
        if (pos > _radioMaxListened) _radioMaxListened = pos;
      }
      audioHandler?.updatePosition(pos, _duration, _isPlaying);
      // Notifies only the progress bars. See [positionNotifier].
      positionNotifier.value = pos;
      _maybeStartCrossfade();
    });
    _durSub = player.durationStream.listen((dur) {
      // Live radio has no duration (null) - keep the previous value.
      if (dur == null) return;
      _duration = dur;
      durationNotifier.value = dur;
      // The real length is often the only place we ever learn it (scrapes and
      // local files can carry no duration), so write it back onto the track.
      // Everything downstream - mini player, queue rows, playlist lists - reads
      // `durationMs`, so this is what makes their lengths correct.
      final ms = dur.inMilliseconds;
      if (ms > 0) _applyDurationToTrack(ms);
      if (_currentTrack != null) {
        audioHandler?.updateTrack(
          _currentTrack!,
          queue: _queue,
          position: _position,
          duration: _duration,
          isPlaying: _isPlaying,
        );
      }
      notifyListeners();
    });
    _bufSub = player.bufferedPositionStream.listen((buf) {
      _buffered = buf;
      audioHandler?.updateBuffered(buf);
      notifyListeners();
    });
    _stateSub = player.playerStateStream.listen((state) {
      if (_crossfading) {
        // The outgoing track winding down under a crossfade: its state is no
        // longer the source of truth for the UI, and the crossfade owns the
        // transition, so its completion must not also skip.
        return;
      }
      _isPlaying = state.playing;
      _completed = state.processingState == ProcessingState.completed;
      if (_completed) {
        _onTrackCompleted();
        return;
      }
      _handleRadioDrift();
      audioHandler?.updatePosition(_position, _duration, _isPlaying);
      notifyListeners();
    });
  }

  /// Advances past a track that reached its end: the next queued track, or
  /// a stop at the end of the queue.
  void _onTrackCompleted() {
    if (_queue.isNotEmpty && _currentIndex < _queue.length - 1) {
      next();
    } else {
      _isPlaying = false;
      audioHandler?.updatePosition(_position, _duration, false);
    }
  }

  // --- crossfade ------------------------------------------------------

  /// Whether a crossfade is currently overlapping the outgoing and incoming
  /// track.
  bool _crossfading = false;

  /// The incoming track's player while [_crossfading] is true.
  AudioPlayer? _crossPlayer;

  /// Starts overlapping the next track over the last
  /// [PlaybackSettingsController.crossfadeSeconds] of the current one.
  ///
  /// Only for automatic transitions (a track playing out): a manual skip is
  /// instant by design, and pre-loading the next track on every track just to
  /// cover manual skips would double streaming bandwidth for everyone.
  void _maybeStartCrossfade() {
    if (_crossfading || isRadio) return;
    final seconds = PlaybackSettingsController.instance.crossfadeSeconds;
    if (seconds <= 0) return;
    if (!hasNext || _duration <= Duration.zero) return;
    final remaining = _duration - _position;
    if (remaining > Duration(seconds: seconds)) return;
    final nextTrack = _queue[_currentIndex + 1];
    _startCrossfade(nextTrack, Duration(seconds: seconds));
  }

  Future<void> _startCrossfade(TrackModel nextTrack, Duration fade) async {
    _crossfading = true;
    // The secondary player owns its own effect instances: an effect can only
    // be attached to one player at a time, so the primary's singletons can't
    // be shared. They're configured from the stored EQ state once this
    // player is active (see EqualizerProvider.applyTo).
    final crossEq = AndroidEqualizer();
    final crossLoudness = AndroidLoudnessEnhancer();
    final cross = AudioPlayer(
      audioPipeline: AudioPipeline(
        androidAudioEffects: [crossEq, crossLoudness],
      ),
    );
    _crossPlayer = cross;
    try {
      final loaded = await _loadInto(cross, nextTrack);
      if (!loaded) {
        // The outgoing track may already have ended while this one loaded.
        // Advance manually if so; otherwise it completes naturally.
        await _cancelCrossfade();
        if (_completed) _onTrackCompleted();
        return;
      }
      // The incoming track is playing now, so its effect instances can be
      // configured (parameters are only available once the player is active).
      await EqualizerProvider.current?.applyTo([crossEq, crossLoudness]);
      // Start the incoming track silently under the outgoing one, then ramp
      // the two volumes in opposite directions over the fade.
      await cross.setVolume(0);
      const step = Duration(milliseconds: 50);
      final steps =
          (fade.inMilliseconds / step.inMilliseconds).round().clamp(1, 10000);
      for (var i = 1; i <= steps; i++) {
        await Future.delayed(step);
        if (!_crossfading) return;
        final t = i / steps;
        await _player.setVolume(1 - t);
        await cross.setVolume(t);
        if (!_crossfading) {
          // Cancelled mid-ramp: restore the outgoing volume.
          await _player.setVolume(1);
          return;
        }
      }
      await _finishCrossfade(nextTrack, cross, [crossEq, crossLoudness]);
    } catch (e) {
      debugPrint('[Player] crossfade failed: $e');
      await _cancelCrossfade();
    }
  }

  /// Hands playback over to the crossfaded track: the outgoing player is
  /// stopped and disposed, the incoming one becomes [_player], and the
  /// provider's state moves onto the new track.
  Future<void> _finishCrossfade(
    TrackModel nextTrack,
    AudioPlayer cross,
    List<AndroidAudioEffect> crossEffects,
  ) async {
    _crossfading = false;
    _crossPlayer = null;
    // The queue may have been edited while the fade ran; only take over if
    // the crossfaded track is still the expected next one.
    if (_currentIndex + 1 >= _queue.length ||
        _queue[_currentIndex + 1].id != nextTrack.id) {
      await _cancelCrossfade();
      // The outgoing track may already have ended; advance if so.
      if (_completed) _onTrackCompleted();
      return;
    }
    final old = _player;
    _currentIndex++;
    _currentTrack = nextTrack;
    _position = Duration.zero;
    _duration = Duration.zero;
    _buffered = Duration.zero;
    _completed = false;
    _starting = false;
    _pauseRequested = false;
    _isPlaying = true;
    positionNotifier.value = Duration.zero;
    durationNotifier.value = Duration.zero;
    bufferedNotifier.value = Duration.zero;
    _player = cross;
    // Re-point the provider's streams at the new primary (this also detaches
    // the outgoing player's listeners).
    _bindPlayerStreams(_player);
    notifyListeners();
    // The outgoing track is fully faded out by now.
    await old.stop();
    await old.dispose();
    // EQ changes from here on target the new primary's effect instances.
    await EqualizerProvider.current?.bindEffects(crossEffects);
    final h = audioHandler;
    if (h != null) {
      await h.updateTrack(
        nextTrack,
        queue: _queue,
        position: Duration.zero,
        duration: Duration.zero,
        isPlaying: true,
      );
    }
    _prefetchNextSource();
    _savePlayerState();
  }

  /// Aborts an in-flight crossfade: the incoming player is disposed and the
  /// outgoing one keeps playing (its volume is restored by the fade loop's
  /// post-check, or was never touched).
  Future<void> _cancelCrossfade() async {
    final cross = _crossPlayer;
    _crossPlayer = null;
    _crossfading = false;
    if (cross != null) {
      await cross.stop();
      await cross.dispose();
    }
  }

  /// Writes a learned track length back onto the current track and its queue
  /// entry, so every view that renders `durationMs` shows the real value
  /// instead of 0:00 / a blank.
  void _applyDurationToTrack(int ms) {
    final current = _currentTrack;
    if (current == null) return;
    if (current.durationMs == ms) return;
    final updated = current.copyWith(durationMs: ms);
    _currentTrack = updated;
    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      final queued = _queue[_currentIndex];
      if (queued.durationMs != ms) {
        _queue[_currentIndex] = updated;
      }
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      // POST_NOTIFICATIONS is Android 13+ (33) only - on 11/12 it's auto-granted
      // permission_handler returns granted on <33, so gate to avoid prompt spam on 11
      if (await perm.Permission.notification.status.isGranted) return;
      // Only request on 33+ where runtime prompt exists; on 11/12 the channel still shows without prompt
      final s = await perm.Permission.notification.status;
      if (s.isDenied || s.isPermanentlyDenied) {
        await perm.Permission.notification.request();
      }
    } catch (_) {}
  }

  void _bindHandler() {
    bindAudioHandlerCallbacks(
      onPlay: () async => await resume(),
      onPause: () async => await pause(),
      onSkipNext: () async => await next(),
      onSkipPrev: () async => await previous(),
      onSeek: (pos) async => await seekTo(pos),
    );
    final h = audioHandler;
    if (h != null) h.onSeekRequested = (pos) async => await seekTo(pos);
  }

  void _handleRadioDrift() {
    _radioDriftTimer?.cancel();
    _radioDriftTimer = null;
    if (!isRadio) return;
    if (!_isPlaying) {
      // When radio paused, progress drifts left (fall behind live) at 1x speed
      _radioDriftTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_position.inMilliseconds > 0) {
          _position = Duration(milliseconds: _position.inMilliseconds - 1000);
          if (_position.isNegative) _position = Duration.zero;
          audioHandler?.updatePosition(_position, _duration, false);
          positionNotifier.value = _position;
        } else {
          _radioDriftTimer?.cancel();
        }
      });
    }
  }

  Future<void> play(TrackModel track, {List<TrackModel>? queue}) async {
    await _cancelCrossfade();
    if (queue != null) {
      _queue = List.from(queue);
      _currentIndex = queue.indexWhere((e) => e.id == track.id);
      if (_currentIndex == -1) _currentIndex = 0;
    } else if (_queue.isEmpty) {
      _queue = [track];
      _currentIndex = 0;
    } else {
      final idx = _queue.indexWhere((e) => e.id == track.id);
      if (idx >= 0) {
        _currentIndex = idx;
      } else {
        _queue.add(track);
        _currentIndex = _queue.length - 1;
      }
    }
    _currentTrack = track;
    _position = Duration.zero;
    _duration = Duration.zero;
    _buffered = Duration.zero;
    positionNotifier.value = Duration.zero;
    durationNotifier.value = Duration.zero;
    bufferedNotifier.value = Duration.zero;
    if (isRadio) _radioMaxListened = Duration.zero;
    // A track is loading from here until playback actually begins. During this
    // window both `_isPlaying` and `_player.playing` are false, so a pause tap
    // used to be read as "not playing", turned into a play command, and then
    // silently overwritten when the load finished - which is why pressing pause
    // during a slow load appeared to do nothing.
    _starting = true;
    _pauseRequested = false;
    _handleRadioDrift();
    notifyListeners();
    await ensureAudioHandler();
    _bindHandler();
    final h = audioHandler;
    if (h != null) {
      await h.updateTrack(
        track,
        queue: _queue,
        position: Duration.zero,
        duration: Duration.zero,
        isPlaying: true,
      );
      h.onSeekRequested = (pos) async => await seekTo(pos);
    } else {
      debugPrint('[Player] audioHandler is null — notification will not show');
    }
    final loaded = await _loadInto(_player, track);
    if (!loaded) {
      // Every source failed: don't leave the UI showing a track that isn't
      // audible. `_onTrackStarted` is skipped so `_isPlaying` stays false.
      _starting = false;
      _savePlayerState();
      return;
    }
    await _onTrackStarted();
    _starting = false;
    _savePlayerState();
  }

  /// Loads [track] into [player] and starts it.
  ///
  /// Shared by [play] and the crossfade, which preloads the next track into a
  /// second player so the two can overlap. Returns true once a source is
  /// loaded and playing; false if every source failed (a crossfade then falls
  /// back to a normal track change when the current one completes).
  Future<bool> _loadInto(
    AudioPlayer player,
    TrackModel track, {
    Duration startAt = Duration.zero,
  }) async {
    // Local storage files: play directly from device, no backend
    if (_isLocalPath(track.sourceUrl)) {
      final path = track.sourceUrl.replaceFirst('file://', '');
      try {
        await player
            .setFilePath(path, initialPosition: startAt)
            .timeout(const Duration(seconds: 30));
        await _playUntilAudibleOn(player);
        return true;
      } catch (e) {
        debugPrint('[Player] local file failed: $e');
        return false;
      }
    }

    // A track downloaded from inside the app is played from disk, so it starts
    // instantly and costs no bandwidth. Falls through to streaming when the
    // file is absent or unreadable.
    final downloaded = await _downloadedPathFor(track);
    if (downloaded != null) {
      try {
        await player
            .setFilePath(downloaded, initialPosition: startAt)
            .timeout(const Duration(seconds: 30));
        await _playUntilAudibleOn(player);
        return true;
      } catch (e) {
        debugPrint('[Player] downloaded file failed, streaming instead: $e');
      }
    }
    // Radio live streams (icecast etc) play directly, not via backend proxy
    final primary = track.sourceUrl.isNotEmpty
        ? (isDirectRadioUrl(track.sourceUrl) || track.id.startsWith('radio_')
              ? track.sourceUrl
              : ApiService.streamTrackUrl(track.sourceUrl))
        : null;
    final fallback = ApiService.streamTrackUrl(
      'ytsearch1:${track.title} ${track.artists} audio',
    );

    // No pre-flight HEAD request here on purpose. `setAudioSource` performs the
    // real request anyway, and doing a throwaway HEAD first just added a full
    // extra round-trip *in front of* it on every single track. The next track is
    // primed in the background instead (see [_prefetchNextSource]), so by the
    // time it is needed the server-side extraction is already cached.
    try {
      final url = primary ?? fallback;
      // No explicit `stop()`: `setAudioSource` stops the current source itself,
      // so calling it first was a wasted platform round-trip per track.
      await player
          .setAudioSource(
            AudioSource.uri(Uri.parse(url)),
            initialPosition: startAt,
          )
          .timeout(const Duration(seconds: 30));
      await _playUntilAudibleOn(player);
      return true;
    } catch (e) {
      debugPrint('[Player] primary failed: $e');
      try {
        await player
            .setAudioSource(
              AudioSource.uri(Uri.parse(fallback)),
              initialPosition: startAt,
            )
            .timeout(const Duration(seconds: 35));
        await _playUntilAudibleOn(player);
        return true;
      } catch (e2) {
        debugPrint('[Player] fallback failed: $e2');
      }
    }
    return false;
  }

  /// Warms the server-side extraction for the *next* queue track.
  ///
  /// The backend caches the resolved audio URL, so touching it early means the
  /// next track skips the slow yt-dlp resolution and starts almost immediately.
  /// Fire-and-forget: a failure here is harmless because the real load still
  /// falls back normally.
  ///
  /// Two tracks ahead are warmed, not one. Resolving a track can take seconds
  /// when the extraction is cold, and one ahead only covers the common case of
  /// listening straight through; prefetching the one after that covers skipping
  /// or letting a track finish early. Requests for the same URL collapse on the
  /// backend's single-flight lock, so the overlap costs nothing.
  void _prefetchNextSource() {
    if (isRadio) return;
    for (final ahead in [1, 2]) {
      final next = _currentIndex + ahead;
      if (next < 0 || next >= _queue.length) continue;
      final upcoming = _queue[next];
      // Local files and direct radio streams need no resolution.
      if (_isLocalPath(upcoming.sourceUrl)) continue;
      if (isDirectRadioUrl(upcoming.sourceUrl)) continue;
      final url = ApiService.streamTrackUrl(upcoming.sourceUrl);
      if (_prefetchedUrls.contains(url)) continue;
      _prefetchedUrls.add(url);
      // Sent right away rather than on a delay: the whole point is to have the
      // extraction finished before the track is needed, and the old 2s wait just
      // threw away the start of that window.
      Timer.run(() {
        try {
          http
              .head(Uri.parse(url))
              .timeout(const Duration(seconds: 8))
              .then((_) {}, onError: (_) {});
        } catch (_) {}
      });
    }
  }

  /// Stream URLs already warmed by [_prefetchNextSource], so repeatedly
  /// re-selecting the same track does not re-issue the request every time.
  final Set<String> _prefetchedUrls = {};

  /// Absolute path of the app-downloaded file for [track], if one exists.
  ///
  /// Looks the track up by id **and** by source URL: tracks can be re-imported
  /// or matched across playlists with different ids, and the download index is
  /// keyed on whichever id was used when it was saved.
  Future<String?> _downloadedPathFor(TrackModel track) async {
    try {
      await DownloadService.instance.ensureLoaded();
      final svc = DownloadService.instance;
      final candidates = <String>[track.id, track.sourceUrl];
      // Also try the id without a `yt_`-style prefix, and the URL without query.
      for (final c in candidates) {
        final p = svc.localPathFor(c);
        if (p != null && await File(p).exists()) return p;
      }
      for (final e in svc.entries.values) {
        if (track.sourceUrl.isNotEmpty && e.title == track.title) {
          final p = svc.localPathFor(e.trackId);
          if (p != null && await File(p).exists()) return p;
        }
      }
      return null;
    } catch (e) {
      debugPrint('[Player] download lookup failed: $e');
      return null;
    }
  }

  /// Marks a track as genuinely started.
  ///
  /// Honours a pause that was pressed while the track was still loading, so the
  /// page never starts playing something the user already cancelled.
  Future<void> _onTrackStarted() async {
    _completed = false;
    if (_pauseRequested) {
      _pauseRequested = false;
      _isPlaying = false;
      notifyListeners();
      await _player.pause();
      return;
    }
    _isPlaying = true;
    notifyListeners();
    // Get the following track resolving on the server while this one plays.
    _prefetchNextSource();
  }

  Future<void> _startPlayback() async {
    // just_audio resumes from the completed state otherwise - restart instead.
    if (_completed) {
      await _player.seek(Duration.zero);
      _completed = false;
    }
    // After an app restart the player owns no audio source - only the queue,
    // track and position were restored from disk - so the current track has
    // to be loaded before it can play. Without this, pressing play on a
    // restored session silently does nothing.
    if (_player.processingState == ProcessingState.idle) {
      final track = _currentTrack;
      if (track == null) return;
      await ensureAudioHandler();
      _bindHandler();
      _starting = true;
      final loaded = await _loadInto(_player, track, startAt: _position);
      _starting = false;
      if (loaded) await _onTrackStarted();
      return;
    }
    await _playUntilAudibleOn(_player);
  }

  /// Starts playback on [player] and returns once audio is actually running.
  ///
  /// Must never `await player.play()` directly. That future only completes when
  /// playback is *paused or stopped*, so awaiting it blocks here for the entire
  /// track. That was the root of "play takes ages" and "pause does nothing":
  /// [resume] held the caller open for the whole song, so the post-play state
  /// corrections never ran, and the toggle lock stayed held - every later pause
  /// tap just queued and was never applied.
  ///
  /// Waits on the playing state instead, with a ceiling so a stalled source
  /// still surfaces a TimeoutException for the caller's existing fallback.
  Future<void> _playUntilAudibleOn(AudioPlayer player) async {
    if (player.playing) return;
    // Nothing loaded at all: fail immediately rather than sitting out the whole
    // ceiling on a source that will never arrive.
    if (player.processingState == ProcessingState.idle) {
      throw StateError('play requested with no media loaded');
    }
    final audible = player.playingStream
        .firstWhere((isPlaying) => isPlaying)
        .timeout(const Duration(seconds: 12));
    // Errors here would otherwise become an unhandled async error; the timeout
    // above is what reports a source that never starts.
    unawaited(
      player.play().catchError((Object e) {
        debugPrint('[Player] play() failed: $e');
      }),
    );
    await audible;
  }

  /// Guards against overlapping play/pause requests: `_startPlayback()` can
  /// await network work for seconds, and without a guard two taps would
  /// interleave.
  /// A track is loading (source resolution / buffering). During this window the
  /// player reports `playing == false`, so this flag is what lets a pause tap be
  /// understood as "stop the thing that is about to start".
  bool _starting = false;

  /// The user pressed pause before the track finished loading.
  bool _pauseRequested = false;

  /// Live radio streams are played directly rather than through the backend
  /// proxy. Shared by [play] and [_prefetchNextSource] so both agree on what
  /// needs resolving.
  static bool isDirectRadioUrl(String url) {
    final u = url.toLowerCase();
    return u.contains('icecast.vrtcdn.be') ||
        u.contains('qmusic.be') ||
        u.contains('joe.be') ||
        u.contains('streamtheworld.com') ||
        (u.contains('.mp3') && u.contains('dist='));
  }

  /// Guards against overlapping play/pause requests: `_startPlayback()` can
  /// await network work for seconds.
  bool _toggling = false;

  /// Taps that arrived while a toggle was in flight. These used to be discarded
  /// outright, which is the other half of "pause sometimes does nothing".
  int _pendingToggles = 0;

  Future<void> togglePlayPause() {
    _pendingToggles++;
    if (_toggling) return Future<void>.value();
    return _drainToggles();
  }

  /// Applies queued toggles one at a time.
  ///
  /// Each toggle flips the state, so a burst of taps only needs applying by
  /// parity - replaying every tap in order would just re-run a slow start
  /// several times for exactly the same end result.
  Future<void> _drainToggles() async {
    _toggling = true;
    try {
      while (_pendingToggles > 0) {
        var queued = 0;
        while (_pendingToggles > 0) {
          _pendingToggles--;
          queued++;
        }
        if (queued.isOdd) await _applyToggle();
      }
    } finally {
      _toggling = false;
    }
  }

  Future<void> _applyToggle() async {
    // Decide from BOTH sources *plus* "a track is loading". Treating it as
    // playing when any of them says so is what makes pause reliable: using only
    // `_isPlaying` (the mirror) missed a pause whenever the mirror lagged, and
    // using only `_player.playing` missed one while the source was loading.
    final actuallyPlaying = _player.playing || _isPlaying || _starting;
    final willPlay = !actuallyPlaying;
    // Optimistic so the button reacts on the first frame, and deliberately not
    // re-read from the player afterwards - that discarded the flip before the
    // audio pipeline reported back and left the glyph stuck.
    _isPlaying = willPlay;
    notifyListeners();
    try {
      if (willPlay) {
        await _startPlayback();
        // `_startPlayback` swallows its own errors and silently falls back to a
        // second URL, so a source that never started leaves the optimistic value
        // lying. `idle` is the only state that proves nothing loaded.
        if (!_player.playing &&
            _player.processingState == ProcessingState.idle) {
          _isPlaying = false;
        }
      } else if (_starting) {
        // Nothing is audible yet, so don't pause an unloaded player - just make
        // sure the track doesn't start under the user's finger.
        _pauseRequested = true;
        _isPlaying = false;
      } else {
        await _player.pause();
        // A completed pause always settles on false, whatever `playing` happens
        // to report at this instant.
        _isPlaying = false;
      }
      audioHandler?.updatePosition(_position, _duration, _isPlaying);
    } catch (e) {
      debugPrint('[Player] toggle failed: $e');
      _isPlaying = _player.playing;
    } finally {
      notifyListeners();
    }
  }

  Future<void> pause() async {
    await _cancelCrossfade();
    await _player.pause();
    audioHandler?.updatePosition(_position, _duration, false);
  }

  Future<void> resume() async {
    await _startPlayback();
    // A restored track whose source failed to load leaves the player idle;
    // don't broadcast a "playing" state that has no audio behind it.
    if (!_player.playing && _player.processingState == ProcessingState.idle) {
      _isPlaying = false;
      notifyListeners();
      return;
    }
    audioHandler?.updatePosition(_position, _duration, true);
  }

  Future<void> seekTo(Duration position) async {
    if (isRadio) {
      // Radio: only back within listened window, never forward beyond live edge
      final clamped = Duration(
        milliseconds: position.inMilliseconds.clamp(
          0,
          _radioMaxListened.inMilliseconds,
        ),
      );
      await _player.seek(clamped);
      _position = clamped;
      audioHandler?.updatePosition(clamped, _duration, _isPlaying);
      positionNotifier.value = clamped;
      return;
    }
    await _player.seek(position);
    audioHandler?.updatePosition(position, _duration, _isPlaying);
  }

  Future<void> next() async {
    if (isRadio) return;
    if (_queue.isEmpty || _currentIndex >= _queue.length - 1) return;
    await _cancelCrossfade();
    _currentIndex++;
    await play(_queue[_currentIndex], queue: _queue);
  }

  Future<void> previous() async {
    if (isRadio) {
      // Radio: only seek back within listened window, no track switch
      await seekTo(Duration.zero);
      return;
    }
    if (_queue.isEmpty || _currentIndex <= 0) return;
    await _cancelCrossfade();
    if (_position.inSeconds > 3) {
      await seekTo(Duration.zero);
      return;
    }
    _currentIndex--;
    await play(_queue[_currentIndex], queue: _queue);
  }

  Future<void> stop() async {
    await _cancelCrossfade();
    await _player.stop();
    _isPlaying = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    positionNotifier.value = Duration.zero;
    durationNotifier.value = Duration.zero;
    audioHandler?.updatePosition(_position, _duration, false);
    notifyListeners();
  }

  void setQueue(List<TrackModel> tracks, {int startIndex = 0}) {
    _queue = List.from(tracks);
    _currentIndex = startIndex.clamp(0, tracks.isEmpty ? 0 : tracks.length - 1);
    audioHandler?.setQueue(tracks, startIndex: startIndex);
    notifyListeners();
  }

  Future<void> playFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    await play(_queue[index], queue: _queue);
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    if (_currentIndex >= index) {
      _currentIndex = (_currentIndex - 1).clamp(-1, _queue.length - 1);
    }
    if (_currentIndex < 0 && _queue.isNotEmpty) {
      _currentIndex = 0;
    } else if (_queue.isEmpty) {
      _currentTrack = null;
      _currentIndex = -1;
      _isPlaying = false;
    }
    notifyListeners();
  }

  void clearQueue() {
    _queue.clear();
    _currentIndex = -1;
    _currentTrack = null;
    _isPlaying = false;
    notifyListeners();
  }

  /// Moves the queue entry at [from] to [to], keeping [_currentIndex] pointing
  /// at the *same track*.
  ///
  /// The index has to follow the track rather than the slot: moving the playing
  /// track one place up would otherwise leave playback pointing at whatever
  /// slid into the old position.
  void moveQueueItem(int from, int to) {
    if (from < 0 || from >= _queue.length) return;
    if (to < 0 || to >= _queue.length) return;
    if (from == to) return;
    final movingIsCurrent = from == _currentIndex;
    final item = _queue.removeAt(from);
    _queue.insert(to, item);
    if (movingIsCurrent) {
      _currentIndex = to;
    } else if (_currentIndex > from && _currentIndex <= to) {
      // The playing track shifted one place earlier.
      _currentIndex -= 1;
    } else if (_currentIndex < from && _currentIndex >= to) {
      // The playing track shifted one place later.
      _currentIndex += 1;
    }
    audioHandler?.setQueue(_queue, startIndex: _currentIndex);
    notifyListeners();
  }

  /// Moves [from] up one place, if it can.
  void moveQueueUp(int from) => moveQueueItem(from, from - 1);

  /// Moves [from] down one place, if it can.
  void moveQueueDown(int from) => moveQueueItem(from, from + 1);

  /// Removes several queue entries at once.
  ///
  /// Indices are resolved against the *original* queue and removed highest
  /// first, so the caller can pass a UI selection straight through without
  /// re-computing indices as the list shifts underneath.
  void removeFromQueueMany(Iterable<int> indices) {
    final targets = indices.toSet().where((i) => i >= 0 && i < _queue.length);
    if (targets.isEmpty) return;
    final removedCurrent = targets.contains(_currentIndex);
    final ordered = targets.toList()..sort((a, b) => b.compareTo(a));
    for (final i in ordered) {
      _queue.removeAt(i);
    }
    if (_queue.isEmpty) {
      _currentTrack = null;
      _currentIndex = -1;
      _isPlaying = false;
    } else if (removedCurrent) {
      // Playback continues from whatever now sits at the old slot, clamped.
      _currentIndex = _currentIndex.clamp(0, _queue.length - 1);
    } else if (_currentIndex > ordered.last) {
      _currentIndex -= ordered.length;
    }
    audioHandler?.setQueue(_queue, startIndex: _currentIndex);
    notifyListeners();
  }

  /// Moves every selected entry up one place, keeping their relative order.
  ///
  /// Moving a multi-row selection one item at a time would shuffle it instead
  /// of shifting the block, so only the lowest selected index actually moves.
  void moveQueueBlockUp(List<int> indices) {
    final sel = indices.where((i) => i >= 0 && i < _queue.length).toSet();
    if (sel.isEmpty) return;
    final block = sel.toList()..sort();
    final lowest = block.first;
    if (lowest == 0) return;
    final wasCurrent = lowest == _currentIndex;
    final item = _queue.removeAt(lowest);
    _queue.insert(lowest - 1, item);
    if (wasCurrent) {
      _currentIndex = lowest - 1;
    } else if (_currentIndex >= lowest) {
      // Everything from `lowest` onwards shifted up a slot.
      _currentIndex += 1;
    }
    audioHandler?.setQueue(_queue, startIndex: _currentIndex);
    notifyListeners();
  }

  /// Moves every selected entry down one place, keeping their relative order.
  void moveQueueBlockDown(List<int> indices) {
    final sel = indices.where((i) => i >= 0 && i < _queue.length).toSet();
    if (sel.isEmpty) return;
    final block = sel.toList()..sort();
    final highest = block.last;
    if (highest >= _queue.length - 1) return;
    final wasCurrent = highest == _currentIndex;
    final item = _queue.removeAt(highest);
    _queue.insert(highest + 1, item);
    if (wasCurrent) {
      _currentIndex = highest + 1;
    } else if (_currentIndex <= highest) {
      // Everything up to `highest` shifted down a slot.
      _currentIndex -= 1;
    }
    audioHandler?.setQueue(_queue, startIndex: _currentIndex);
    notifyListeners();
  }

  void addToQueue(TrackModel track) {
    _queue.add(track);
    audioHandler?.setQueue(
      _queue,
      startIndex: _currentIndex.clamp(0, _queue.length - 1),
    );
    notifyListeners();
  }

  void addToQueueNext(TrackModel track) {
    if (_currentIndex >= 0 && _currentIndex < _queue.length) {
      _queue.insert(_currentIndex + 1, track);
    } else {
      _queue.add(track);
    }
    audioHandler?.setQueue(
      _queue,
      startIndex: _currentIndex.clamp(0, _queue.length - 1),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _radioDriftTimer?.cancel();
    _savePlayerState();
    _player.dispose();
    // An in-flight fade notices via [_crossfading] and exits on its next
    // tick; disposing the cross player here releases its audio resources.
    _cancelCrossfade().catchError((_) {});
    super.dispose();
  }

  /// Pushes the persisted session into the media session once the audio service
  /// exists, so Android Auto has something to show on connect.
  ///
  /// Waits for [ensureAudioHandler] rather than assuming it: the service may not
  /// be up yet on a cold start, and skipping the restore leaves the car looking at
  /// an empty app for the rest of the drive.
  Future<void> _restoreForAuto() async {
    try {
      await ensureAudioHandler();
      // Wire the notification controls onto this provider now, so pressing
      // play on a restored session actually starts playback. Without this the
      // handler callbacks are still null and the notification would show a
      // "playing" state with no audio behind it.
      _bindHandler();
      // The queue/track are restored asynchronously; make sure that has
      // happened before publishing the session to the media session.
      await _stateLoadFuture;
      final handler = audioHandler;
      if (handler == null) return;
      if (_queue.isEmpty) {
        // Nothing saved yet. Still refresh the browse tree so the car sees the
        // library rather than an empty root.
        AutoLibraryBridge.libraryChanged();
        return;
      }
      await handler.restoreSession(
        queue: _queue,
        index: _currentIndex,
        position: _position,
        wasPlaying: _wasPlayingBeforeRestart,
      );
    } catch (e) {
      debugPrint('[Player] auto session restore skipped: $e');
    }
  }

  Future<void> _loadPlayerState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = prefs.getString('player_queue');
      final currentIndex = prefs.getInt('player_current_index') ?? -1;
      final positionMs = prefs.getInt('player_position_ms') ?? 0;
      if (queueJson != null) {
        final List<dynamic> queueData = jsonDecode(queueJson);
        _queue = queueData.map((data) => TrackModel.fromJson(data)).toList();
        if (currentIndex >= 0 && currentIndex < _queue.length) {
          _currentIndex = currentIndex;
          _currentTrack = _queue[_currentIndex];
          _position = Duration(milliseconds: positionMs);
          // Remembered so the media session can be restored paused; auto-resume is the
          // driver's decision, not ours.
          _wasPlayingBeforeRestart =
              prefs.getBool('player_was_playing') ?? false;
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[Player] Failed to load state: $e');
    }
  }

  Future<void> _savePlayerState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_queue.isNotEmpty) {
        final queueJson = jsonEncode(_queue.map((t) => t.toJson()).toList());
        await prefs.setString('player_queue', queueJson);
        await prefs.setInt('player_current_index', _currentIndex);
        await prefs.setBool('player_was_playing', _isPlaying);
        await prefs.setInt('player_position_ms', _position.inMilliseconds);
      } else {
        await prefs.remove('player_queue');
        await prefs.remove('player_current_index');
        await prefs.remove('player_was_playing');
        await prefs.remove('player_position_ms');
      }
    } catch (e) {
      debugPrint('[Player] Failed to save state: $e');
    }
  }
}
